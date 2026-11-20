#!/usr/bin/env bash
# gh-flow.sh — issue → branch → code → commit → push → issue-comment, with enforced naming.
#
#   gh-flow.sh repo                               # print detected OWNER/NAME/REPO/REMOTE/BASE/PROJECT
#   gh-flow.sh project                            # ensure the repo-named GitHub Project exists, is linked, shows Labels
#   gh-flow.sh start  <type>  "<issue title>" ["<issue body>"]
#   gh-flow.sh work   <issue-number>              # work an existing issue (reopen if closed)
#   gh-flow.sh sync                               # rebase the current dev branch on the latest base (run before editing)
#   gh-flow.sh continue                           # after resolving rebase conflicts (exit 3), finish the rebase
#   gh-flow.sh commit "<summary>" ["<body>"]      # commits STAGED changes
#   gh-flow.sh finish ["<comment body>"]          # push + comment on issue (no PR)
#   gh-flow.sh slug   "<title>"                   # print the branch slug for a title
#   gh-flow.sh check-msg <commit-msg-file>        # used by the commit-msg hook
#   gh-flow.sh install-hook                       # installs .git/hooks/commit-msg
#
# Types:   issue | feature | hotfix | bugfix | chore   (carried by the issue title, not a GitHub label)
# Branch:  <type>/<slug>-<issue#>         e.g. bugfix/login-timeout-42
# Commit:  <type>: <summary>\n\n<body>\n\nRefs #<issue#>
# Issue:   <type>: <title>
# Status:  start/work add ONGOING-DEVELOPMENT; finish replaces it with FOR-AGENT-REVIEW
#
# Everything repo-related is detected from the current checkout:
#   remote   GH_FLOW_REMOTE, else "origin", else the first remote
#   repo     owner/name parsed from that remote's URL
#   base     GH_FLOW_BASE, else the remote's default branch (origin/HEAD, then GitHub API)
#   project  the GitHub Project (user- or org-owned) whose title equals the repo name; created
#            (and linked to the repo) when missing unless GH_FLOW_CREATE_PROJECT=0. Every table
#            view of it shows the Labels column (status labels are visible on the board).
#
# Network steps (push, push confirmation, status labels, issue comment) are retried
# GH_FLOW_RETRIES times (default 3) with 2s/4s/8s backoff.
#
# Portable to macOS bash 3.2 (no ${x,,}, no mapfile, no assoc arrays).
set -euo pipefail

LABELS="issue feature hotfix bugfix chore"
ONGOING_LABEL="ONGOING-DEVELOPMENT"
REVIEW_LABEL="FOR-AGENT-REVIEW"
MAX_SUMMARY=72
MAX_SLUG=40

# Filled in by detect_repo
REMOTE="" OWNER="" NAME="" REPO="" BASE=""

die()  { printf 'gh-flow: error: %s\n' "$*" >&2; exit 1; }
info() { printf 'gh-flow: %s\n' "$*" >&2; }

is_label() {
  case " $LABELS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

slugify() {
  local full s
  full="$(printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [ "${#full}" -le "$MAX_SLUG" ]; then printf '%s' "$full"; return; fi
  # Too long: cut on a word (hyphen) boundary so we don't end mid-word.
  s="$(printf '%s' "$full" | cut -c1-$((MAX_SLUG + 1)))"
  case "$s" in *-*) s="${s%-*}" ;; esac
  printf '%s' "$s" | cut -c1-"$MAX_SLUG" | sed -E 's/-+$//'
}

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH"; }

in_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"; }

current_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null || die "detached HEAD"; }

# Tracked changes only; untracked files don't block branch switches.
is_dirty() { [ -n "$(git status --porcelain --untracked-files=no)" ]; }

# Exit status meaning "rebase stopped on conflicts": resolve them, then run `continue`.
EXIT_CONFLICT=3

rebase_in_progress() {
  [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]
}

report_conflicts() {
  local files; files="$(git diff --name-only --diff-filter=U)"
  info "rebase on $REMOTE/$BASE stopped on conflicts in:"
  printf '%s\n' "$files" | sed 's/^/gh-flow:   /' >&2
  info "resolve each file (keep the intent of both sides, remove all conflict markers),"
  info "then run: gh-flow.sh continue — and re-run the command that was interrupted"
  printf 'CONFLICT=1\n'
  printf '%s\n' "$files" | sed 's/^/CONFLICT_FILE=/'
}

# Rebase the current branch on <remote>/<base>. Extra args go to `git rebase` (e.g. --autostash).
# On conflicts: leave the rebase in progress, list the files, exit $EXIT_CONFLICT.
rebase_onto_base() {
  git rebase --quiet "$@" "$REMOTE/$BASE" >/dev/null 2>&1 && return 0
  rebase_in_progress && { report_conflicts; exit "$EXIT_CONFLICT"; }
  die "rebase on $REMOTE/$BASE failed"
}

# retry <description> <command...>: run a network step up to GH_FLOW_RETRIES times
# (default 3), waiting 2s, 4s, 8s… between attempts. Returns the last exit status.
retry() {
  local what="$1" max="${GH_FLOW_RETRIES:-3}" delay=2 n=1
  shift
  while :; do
    "$@" && return 0
    [ "$n" -ge "$max" ] && { info "$what: failed after $max attempts"; return 1; }
    info "$what: attempt $n/$max failed; retrying in ${delay}s"
    sleep "$delay"
    n=$((n + 1)); delay=$((delay * 2))
  done
}

# Detect remote, owner/name, and base branch from the current checkout.
detect_repo() {
  [ -n "$REPO" ] && return 0
  need git; need gh; in_repo

  REMOTE="${GH_FLOW_REMOTE:-}"
  if [ -z "$REMOTE" ]; then
    if git remote get-url origin >/dev/null 2>&1; then REMOTE="origin"
    else REMOTE="$(git remote | head -1)"; fi
  fi
  [ -n "$REMOTE" ] || die "no git remote configured"

  # Works for https://host/owner/name(.git), git@host:owner/name(.git) and ssh:// URLs.
  local url path
  url="$(git remote get-url "$REMOTE")"
  path="$(printf '%s' "$url" | sed -E 's#\.git$##; s#/+$##')"
  NAME="${path##*/}"
  path="${path%/*}"
  OWNER="${path##*[/:]}"
  [ -n "$OWNER" ] && [ -n "$NAME" ] || die "could not parse owner/name from remote '$REMOTE' ($url)"
  REPO="$OWNER/$NAME"

  BASE="${GH_FLOW_BASE:-}"
  if [ -z "$BASE" ]; then
    BASE="$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)"
    BASE="${BASE#"$REMOTE"/}"
  fi
  if [ -z "$BASE" ]; then
    BASE="$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
  fi
  [ -n "$BASE" ] || die "could not detect the default branch of $REPO; set GH_FLOW_BASE"
}

# Parse "<type>/<slug>-<n>" → sets BR_LABEL, BR_ISSUE
parse_branch() {
  local b="$1"
  BR_LABEL="${b%%/*}"
  BR_ISSUE="$(printf '%s' "$b" | sed -nE 's#^[a-z]+/.+-([0-9]+)$#\1#p')"
  is_label "$BR_LABEL" && [ -n "$BR_ISSUE" ] \
    || die "branch '$b' does not match <type>/<slug>-<issue#> (types: $LABELS)"
}

# Make sure label <name> exists with exactly that casing. GitHub label names are
# case-insensitive, so an existing "for-agent-review" is renamed, not duplicated.
ensure_label() {
  local l="$1" color="$2" desc="$3" existing
  existing="$(gh label list -R "$REPO" --limit 500 --json name --jq '.[].name' | grep -ix "$l" | head -1 || true)"
  if [ -z "$existing" ]; then
    info "creating label '$l'"
    gh label create "$l" -R "$REPO" --color "$color" --description "$desc" >/dev/null
  elif [ "$existing" != "$l" ]; then
    info "renaming label '$existing' to '$l'"
    gh label edit "$existing" -R "$REPO" --name "$l" >/dev/null
  fi
}

ensure_status_labels() {
  ensure_label "$ONGOING_LABEL" "FBCA04" "Development in progress"
  ensure_label "$REVIEW_LABEL" "9966CC" "Development done; ready for agent/AI code review"
}

# Swap the status label on an issue: set_status <issue#> <add> <remove>
# One attempt: swap the labels, then re-read them. Non-zero unless the issue
# has <add> and not <remove>.
try_set_status() {
  local labels
  gh issue edit "$1" -R "$REPO" --add-label "$2" --remove-label "$3" >/dev/null 2>&1 || true
  labels="$(gh issue view "$1" -R "$REPO" --json labels --jq '.labels[].name' 2>/dev/null)" || return 1
  printf '%s\n' "$labels" | grep -qxF "$2" || return 1
  ! printf '%s\n' "$labels" | grep -qxF "$3"
}

# set_status <issue#> <add> <remove>, with retries. Returns non-zero if it never sticks.
set_status() {
  retry "ensure status labels" ensure_status_labels || return 1
  info "issue #$1: label '$2' (removing '$3')"
  retry "set label '$2' on issue #$1" try_set_status "$1" "$2" "$3"
}

# One push attempt. A previously pushed branch is updated with a lease, since the
# rebase rewrote it (refuses if someone else pushed to it in the meantime).
try_push() {
  local branch="$1"
  if git ls-remote --exit-code --heads "$REMOTE" "$branch" >/dev/null 2>&1; then
    git fetch --quiet "$REMOTE" "$branch" || return 1
    git push --quiet --force-with-lease="$branch:$REMOTE/$branch" -u "$REMOTE" "$branch"
  else
    git push --quiet -u "$REMOTE" "$branch"
  fi
}

# Succeeds when GitHub's <branch> points at <sha>.
remote_is_at() {
  [ "$(git ls-remote --heads "$REMOTE" "$1" 2>/dev/null | cut -f1)" = "$2" ]
}

# Record the development branch in the issue body (once).
record_branch_in_issue() {
  local num="$1" branch="$2" body tmpfile
  body="$(gh issue view "$num" -R "$REPO" --json body --jq '.body' 2>/dev/null || true)"
  printf '%s' "$body" | grep -qF "Branch: \`$branch\`" && return 0
  info "updating issue #$num with development branch"
  tmpfile="$(mktemp)" || die "could not create temp file"
  printf '%s\n\n## Development\n\nBranch: `%s` (from `%s`)\n' "$body" "$branch" "$BASE" > "$tmpfile"
  gh issue edit "$num" -R "$REPO" --body-file "$tmpfile" >/dev/null \
    || info "warning: could not update issue body with branch"
  rm -f "$tmpfile"
}

# Print the number of the GitHub Project titled exactly like the repo (empty if none).
# `gh project list --owner` works for both user- and org-owned projects.
find_project() {
  local out
  if ! out="$(gh project list --owner "$OWNER" --limit 100 --format json \
      --jq ".projects[] | select(.title == \"$NAME\") | .number" 2>&1)"; then
    case "$out" in
      *scope*) info "warning: gh token lacks project access; run: gh auth refresh -s project" ;;
      *)       info "warning: could not list projects for '$OWNER': $out" ;;
    esac
    return 0
  fi
  printf '%s' "$out" | head -1
}

# Add an issue to the repo-named GitHub Project and set its Status to "In Progress".
# Make the Labels field visible in every table view of project <number> (idempotent).
ensure_labels_column() {
  local number="$1" project_id data labels_id views view_id body
  command -v jq >/dev/null 2>&1 || { info "warning: jq not found; Labels column not checked"; return 0; }
  project_id="$(gh project view "$number" --owner "$OWNER" --format json --jq '.id' 2>/dev/null || true)"
  [ -n "$project_id" ] || { info "warning: could not read project #$number; Labels column not checked"; return 0; }
  data="$(gh api graphql -f id="$project_id" -f query='query($id: ID!) { node(id: $id) { ... on ProjectV2 {
      fields(first: 50) { nodes { ... on ProjectV2FieldCommon { id name } } }
      views(first: 20) { nodes { id layout fields(first: 50) { nodes { ... on ProjectV2FieldCommon { id } } } } } } } }' \
    2>/dev/null || true)"
  labels_id="$(printf '%s' "$data" | jq -r '.data.node.fields.nodes[]? | select(.name == "Labels") | .id' 2>/dev/null || true)"
  [ -n "$labels_id" ] || { info "warning: project #$number has no Labels field"; return 0; }
  views="$(printf '%s' "$data" | jq -c --arg l "$labels_id" '.data.node.views.nodes[]?
    | select(.layout == "TABLE_LAYOUT") | {id, ids: [.fields.nodes[].id]} | select(.ids | index($l) | not)' 2>/dev/null || true)"
  [ -n "$views" ] || return 0
  printf '%s\n' "$views" | while IFS= read -r view; do
    view_id="$(printf '%s' "$view" | jq -r '.id')"
    body="$(jq -n --argjson v "$view" --arg l "$labels_id" '{
      query: "mutation($v: ID!, $ids: [ID!]!) { updateProjectV2View(input: {viewId: $v, configuration: {visibleFieldIds: $ids}}) { projectV2View { id } } }",
      variables: {v: $v.id, ids: ($v.ids + [$l])}}')"
    if printf '%s' "$body" | gh api graphql --input - >/dev/null 2>&1; then
      info "project #$number: Labels column enabled (view $view_id)"
    else
      info "warning: could not enable the Labels column on project #$number (view $view_id)"
    fi
  done
}

# Print the repo-named project's number, creating and linking it first when missing
# (unless GH_FLOW_CREATE_PROJECT=0); always makes sure its Labels column is visible.
ensure_project() {
  local number
  number="$(find_project)"
  if [ -z "$number" ] && [ "${GH_FLOW_CREATE_PROJECT:-1}" != "0" ]; then
    if number="$(gh project create --owner "$OWNER" --title "$NAME" --format json --jq '.number' 2>/dev/null)" \
        && [ -n "$number" ]; then
      info "created GitHub Project #$number ('$NAME') for '$OWNER'"
      gh project link "$number" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
        || info "warning: could not link project #$number to $REPO"
    else
      info "warning: could not create a GitHub Project '$NAME' for '$OWNER' (token needs the project scope)"
      number=""
    fi
  fi
  [ -n "$number" ] && ensure_labels_column "$number"
  printf '%s' "$number"
}

project_add_in_progress() {
  local url="$1" number item_id project_id ids field_id option_id
  number="$(ensure_project)"
  if [ -z "$number" ]; then
    info "warning: no GitHub Project titled '$NAME' for '$OWNER' (GH_FLOW_CREATE_PROJECT=0 or create failed); skipping project add"
    return 0
  fi
  info "adding issue to project #$number ('$NAME')"

  item_id="$(gh project item-add "$number" --owner "$OWNER" --url "$url" --format json --jq '.id' 2>/dev/null || true)"
  [ -n "$item_id" ] || { info "warning: could not add issue to project #$number"; return 0; }

  project_id="$(gh project view "$number" --owner "$OWNER" --format json --jq '.id' 2>/dev/null || true)"
  ids="$(gh project field-list "$number" --owner "$OWNER" --format json \
    --jq '.fields[] | select(.name == "Status") | .id + " " + ([.options[]? | select(.name | ascii_downcase == "in progress") | .id][0] // "")' \
    2>/dev/null || true)"
  field_id="${ids%% *}"
  option_id="${ids#* }"
  if [ -z "$project_id" ] || [ -z "$field_id" ] || [ -z "$option_id" ] || [ "$option_id" = "$ids" ]; then
    info "warning: project #$number has no Status field with an 'In Progress' option; status not set"
    return 0
  fi
  gh project item-edit --project-id "$project_id" --id "$item_id" \
    --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null \
    || info "warning: could not set status to In Progress"
}

# Create or check out the development branch for <issue#>, based on the latest <remote>/<base>.
# A new branch is created on GitHub with `gh issue develop`, which links it to the issue
# (shown under the issue's "Development" section), then checked out locally.
checkout_flow_branch() {
  local branch="$1" num="$2"
  git fetch --quiet "$REMOTE" "$BASE"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    info "branch '$branch' already exists; rebasing on $REMOTE/$BASE"
    git checkout --quiet "$branch"
    rebase_onto_base
  elif git ls-remote --exit-code --heads "$REMOTE" "$branch" >/dev/null 2>&1; then
    info "branch '$branch' exists on $REMOTE; creating local tracking branch and rebasing on $REMOTE/$BASE"
    git fetch --quiet "$REMOTE" "$branch"
    git switch --quiet -c "$branch" --track "$REMOTE/$branch"
    rebase_onto_base
  else
    local out
    if out="$(gh issue develop "$num" -R "$REPO" --name "$branch" --base "$BASE" 2>&1)"; then
      info "created branch '$branch' on GitHub, linked to issue #$num"
      git fetch --quiet "$REMOTE" "$branch"
      git switch --quiet -c "$branch" --track "$REMOTE/$branch"
    else
      info "warning: could not create a linked branch on GitHub ($out); creating it locally"
      info "         it will be linked after the first push (finish)"
      git switch --quiet -c "$branch" "$REMOTE/$BASE"
    fi
  fi
}

is_linked() {
  gh issue develop "$1" -R "$REPO" --list 2>/dev/null | cut -f1 | grep -qxF "$2"
}

# Make sure <branch> is listed under the issue's "Development" section. Never deletes anything.
# GitHub only links branches it creates itself (gh issue develop / createLinkedBranch fail
# when the ref already exists). So:
#   - not on the remote yet → have GitHub create it, linked, at <remote>/<base>; the caller's
#     push then fast-forwards it to the local commits
#   - already on the remote but unlinked → warn; it can't be linked without re-creating it
link_branch() {
  local num="$1" branch="$2" out
  is_linked "$num" "$branch" && return 0

  if git ls-remote --exit-code --heads "$REMOTE" "$branch" >/dev/null 2>&1; then
    info "warning: '$branch' was pushed before it was linked; GitHub can't link an existing"
    info "         branch, so it won't appear under issue #$num's Development section"
    return 0
  fi

  if out="$(gh issue develop "$num" -R "$REPO" --name "$branch" --base "$BASE" 2>&1)"; then
    info "created linked branch '$branch' on GitHub for issue #$num"
  else
    info "warning: could not link '$branch' to issue #$num: $out"
  fi
}

print_result() {
  printf 'REPO=%s\nBASE=%s\nREMOTE=%s\nISSUE=%s\nISSUE_URL=%s\nBRANCH=%s\nLABEL=%s\nTITLE=%s\n' \
    "$REPO" "$BASE" "$REMOTE" "$1" "$2" "$3" "$4" "$5"
}

cmd_project() {
  detect_repo
  local number
  number="$(ensure_project)"
  [ -n "$number" ] || die "no GitHub Project titled '$NAME' for '$OWNER'"
  printf 'PROJECT=%s\n' "$number"
}

cmd_repo() {
  detect_repo
  printf 'OWNER=%s\nNAME=%s\nREPO=%s\nREMOTE=%s\nBASE=%s\nPROJECT=%s\n' \
    "$OWNER" "$NAME" "$REPO" "$REMOTE" "$BASE" "$(find_project)"
}

cmd_start() {
  [ $# -ge 2 ] || die "usage: start <type> \"<issue title>\" [\"<issue body>\"]"
  local label="$1" title="$2" body="${3:-}"
  is_label "$label" || die "invalid type '$label' (allowed: $LABELS)"
  [ -n "$title" ] || die "issue title is empty"
  detect_repo
  is_dirty && die "working tree has uncommitted changes; commit or stash them first"

  local slug; slug="$(slugify "$title")"
  [ -n "$slug" ] || die "could not derive a branch slug from title '$title'"

  # The type lives in the title only; the only label set is the status label below.
  [ -n "$body" ] || body="_Created by gh-flow._"
  local url num
  url="$(gh issue create -R "$REPO" --title "$label: $title" --body "$body" --assignee "@me")"
  num="${url##*/}"
  case "$num" in ''|*[!0-9]*) die "could not parse issue number from '$url'" ;; esac

  project_add_in_progress "$url"

  local branch="$label/$slug-$num"
  checkout_flow_branch "$branch" "$num"
  record_branch_in_issue "$num" "$branch"
  set_status "$num" "$ONGOING_LABEL" "$REVIEW_LABEL" || true

  info "issue:  #$num $url"
  info "branch: $branch (from $REMOTE/$BASE)"
  print_result "$num" "$url" "$branch" "$label" "$title"
}

cmd_work() {
  [ $# -ge 1 ] || die "usage: work <issue-number>"
  local num="$1"
  case "$num" in ''|*[!0-9]*) die "issue number must be numeric: '$num'" ;; esac
  detect_repo
  is_dirty && die "working tree has uncommitted changes; commit or stash them first"

  # Line 1: state, line 2: url, line 3: comma-separated labels, line 4: title.
  local meta state url labels title
  meta="$(gh issue view "$num" -R "$REPO" --json state,url,labels,title \
    --jq '.state, .url, ([.labels[].name] | join(",")), .title' 2>/dev/null)" \
    || die "could not fetch issue #$num from $REPO"
  state="$(printf '%s\n' "$meta" | sed -n '1p')"
  url="$(printf '%s\n' "$meta" | sed -n '2p')"
  labels="$(printf '%s\n' "$meta" | sed -n '3p')"
  title="$(printf '%s\n' "$meta" | sed -n '4,$p')"

  if [ "$state" = "CLOSED" ]; then
    info "issue #$num is closed; reopening"
    gh issue reopen "$num" -R "$REPO" >/dev/null || info "warning: could not reopen issue #$num"
  fi

  # Type: the "<type>: " prefix of the title, else a legacy type label, else "issue".
  local label="issue" l prefix
  prefix="$(printf '%s' "$title" | sed -nE 's/^([A-Za-z]+):.*/\1/p' | tr '[:upper:]' '[:lower:]')"
  if [ -n "$prefix" ] && is_label "$prefix"; then
    label="$prefix"
  else
    local IFS_OLD="$IFS"; IFS=","
    for l in $labels; do
      if is_label "$l"; then label="$l"; break; fi
    done
    IFS="$IFS_OLD"
  fi

  # Slug from the title without any "<word>: " prefix.
  local slug; slug="$(slugify "$(printf '%s' "$title" | sed -E 's/^[A-Za-z-]+:[[:space:]]*//')")"
  [ -n "$slug" ] || die "could not derive a branch slug from title '$title'"

  gh issue edit "$num" -R "$REPO" --add-assignee "@me" >/dev/null || info "warning: could not assign issue"
  project_add_in_progress "$url"

  # Work commences: ONGOING-DEVELOPMENT first; the rebase on <base> below is part of it.
  # If the rebase stops on conflicts (exit 3), resolve, run `continue`, then re-run `work`.
  set_status "$num" "$ONGOING_LABEL" "$REVIEW_LABEL" || true

  local branch="$label/$slug-$num"
  checkout_flow_branch "$branch" "$num"
  link_branch "$num" "$branch"
  record_branch_in_issue "$num" "$branch"

  info "issue:  #$num $url"
  info "branch: $branch (from $REMOTE/$BASE)"
  print_result "$num" "$url" "$branch" "$label" "$title"
  # Body last: it is multi-line, so everything after BODY= belongs to it.
  printf 'BODY=\n'
  gh issue view "$num" -R "$REPO" --json body --jq '.body'
}

# Bring the current development branch up to date with the latest <remote>/<base>.
# Run before every round of editing. Uncommitted edits are stashed and re-applied.
cmd_sync() {
  detect_repo
  local branch; branch="$(current_branch)"
  parse_branch "$branch"
  git fetch --quiet "$REMOTE" "$BASE"
  if git merge-base --is-ancestor "$REMOTE/$BASE" HEAD; then
    info "'$branch' is up to date with $REMOTE/$BASE"
  else
    info "rebasing '$branch' on $REMOTE/$BASE"
    rebase_onto_base --autostash
  fi
  printf 'REPO=%s\nBASE=%s\nREMOTE=%s\nISSUE=%s\nBRANCH=%s\n' "$REPO" "$BASE" "$REMOTE" "$BR_ISSUE" "$branch"
}

# Finish a rebase that stopped on conflicts, after the files have been resolved.
# Refuses while conflict markers remain; stops again (exit $EXIT_CONFLICT) if a
# later commit conflicts too.
cmd_continue() {
  detect_repo
  rebase_in_progress || die "no rebase in progress"
  # Stage the resolutions. Mid-rebase, the only tracked changes are conflict fixes
  # (sync's --autostash parks other edits), and a file staged by an earlier, refused
  # `continue` must be re-staged with its fixed content.
  git add -u
  # `git diff --check` exits non-zero when it finds problems, so capture its output first
  # (piping it straight into grep would hide a match under `set -o pipefail`).
  local check markers
  check="$(git diff --cached --check 2>&1 || true)"
  markers="$(printf '%s\n' "$check" | grep 'leftover conflict marker' || true)"
  if [ -n "$markers" ]; then
    printf '%s\n' "$markers" | sed 's/^/gh-flow:   /' >&2
    die "conflict markers remain; finish resolving, then run continue again"
  fi
  if ! GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
    rebase_in_progress && { report_conflicts; exit "$EXIT_CONFLICT"; }
    die "git rebase --continue failed"
  fi
  rebase_in_progress && { report_conflicts; exit "$EXIT_CONFLICT"; }
  info "rebase on $REMOTE/$BASE complete; re-run the command that was interrupted"
  printf 'CONFLICT=0\n'
}

cmd_commit() {
  [ $# -ge 1 ] || die "usage: commit \"<summary>\" [\"<body>\"]"
  local summary="$1" body="${2:-}"
  need git; in_repo
  local branch; branch="$(current_branch)"
  parse_branch "$branch"

  # Allow the caller to pass "label: summary" by mistake — strip a duplicate prefix.
  summary="${summary#"$BR_LABEL": }"
  [ -n "$summary" ] || die "summary is empty"
  local subject="$BR_LABEL: $summary"
  [ "${#subject}" -le "$MAX_SUMMARY" ] || die "subject is ${#subject} chars (max $MAX_SUMMARY): $subject"

  git diff --cached --quiet && die "nothing staged; 'git add' the files for this commit first"

  local msg; msg="$(mktemp)"
  {
    printf '%s\n' "$subject"
    if [ -n "$body" ]; then printf '\n%s\n' "$body"; fi
    printf '\nRefs #%s\n' "$BR_ISSUE"
  } > "$msg"

  git commit --quiet -F "$msg" || { rm -f "$msg"; die "git commit failed (hook rejected?)"; }
  rm -f "$msg"
  info "committed: $(git log -1 --format='%h %s')"
}

cmd_finish() {
  local comment_body="${1:-}"
  detect_repo
  local branch; branch="$(current_branch)"
  parse_branch "$branch"

  is_dirty && die "uncommitted changes present; commit them (gh-flow.sh commit) before finishing"
  git fetch --quiet "$REMOTE" "$BASE"
  rebase_onto_base

  local ahead; ahead="$(git rev-list --count "$REMOTE/$BASE..HEAD")"
  [ "$ahead" -gt 0 ] || die "no commits on '$branch' ahead of $REMOTE/$BASE"

  # If the branch isn't on GitHub yet, have GitHub create it linked to the issue first;
  # the push below then moves it to the local commits.
  link_branch "$BR_ISSUE" "$branch"

  # 1. Push (retried). Failure leaves the issue in ONGOING-DEVELOPMENT.
  local local_sha; local_sha="$(git rev-parse HEAD)"
  retry "push '$branch'" try_push "$branch" \
    || die "push failed; issue #$BR_ISSUE stays '$ONGOING_LABEL'. Fix the cause and re-run finish"

  # 2. Confirm GitHub's branch == local HEAD (retried, in case GitHub is slow to report it).
  retry "confirm push of '$branch'" remote_is_at "$branch" "$local_sha" \
    || die "push not confirmed ($REMOTE/$branch is not at ${local_sha:0:7}); issue #$BR_ISSUE stays '$ONGOING_LABEL'"
  info "pushed '$branch' at ${local_sha:0:7}"

  # 3. Only after a confirmed push: ONGOING-DEVELOPMENT → FOR-AGENT-REVIEW (retried + verified).
  record_branch_in_issue "$BR_ISSUE" "$branch"
  set_status "$BR_ISSUE" "$REVIEW_LABEL" "$ONGOING_LABEL" \
    || die "pushed, but could not move issue #$BR_ISSUE to '$REVIEW_LABEL'; re-run finish to retry"
  info "issue #$BR_ISSUE: '$ONGOING_LABEL' → '$REVIEW_LABEL'"

  local range="$REMOTE/$BASE...HEAD"
  local f; f="$(mktemp)"
  {
    if [ -n "$comment_body" ]; then
      printf '%s\n\n' "$comment_body"
    else
      printf '## Changes Summary\n\n'
    fi
    printf '### File Statistics\n\n```\n%s\n```\n\n' "$(git diff --stat "$range" | tail -40)"
    printf '### Detailed Changes (Line by Line)\n\n'
    git diff --name-only "$range" | while IFS= read -r file; do
      printf '#### `%s`\n\n```diff\n' "$file"
      git diff "$range" -- "$file" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | head -20 || true
      printf '```\n\n'
    done
    printf '### Branch\n\n`%s` (based on `%s`)\n\n' "$branch" "$BASE"
    printf '### Commits\n\n'
    git log --reverse --format='- %s' "$REMOTE/$BASE..HEAD"
  } > "$f"

  # 4. Changes comment (retried).
  retry "comment on issue #$BR_ISSUE" gh issue comment "$BR_ISSUE" -R "$REPO" --body-file "$f" >/dev/null \
    || { rm -f "$f"; die "pushed and labeled '$REVIEW_LABEL', but failed to post the changes comment on issue #$BR_ISSUE"; }
  rm -f "$f"
  info "commented on issue #$BR_ISSUE"

  printf 'REPO=%s\nISSUE=%s\nBRANCH=%s\nSHA=%s\nSTATUS=%s\n' "$REPO" "$BR_ISSUE" "$branch" "$local_sha" "$REVIEW_LABEL"
}

cmd_check_msg() {
  [ $# -eq 1 ] || die "usage: check-msg <commit-msg-file>"
  local first; first="$(sed -n '1p' "$1")"
  case "$first" in
    Merge\ *|Revert\ *|fixup!\ *|squash!\ *|amend!\ *) exit 0 ;;
  esac
  local re="^(${LABELS// /|}): .+"
  if ! printf '%s' "$first" | grep -Eq "$re"; then
    printf 'commit-msg: subject must be "<type>: <summary>" (types: %s)\n  got: %s\n' "$LABELS" "$first" >&2
    exit 1
  fi
  if [ "${#first}" -gt "$MAX_SUMMARY" ]; then
    printf 'commit-msg: subject is %s chars (max %s)\n' "${#first}" "$MAX_SUMMARY" >&2
    exit 1
  fi
  # If on a flow branch, the commit label must match the branch label.
  local b; b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  local bl="${b%%/*}"
  if is_label "$bl" && [ "${first%%:*}" != "$bl" ]; then
    printf 'commit-msg: type "%s" does not match branch type "%s"\n' "${first%%:*}" "$bl" >&2
    exit 1
  fi
}

cmd_install_hook() {
  need git; in_repo
  local hooks; hooks="$(git rev-parse --git-path hooks)"
  local self; self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  local root; root="$(git rev-parse --show-toplevel)"
  # Prefer a repo-relative path so the hook survives moving the checkout.
  # Otherwise keep a global install home-relative so the hook isn't tied to one user name.
  case "$self" in
    "$root"/*) self="\$(git rev-parse --show-toplevel)/${self#"$root"/}" ;;
    "$HOME"/*) self="\$HOME/${self#"$HOME"/}" ;;
  esac
  mkdir -p "$hooks"
  if [ -e "$hooks/commit-msg" ] && ! grep -q 'gh-flow' "$hooks/commit-msg"; then
    die "$hooks/commit-msg already exists and is not gh-flow's; merge it manually"
  fi
  cat > "$hooks/commit-msg" <<EOF
#!/usr/bin/env bash
# installed by gh-flow
exec bash "$self" check-msg "\$1"
EOF
  chmod +x "$hooks/commit-msg"
  info "installed $hooks/commit-msg"
}

# Print the header comment block (line 2 up to the first non-comment line).
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

main() {
  [ $# -ge 1 ] || { usage; exit 1; }
  local sub="$1"; shift
  case "$sub" in
    repo)         cmd_repo ;;
    project)      cmd_project ;;
    start)        cmd_start "$@" ;;
    work)         cmd_work "$@" ;;
    sync)         cmd_sync ;;
    continue)     cmd_continue ;;
    commit)       cmd_commit "$@" ;;
    finish)       cmd_finish "$@" ;;
    check-msg)    cmd_check_msg "$@" ;;
    install-hook) cmd_install_hook ;;
    slug)         printf '%s\n' "$(slugify "$*")" ;;
    -h|--help|help) usage ;;
    *) die "unknown subcommand '$sub' (repo|project|start|work|sync|continue|commit|finish|slug|check-msg|install-hook)" ;;
  esac
}

main "$@"
