#!/usr/bin/env bash
# Exercises install.sh against a throwaway $HOME: link and copy installs, backups, idempotence,
# every CLAUDE.md case, dry run and uninstall. Run with `make test`.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
SRC="$REPO_DIR/claude"
failures=0

check() {
  local what="$1"; shift
  if "$@"; then printf 'ok   %s\n' "$what"; else printf 'FAIL %s\n' "$what"; failures=$((failures + 1)); fi
}

fresh_home() {
  HOME="$(mktemp -d)"
  export HOME
  C="$HOME/.claude"
}

# Convert <file> to CRLF line endings, as a Windows editor would save it.
to_crlf() { awk '{ printf "%s\r\n", $0 }' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }

no_backups() { [ ! -e "$HOME/.dotfiles-backups" ]; }
# Path of <relative path under $HOME> in the (single) backup folder of this test's run.
backed_up() { printf '%s\n' "$HOME"/.dotfiles-backups/*/"$1"; }
nothing_backed_up_inside_claude() { [ -z "$(find "$C" -name '*.bak-*' 2>/dev/null)" ]; }

# --- every skill the shared rules name ships with this repo ----------------------------------------------------
for s in $(grep -oE '\.claude/skills/[A-Za-z0-9_-]+' "$SRC/CLAUDE.md" | sed 's#.*/##' | sort -u); do
  check "claude/CLAUDE.md names $s, and the repo has it" test -f "$SRC/skills/$s/SKILL.md"
done
# --- line endings -------------------------------------------------------------------------------------------
if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for f in install.sh claude/skills/gh-flow/scripts/gh-flow.sh claude/skills/gh-merge/scripts/gh-merge.sh claude/CLAUDE.md lib/settings_merge.py; do
    check "$f is forced to LF in every checkout" \
      test "$(git -C "$REPO_DIR" check-attr eol -- "$f" | sed 's/.*: //')" = lf
  done
fi

# --- link install --------------------------------------------------------------------------------------------
fresh_home
"$INSTALL" >/dev/null
for s in gh-flow gh-merge plan-first; do
  check "$s skill is a link into the repo" test "$(readlink "$C/skills/$s")" = "$SRC/skills/$s"
done
for c in gh-issue gh-merge gh-task gh-verify; do
  check "/$c command is linked" test "$(readlink "$C/commands/$c.md")" = "$SRC/commands/$c.md"
done
check "helper script runs from the installed path" \
  test "$(bash "$C/skills/gh-flow/scripts/gh-flow.sh" slug 'Fix login timeout')" = "fix-login-timeout"
check "no CLAUDE.md without --with-claude-md" test ! -e "$C/CLAUDE.md"
"$INSTALL" claude >/dev/null
check "re-install is idempotent (no backups)" no_backups
"$INSTALL" --uninstall >/dev/null
check "uninstall removes the skill links" test ! -e "$C/skills/gh-flow" -a ! -e "$C/skills/gh-merge" -a ! -e "$C/skills/plan-first"
check "uninstall removes the command links" test ! -e "$C/commands/gh-task.md"
check "uninstall leaves the repo's own files alone" test -f "$SRC/skills/gh-flow/SKILL.md"

# --- existing files are backed up, never overwritten ---------------------------------------------------------
fresh_home
mkdir -p "$C/skills/gh-flow" "$C/commands"
echo mine > "$C/skills/gh-flow/SKILL.md"
echo mine > "$C/commands/gh-task.md"
"$INSTALL" >/dev/null
check "someone else's skill dir is backed up" test "$(cat "$(backed_up .claude/skills/gh-flow)/SKILL.md")" = mine
check "someone else's command is backed up" test "$(cat "$(backed_up .claude/commands/gh-task.md)")" = mine
check "backups never land inside ~/.claude (Claude Code would load them)" nothing_backed_up_inside_claude
check "nothing but the installed skills under ~/.claude/skills" test "$(ls "$C/skills")" = "$(ls "$SRC/skills")"
"$INSTALL" --uninstall >/dev/null
check "uninstall keeps the backups" test -f "$(backed_up .claude/skills/gh-flow)/SKILL.md"

# --- an identical existing directory is replaced without a backup (first install on the maintainer's machine)
fresh_home
mkdir -p "$C/skills" && cp -R "$SRC/skills/gh-flow" "$C/skills/gh-flow"
"$INSTALL" >/dev/null
check "identical skill dir: replaced by a link" test -L "$C/skills/gh-flow"
check "identical skill dir: no backup" no_backups
fresh_home
mkdir -p "$C/skills" && cp -R "$SRC/skills/gh-flow" "$C/skills/gh-flow" && echo extra > "$C/skills/gh-flow/NOTES.md"
"$INSTALL" >/dev/null
check "changed skill dir: backed up" test -f "$(backed_up .claude/skills/gh-flow)/NOTES.md"

# --- copy install --------------------------------------------------------------------------------------------
fresh_home
"$INSTALL" --copy >/dev/null
check "copy install is a real directory" test -d "$C/skills/gh-flow" -a ! -L "$C/skills/gh-flow"
check "copy matches the repo" diff -rq --exclude=.installed-by-dotfiles "$SRC/skills/gh-flow" "$C/skills/gh-flow"
"$INSTALL" --copy >/dev/null
check "copy re-install replaces its own copy (no backups)" no_backups
"$INSTALL" --uninstall >/dev/null
check "uninstall removes the copy" test ! -e "$C/skills/gh-flow"
check "uninstall removes copied commands" test ! -e "$C/commands/gh-issue.md"

# --- CLAUDE.md -------------------------------------------------------------------------------------------------
fresh_home
"$INSTALL" --with-claude-md >/dev/null
check "no CLAUDE.md yet: linked" test "$(readlink "$C/CLAUDE.md")" = "$SRC/CLAUDE.md"
"$INSTALL" --uninstall >/dev/null
check "uninstall removes the CLAUDE.md link" test ! -e "$C/CLAUDE.md"

fresh_home
mkdir -p "$C" && cp "$SRC/CLAUDE.md" "$C/CLAUDE.md"
"$INSTALL" --with-claude-md >/dev/null
check "identical CLAUDE.md: replaced by a link, no backup" test -L "$C/CLAUDE.md"
check "identical CLAUDE.md: no backup" no_backups

fresh_home
mkdir -p "$C" && printf '# My rules\n\nkeep me\n' > "$C/CLAUDE.md"
"$INSTALL" --with-claude-md >/dev/null
"$INSTALL" --with-claude-md >/dev/null
check "own CLAUDE.md: block appended once" test "$(grep -c 'dotfiles:claude-md:begin' "$C/CLAUDE.md")" = 1
check "own CLAUDE.md: content kept" grep -q 'keep me' "$C/CLAUDE.md"
check "own CLAUDE.md: rules present" grep -qF "Record everything in the repo's progress tracker" "$C/CLAUDE.md"
"$INSTALL" --uninstall >/dev/null
check "uninstall restores the original CLAUDE.md exactly" test "$(cat "$C/CLAUDE.md")" = "$(printf '# My rules\n\nkeep me')"
check "uninstall leaves no trailing blank line" test "$(tail -c 1 "$C/CLAUDE.md" | od -An -c | tr -d ' ')" = '\n'

fresh_home
mkdir -p "$C" && printf '# My rules\n\nkeep me\n' > "$C/CLAUDE.md"
"$INSTALL" --with-claude-md >/dev/null
to_crlf "$C/CLAUDE.md"
"$INSTALL" --with-claude-md >/dev/null
check "CRLF CLAUDE.md: re-install keeps one block" test "$(grep -c 'dotfiles:claude-md:begin' "$C/CLAUDE.md")" = 1
check "CRLF CLAUDE.md: content kept" grep -q 'keep me' "$C/CLAUDE.md"
to_crlf "$C/CLAUDE.md"
"$INSTALL" --uninstall >/dev/null
check "CRLF CLAUDE.md: uninstall removes the block" sh -c '! grep -q "dotfiles:claude-md" "$1"' _ "$C/CLAUDE.md"
check "CRLF CLAUDE.md: uninstall keeps your content" grep -q 'keep me' "$C/CLAUDE.md"

fresh_home
mkdir -p "$C" && printf "## Record everything in the repo's progress tracker — mine\n" > "$C/CLAUDE.md"
"$INSTALL" --with-claude-md >/dev/null
check "an unmarked copy of the rules isn't duplicated" \
  test "$(grep -c "Record everything in the repo's progress tracker" "$C/CLAUDE.md")" = 1

fresh_home
"$INSTALL" --copy --with-claude-md >/dev/null
check "copy mode: CLAUDE.md is a real file" test -f "$C/CLAUDE.md" -a ! -L "$C/CLAUDE.md"
"$INSTALL" --copy --with-claude-md >/dev/null
check "copy mode: re-install keeps one block" test "$(grep -c 'dotfiles:claude-md:begin' "$C/CLAUDE.md")" = 1
"$INSTALL" --uninstall >/dev/null
check "copy mode: uninstall removes the file it wrote" test ! -e "$C/CLAUDE.md"

# --- team settings (--with-settings) ---------------------------------------------------------------------------
RULE='Bash(bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh *)'
# json <file> <python expression over `d`>: prints the result
json() { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
allow_count() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("permissions",{}).get("allow",[]).count(sys.argv[2]))' "$C/settings.json" "$RULE"; }
personal='{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"node \"$HOME/tool.js\""}]}]},"model":"opus","permissions":{"allow":["Bash(npm test *)"],"defaultMode":"default"}}'

fresh_home
"$INSTALL" >/dev/null
check "settings untouched without --with-settings" test ! -e "$C/settings.json"
"$INSTALL" --with-settings >/dev/null
check "no settings.json yet: created with the team rule" test "$(allow_count)" = 1
check "settings.json is a real file, not a link (Claude Code writes it)" test -f "$C/settings.json" -a ! -L "$C/settings.json"
"$INSTALL" --uninstall >/dev/null
check "uninstall removes a settings.json that only held team settings" test ! -e "$C/settings.json"
check "uninstall removes the state file" test ! -e "$C/.dotfiles-settings-applied.json"

fresh_home
mkdir -p "$C" && printf '%s\n' "$personal" > "$C/settings.json"
"$INSTALL" --with-settings >/dev/null
"$INSTALL" --with-settings >/dev/null
check "own settings: team rule added once (idempotent)" test "$(allow_count)" = 1
check "own settings: personal hooks kept" grep -q 'tool.js' "$C/settings.json"
check "own settings: personal allow rule kept" grep -qF 'Bash(npm test *)' "$C/settings.json"
check "own settings: model kept" test "$(json "$C/settings.json" "d['model']")" = opus
"$INSTALL" --uninstall >/dev/null
check "uninstall restores the personal settings exactly" \
  test "$(json "$C/settings.json" "json.dumps(d, sort_keys=True)")" = "$(printf '%s' "$personal" | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')"

fresh_home
mkdir -p "$C" && printf '{"$schema":"mine","permissions":{"allow":["%s"]}}\n' "$RULE" > "$C/settings.json"
out="$("$INSTALL" --with-settings)"
check "rule already present: not duplicated" test "$(allow_count)" = 1
check "conflicting value: yours kept and reported" sh -c 'test "$1" = mine && printf "%s" "$2" | grep -q "kept your"' _ \
  "$(json "$C/settings.json" "d['\$schema']")" "$out"
"$INSTALL" --uninstall >/dev/null
check "uninstall keeps a rule you already had" test "$(allow_count)" = 1

fresh_home
mkdir -p "$C" && printf '{ broken\n' > "$C/settings.json"
out="$("$INSTALL" --with-settings)"
check "invalid settings.json: left untouched" test "$(cat "$C/settings.json")" = '{ broken'
check "invalid settings.json: warned" sh -c 'printf "%s" "$1" | grep -q "not valid JSON"' _ "$out"

fresh_home
mkdir -p "$C" && printf '%s\n' "$personal" > "$C/settings.json"
"$INSTALL" --with-settings --dry-run >/dev/null
check "dry run: settings unchanged" test "$(allow_count)" = 0
check "dry run: no state file" test ! -e "$C/.dotfiles-settings-applied.json"

if [ -x /usr/bin/python3 ]; then
  fresh_home
  mkdir -p "$C" && printf '%s\n' "$personal" > "$C/settings.json"
  PATH="/usr/bin:/bin" "$INSTALL" --with-settings >/dev/null
  check "merge works with the system /usr/bin/python3 (3.9 on macOS)" test "$(allow_count)" = 1
fi

# --- dry run and argument checks -----------------------------------------------------------------------------
fresh_home
"$INSTALL" --dry-run --with-claude-md >/dev/null
check "dry run changes nothing" test ! -e "$C"
check "unknown component is rejected" sh -c "! '$INSTALL' nvim >/dev/null 2>&1"
check "unknown option is rejected" sh -c "! '$INSTALL' --bogus >/dev/null 2>&1"

# --- native Windows shells are refused (a fake uname stands in for Git Bash, MSYS and Cygwin) ----------------
for system in MINGW64_NT-10.0-22631 MSYS_NT-10.0-22631 CYGWIN_NT-10.0-22631; do
  fresh_home
  mkdir "$HOME/bin"
  printf '#!/bin/sh\necho %s\n' "$system" > "$HOME/bin/uname"
  chmod +x "$HOME/bin/uname"
  status=0
  out="$(PATH="$HOME/bin:$PATH" "$INSTALL" --with-claude-md --with-settings 2>&1)" || status=$?
  check "$system: refused with a non-zero exit" test "$status" -ne 0
  check "$system: message points at WSL" sh -c 'printf "%s" "$1" | grep -q WSL' _ "$out"
  check "$system: nothing installed" test ! -e "$C"
done
check "--help still works on a refused system" sh -c 'PATH="$1:$PATH" "$2" --help | grep -q Components' _ "$HOME/bin" "$INSTALL"

# --- gh-merge: criteria and tick against a stub gh (no network) -----------------------------------------------
GHM_DIR="$(mktemp -d)"
mkdir -p "$GHM_DIR/bin"
printf '## Context\n- [ ] not a criterion\n\n## Acceptance criteria\n- [ ] first\n- [x] second\r\n  * [ ] third\n\n## Development\n- [ ] after\n' > "$GHM_DIR/body"
cat > "$GHM_DIR/bin/gh" <<'STUB'
#!/bin/sh
# Minimal gh: the repo name, an issue body from $GHM_DIR/body, and `issue edit --body-file` writing it back.
case "$1 $2" in
  "repo view") echo owner/name ;;
  "issue view") cat "$GHM_DIR/body" ;;
  "issue edit") while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$GHM_DIR/body"; shift; done ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GHM_DIR/bin/gh"
export GHM_DIR
ghm() { PATH="$GHM_DIR/bin:$PATH" bash "$SRC/skills/gh-merge/scripts/gh-merge.sh" "$@"; }
check "gh-merge lists only the Acceptance criteria checkboxes" \
  test "$(ghm criteria 7 | cut -f1,2 | tr '\t\n' ':,')" = "1:-,2:x,3:-,"
ghm tick 7 1 3 >/dev/null
check "gh-merge tick checks off the named criteria" test "$(ghm criteria 7 | cut -f2 | tr -d '\n')" = "xxx"
check "gh-merge tick leaves other checkboxes alone" sh -c 'grep -c "\[ \]" "$1" | grep -qx 2' _ "$GHM_DIR/body"
check "gh-merge tick keeps the CRLF line" sh -c 'grep -q "second$(printf "\r")$" "$1"' _ "$GHM_DIR/body"
status=0; ghm tick 7 9 >/dev/null 2>&1 || status=$?
check "gh-merge tick refuses a criterion that doesn't exist" test "$status" -ne 0
printf '## Context\nnothing\n' > "$GHM_DIR/body"
status=0; ghm criteria 7 >/dev/null 2>&1 || status=$?
check "gh-merge criteria exits 4 without acceptance criteria" test "$status" -eq 4
rm -rf "$GHM_DIR"

if [ "$failures" -gt 0 ]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
printf 'all checks passed\n'
