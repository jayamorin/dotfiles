#!/usr/bin/env bash
# gh-merge.sh — merge a PR only after its issue's acceptance criteria are checked off.
#
#   gh-merge.sh resolve  [<pr>]               # PR (default: the current branch's) → its issue, head, base, merge state
#   gh-merge.sh criteria <issue>              # numbered acceptance criteria: N<TAB>x|-<TAB>text  (x = checked)
#   gh-merge.sh tick     <issue> <n> [<n>...] # check off criteria N… in the issue body, then confirm on GitHub
#   gh-merge.sh merge    <pr>                 # merge with a method the repo allows (rebase > squash > merge); keeps the branch
#
# The issue is found in this order: the issues the PR closes (closingIssuesReferences), the "-<n>" suffix of a
# gh-flow branch (<type>/<slug>-<n>), then a single "Refs #n" / "Closes #n" in the PR body or its commits.
# `resolve` also reports whether the issue lists the PR's head branch or the PR under Development (LINKED=yes|no|unknown)
# and whether merging will close the issue on its own (AUTO_CLOSE=yes|no: the PR is one of its closing references).
#
# Criteria are the "- [ ]" / "- [x]" items under the issue's "## Acceptance criteria" heading (up to the next "## ").
# `tick` changes only "[ ]" → "[x]" on those lines; every other byte of the body stays as it was.
#
# Exit codes: 0 ok · 1 error · 2 issue ambiguous or not found · 4 no acceptance criteria · 5 PR not mergeable
# Portable to macOS bash 3.2 (no mapfile, no assoc arrays). Needs git and an authenticated gh.
set -euo pipefail

die()  { printf 'gh-merge: error: %s\n' "$*" >&2; exit "${2:-1}"; }
info() { printf 'gh-merge: %s\n' "$*" >&2; }

need_number() { case "${1:-}" in ''|*[!0-9]*) die "expected a number, got '${1:-}'" ;; esac; }

repo() {
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || die "not in a GitHub repository (or gh isn't signed in)"
}

# Awk program shared by `criteria` and `tick`: walks the body, finds checkboxes in the Acceptance criteria section.
# With TICK set to " 2 5 ", rewrites those checkboxes to [x] and prints the whole body; otherwise lists the criteria.
CRITERIA_AWK='
function heading(l,  t) { t = tolower(l); sub(/\r$/, "", t); return t }
{
  line = $0
  if (line ~ /^##[ \t]/) {
    h = heading(line)
    in_section = (h ~ /^##[ \t]+acceptance criteria[ \t]*$/)
  } else if (in_section && line ~ /^[ \t]*[-*][ \t]+\[[ xX]\][ \t]/) {
    n++
    if (TICK == "") {
      state = (line ~ /\[[xX]\]/) ? "x" : "-"
      text = line; sub(/^[ \t]*[-*][ \t]+\[[ xX]\][ \t]+/, "", text); sub(/\r$/, "", text)
      printf "%d\t%s\t%s\n", n, state, text
    } else if (index(TICK, " " n " ") > 0) {
      sub(/\[ \]/, "[x]", line)
    }
  }
  if (TICK != "") print line
}'

body_of() { gh issue view "$1" -R "$(repo)" --json body -q .body; }

cmd_criteria() {
  need_number "${1:-}"
  local out
  out="$(body_of "$1" | awk -v TICK="" "$CRITERIA_AWK")"
  [ -n "$out" ] || die "issue #$1 has no checkbox items under '## Acceptance criteria'" 4
  printf '%s\n' "$out"
}

cmd_tick() {
  need_number "${1:-}"
  local issue=$1; shift
  [ $# -gt 0 ] || die "tick: give at least one criterion number"
  local list=" " n total tmp r
  for n in "$@"; do need_number "$n"; list="$list$n "; done
  r="$(repo)"
  total="$(body_of "$issue" | awk -v TICK="" "$CRITERIA_AWK" | wc -l | tr -d ' ')"
  [ "$total" -gt 0 ] || die "issue #$issue has no acceptance criteria" 4
  for n in "$@"; do [ "$n" -ge 1 ] && [ "$n" -le "$total" ] || die "criterion $n doesn't exist (issue #$issue has $total)"; done
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT
  body_of "$issue" | awk -v TICK="$list" "$CRITERIA_AWK" > "$tmp"
  gh issue edit "$issue" -R "$r" --body-file "$tmp" >/dev/null
  # Confirm on GitHub: every requested criterion now reads [x].
  local now missing=""
  now="$(cmd_criteria "$issue")"
  for n in "$@"; do
    printf '%s\n' "$now" | awk -F'\t' -v n="$n" '$1 == n && $2 == "x" { ok = 1 } END { exit !ok }' || missing="$missing $n"
  done
  [ -z "$missing" ] || die "criteria not checked on GitHub after the edit:$missing"
  printf 'TICKED=%s\n' "$(printf '%s' "$list" | sed 's/^ //; s/ $//')"
}

cmd_resolve() {
  local pr=${1:-} r
  r="$(repo)"
  if [ -z "$pr" ]; then
    pr="$(gh pr view --json number -q .number 2>/dev/null)" || die "no PR for the current branch; give a PR number"
  fi
  need_number "$pr"
  local head base state mergeable closing refs issue="" via=""
  head="$(gh pr view "$pr" -R "$r" --json headRefName -q .headRefName)"
  base="$(gh pr view "$pr" -R "$r" --json baseRefName -q .baseRefName)"
  state="$(gh pr view "$pr" -R "$r" --json state -q .state)"
  mergeable="$(gh pr view "$pr" -R "$r" --json mergeable -q .mergeable)"
  closing="$(gh pr view "$pr" -R "$r" --json closingIssuesReferences -q '.closingIssuesReferences[].number' | sort -un)"

  if [ "$(printf '%s' "$closing" | grep -c .)" -eq 1 ]; then
    issue=$closing; via="closes"
  elif printf '%s' "$head" | grep -qE -- '-[0-9]+$'; then
    issue="$(printf '%s' "$head" | grep -oE '[0-9]+$')"; via="branch"
  else
    refs="$( { gh pr view "$pr" -R "$r" --json body -q .body; gh pr view "$pr" -R "$r" --json commits -q '.commits[].messageBody, .commits[].messageHeadline'; } \
      | { grep -oiE '(refs|closes|fixes|resolves)[[:space:]]+#[0-9]+' || true; } | grep -oE '[0-9]+' | sort -un || true)"
    if [ "$(printf '%s' "$refs" | grep -c .)" -eq 1 ]; then issue=$refs; via="refs"; fi
  fi
  if [ -z "$issue" ]; then
    printf 'PR=%s\nHEAD=%s\nCANDIDATES=%s\n' "$pr" "$head" "$(printf '%s %s' "$closing" "${refs:-}" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
    die "couldn't tell which issue PR #$pr belongs to; name it" 2
  fi
  gh issue view "$issue" -R "$r" --json number >/dev/null 2>&1 || die "issue #$issue (from the $via) doesn't exist in $r" 2

  # Does the issue list the PR's head branch under Development? (GitHub links branches it created for the issue.)
  local owner=${r%%/*} name=${r#*/} linked
  linked="$(gh api graphql -f query='query($o:String!,$n:String!,$i:Int!){repository(owner:$o,name:$n){issue(number:$i){linkedBranches(first:50){nodes{ref{name}}}}}}' \
      -F o="$owner" -F n="$name" -F i="$issue" -q '.data.repository.issue.linkedBranches.nodes[].ref.name' 2>/dev/null)" \
    && { printf '%s\n' "$linked" | grep -qxF -- "$head" && linked=yes || linked=no; } \
    || linked=unknown
  # Once a PR is opened from a linked branch, GitHub moves the link to the PR: the branch leaves linkedBranches and
  # the issue becomes one of the PR's closing references, so merging the PR closes the issue automatically.
  local auto_close=no
  printf '%s\n' "$closing" | grep -qxF -- "$issue" && { auto_close=yes; linked=yes; }

  printf 'REPO=%s\nPR=%s\nSTATE=%s\nMERGEABLE=%s\nHEAD=%s\nBASE=%s\nISSUE=%s\nISSUE_VIA=%s\nLINKED=%s\nAUTO_CLOSE=%s\nISSUE_URL=%s\n' \
    "$r" "$pr" "$state" "$mergeable" "$head" "$base" "$issue" "$via" "$linked" "$auto_close" "https://github.com/$r/issues/$issue"
}

cmd_merge() {
  need_number "${1:-}"
  local pr=$1 r state mergeable method=""
  r="$(repo)"
  state="$(gh pr view "$pr" -R "$r" --json state -q .state)"
  [ "$state" = OPEN ] || die "PR #$pr is $state, not OPEN" 5
  # GitHub computes mergeability lazily; UNKNOWN turns into a real answer within a few seconds.
  for _ in 1 2 3 4 5 6; do
    mergeable="$(gh pr view "$pr" -R "$r" --json mergeable -q .mergeable)"
    [ "$mergeable" != UNKNOWN ] && break
    sleep 3
  done
  [ "$mergeable" = MERGEABLE ] || die "PR #$pr isn't mergeable ($mergeable): rebase it on its base and fix conflicts first" 5
  if   [ "$(gh repo view "$r" --json rebaseMergeAllowed -q .rebaseMergeAllowed)" = true ]; then method=--rebase
  elif [ "$(gh repo view "$r" --json squashMergeAllowed -q .squashMergeAllowed)" = true ]; then method=--squash
  elif [ "$(gh repo view "$r" --json mergeCommitAllowed -q .mergeCommitAllowed)" = true ]; then method=--merge
  else die "the repository allows no merge method"; fi
  info "merging PR #$pr ($method, branch kept)"
  gh pr merge "$pr" -R "$r" "$method" >/dev/null
  state="$(gh pr view "$pr" -R "$r" --json state -q .state)"
  [ "$state" = MERGED ] || die "PR #$pr is $state after the merge call (a merge queue or required review may hold it)"
  printf 'MERGED=%s\nMETHOD=%s\nSHA=%s\n' "$pr" "${method#--}" "$(gh pr view "$pr" -R "$r" --json mergeCommit -q .mergeCommit.oid)"
}

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  resolve)  cmd_resolve "$@" ;;
  criteria) cmd_criteria "$@" ;;
  tick)     cmd_tick "$@" ;;
  merge)    cmd_merge "$@" ;;
  ''|-h|--help|help) usage ;;
  *) usage >&2; die "unknown command '$cmd'" ;;
esac
