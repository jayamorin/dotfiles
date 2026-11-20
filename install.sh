#!/usr/bin/env bash
# install.sh — install this repo's dotfiles into your home directory.
#
#   ./install.sh [component...] [options]
#
# Components (default: all):
#   claude    claude/skills/*  -> ~/.claude/skills/<name>
#             claude/commands/*.md -> ~/.claude/commands/<name>.md   (/gh-task, /gh-issue, /gh-verify, /gh-merge)
#             claude/CLAUDE.md -> ~/.claude/CLAUDE.md                (only with --with-claude-md)
#             claude/settings.json merged into ~/.claude/settings.json (only with --with-settings)
#
# Options:
#   --copy             copy instead of symlink (default: symlink, so `git pull` here updates every install)
#   --with-claude-md   also install the global CLAUDE.md: linked (or copied) when you have none or yours is
#                      identical; otherwise appended to yours between marker comments, keeping your content
#   --with-settings    also merge the team settings into ~/.claude/settings.json (never a link: Claude Code
#                      writes that file itself). Adds missing entries only; your own values and keys (hooks,
#                      model, …) are kept. What it added is recorded so --uninstall removes exactly that. Needs python3
#   --dry-run          print what would change, change nothing
#   --uninstall        remove what this script installed (links, marked copies, the marked CLAUDE.md block,
#                      the merged team settings)
#
# Anything already at a target that this script didn't install (and that differs from the repo's) is moved to
# ~/.dotfiles-backups/<timestamp>/<path under $HOME> first — outside ~/.claude, so Claude Code never loads a backup.
# Runs on macOS, Linux and Windows through WSL; native Windows shells (Git Bash, MSYS, Cygwin) are refused.
# Portable to macOS bash 3.2.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SRC="$REPO_DIR/claude"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="$HOME/.dotfiles-backups/$STAMP"
MARK_BEGIN="<!-- dotfiles:claude-md:begin -->"
MARK_END="<!-- dotfiles:claude-md:end -->"
# Copied directories carry this file so re-installs and --uninstall can tell them from someone else's.
COPY_MARK=".installed-by-dotfiles"
# A CLAUDE.md that already has this heading (unmarked) is left alone rather than given a second copy.
RULE_HEADING="## Record everything in the repo's progress tracker"
ALL_COMPONENTS="claude"
SETTINGS_STATE="$CLAUDE_DIR/.dotfiles-settings-applied.json"

mode="link"
with_claude_md=0
with_settings=0
uninstall=0
dry_run=0
components=""

# The header comment above `set -euo pipefail`, without the leading "# ".
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

for arg in "$@"; do
  case "$arg" in
    --copy) mode=copy ;;
    --with-claude-md) with_claude_md=1 ;;
    --with-settings) with_settings=1 ;;
    --uninstall) uninstall=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "install.sh: unknown option '$arg'" >&2; usage >&2; exit 2 ;;
    *)
      case " $ALL_COMPONENTS " in
        *" $arg "*) components="$components $arg" ;;
        *) echo "install.sh: unknown component '$arg' (known: $ALL_COMPONENTS)" >&2; exit 2 ;;
      esac ;;
  esac
done
[ -n "$components" ] || components="$ALL_COMPONENTS"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "install.sh: native Windows shells aren't supported. Install WSL, then run this inside it, and run" >&2
    echo "Claude Code inside WSL too (README -> Windows). Nothing was changed." >&2
    exit 1 ;;
esac

say() { printf '%s\n' "$*"; }
run() {
  if [ "$dry_run" = 1 ]; then say "  would run: $*"; else "$@"; fi
}

# --- generic link/copy targets -----------------------------------------------------------------------------

# True if <target> was installed by this script or already matches the repo: a link into this repo, a marked
# copy, or a file/directory identical to the source (replacing it loses nothing, so it isn't backed up).
ours() {
  local src="$1" target="$2"
  if [ -L "$target" ]; then
    [ "$(readlink "$target")" = "$src" ]
  elif [ -d "$target" ]; then
    [ -e "$target/$COPY_MARK" ] || diff -rq --exclude="$COPY_MARK" "$src" "$target" >/dev/null 2>&1
  elif [ -f "$target" ]; then
    cmp -s "$src" "$target"
  else
    return 1
  fi
}

# Move <target> into this run's backup folder, keeping its path under $HOME.
backup() {
  local target="$1" dest
  dest="$BACKUP_DIR/${target#"$HOME"/}"
  say "  backing up $target -> $dest"
  run mkdir -p "$(dirname "$dest")"
  run mv "$target" "$dest"
}

install_one() {
  local src="$1" target="$2"
  run mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if ours "$src" "$target"; then
      run rm -rf "$target"
    else
      backup "$target"
    fi
  fi
  if [ "$mode" = link ]; then
    run ln -s "$src" "$target"
  else
    run cp -R "$src" "$target"
    if [ -d "$src" ]; then run touch "$target/$COPY_MARK"; fi
  fi
  say "  $mode $target"
}

uninstall_one() {
  local src="$1" target="$2"
  if ours "$src" "$target"; then
    run rm -rf "$target"
    say "  removed $target"
  elif [ -e "$target" ] || [ -L "$target" ]; then
    say "  kept $target (not installed by this script)"
  fi
}

# --- claude component ----------------------------------------------------------------------------------------

# Pairs of "<source in this repo>|<target under ~/.claude>" (CLAUDE.md is handled separately).
claude_targets() {
  local d f
  for d in "$CLAUDE_SRC"/skills/*/; do
    d="${d%/}"
    printf '%s|%s\n' "$d" "$CLAUDE_DIR/skills/$(basename "$d")"
  done
  for f in "$CLAUDE_SRC"/commands/*.md; do
    printf '%s|%s\n' "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
  done
}

claude_md_has_block() { [ -f "$1" ] && grep -qF "$MARK_BEGIN" "$1"; }

claude_md_remove_block() {
  local file="$1" tmp
  if [ "$dry_run" = 1 ]; then say "  would remove the dotfiles block from $file"; return 0; fi
  tmp="$(mktemp)"
  # Compare without a trailing CR: a Windows editor may have saved the file with CRLF line endings.
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '{l=$0; sub(/\r$/,"",l)} l==b{skip=1; next} l==e{skip=0; next} !skip' "$file" > "$tmp"
  # Drop the blank separator line the block was appended after.
  awk 'NF{for(;n>0;n--)print ""; print; next} {n++}' "$tmp" > "$file"
  rm -f "$tmp"
}

claude_md_append_block() {
  local file="$1"
  if [ "$dry_run" = 1 ]; then say "  would append the global rules to $file (marked block)"; return 0; fi
  {
    [ -s "$file" ] && printf '\n'
    printf '%s\n' "$MARK_BEGIN"
    cat "$CLAUDE_SRC/CLAUDE.md"
    printf '%s\n' "$MARK_END"
  } >> "$file"
}

claude_md_install() {
  local src="$CLAUDE_SRC/CLAUDE.md" target="$CLAUDE_DIR/CLAUDE.md"
  # Yours to replace: none yet, our own link/identical copy -> link (or copy) the repo's file.
  if { [ ! -e "$target" ] && [ ! -L "$target" ]; } || ours "$src" "$target"; then
    if [ "$mode" = copy ]; then
      # A copy is written as a marked block so --uninstall can find it again.
      [ -e "$target" ] && run rm -f "$target"
      run mkdir -p "$CLAUDE_DIR"
      claude_md_append_block "$target"
      say "  copy $target (marked block)"
    else
      install_one "$src" "$target"
    fi
    return 0
  fi
  if claude_md_has_block "$target"; then
    claude_md_remove_block "$target"
    claude_md_append_block "$target"
    say "  updated the dotfiles block in $target"
  elif grep -qF "$RULE_HEADING" "$target"; then
    say "  $target already has the global rules (unmarked); left as is"
  else
    claude_md_append_block "$target"
    say "  appended the global rules to $target (your content kept)"
  fi
}

claude_md_uninstall() {
  local src="$CLAUDE_SRC/CLAUDE.md" target="$CLAUDE_DIR/CLAUDE.md"
  if [ -L "$target" ] && ours "$src" "$target"; then
    run rm -f "$target"
    say "  removed $target"
  elif claude_md_has_block "$target"; then
    claude_md_remove_block "$target"
    # Nothing left but the block we wrote: remove the empty file too.
    if [ "$dry_run" = 0 ] && [ ! -s "$target" ]; then rm -f "$target"; fi
    say "  removed the dotfiles block from $target"
  fi
}

settings_merge() {
  if ! command -v python3 >/dev/null 2>&1; then
    say "  warning: python3 not found; team settings not merged (README → Requirements)"
    return 0
  fi
  local dry=""
  [ "$dry_run" = 1 ] && dry="--dry-run"
  # shellcheck disable=SC2086
  python3 -I "$REPO_DIR/lib/settings_merge.py" "$@" $dry
}

install_claude() {
  say "claude -> $CLAUDE_DIR ($mode)"
  claude_targets | while IFS='|' read -r src target; do install_one "$src" "$target"; done
  run chmod +x "$CLAUDE_SRC"/skills/*/scripts/*.sh
  if [ "$with_claude_md" = 1 ]; then claude_md_install; fi
  if [ "$with_settings" = 1 ]; then
    settings_merge merge "$CLAUDE_SRC/settings.json" "$CLAUDE_DIR/settings.json" "$SETTINGS_STATE"
  fi
  local tool
  for tool in git gh; do
    command -v "$tool" >/dev/null 2>&1 || say "warning: '$tool' not found; gh-flow needs it (README → Requirements)"
  done
  command -v jq >/dev/null 2>&1 || say "note: 'jq' not found; optional (gh-flow skips the project Labels-column check)"
}

uninstall_claude() {
  say "claude: uninstalling from $CLAUDE_DIR"
  claude_targets | while IFS='|' read -r src target; do uninstall_one "$src" "$target"; done
  claude_md_uninstall
  if [ -e "$SETTINGS_STATE" ]; then settings_merge unmerge "$CLAUDE_DIR/settings.json" "$SETTINGS_STATE"; fi
}

# --- main ------------------------------------------------------------------------------------------------------

for component in $components; do
  if [ "$uninstall" = 1 ]; then "uninstall_$component"; else "install_$component"; fi
done
if [ "$uninstall" = 0 ]; then
  say "Done. Restart Claude Code (or start a new session) to pick up the changes."
  if grep -qi microsoft /proc/version 2>/dev/null; then
    say "WSL: this installed into your WSL home. Run Claude Code inside WSL; Claude Code on native Windows won't see it."
  fi
fi
