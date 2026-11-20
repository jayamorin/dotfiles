# Progress Tracker

Update this file after every meaningful change.

## Current State

- #2 (2026-11-20): the outdated Ubuntu 17.04 configs (Jenkins, Vim, tmux, git) are replaced by the Claude Code dotfiles: a `claude/` component (global `CLAUDE.md`, team `settings.json`, the gh-flow, gh-merge and plan-first skills, `/gh-task`, `/gh-issue`, `/gh-verify`, `/gh-merge`) installed by `install.sh`, with installer tests and CI on macOS, Ubuntu and Windows/WSL. Published from a private repository as one commit

## Known Issues

1. [minor] **The old commits keep a personal address** (2026-11-20, #2) — some of the 6 commits from before #2 are authored with a personal Gmail address, public since they were pushed. New commits use the GitHub noreply address. Removing it needs a history rewrite and force-push of `master`; not done
2. [minor] **Install location is fixed to `~/.claude`** — the commands call `~/.claude/skills/gh-flow/scripts/gh-flow.sh` by path, so `CLAUDE_CONFIG_DIR` isn't supported
3. [minor] **An appended `CLAUDE.md` block doesn't update on `git pull`** — only linked installs do; people with their own `CLAUDE.md` re-run `./install.sh --with-claude-md` after a pull (README → Update)
4. [minor] **Native Windows is unsupported** — Claude Code running natively on Windows reads `%USERPROFILE%\.claude`, so it doesn't see a WSL install
5. [minor] **The CI Windows job uses WSL 1, while the README recommends WSL 2** — hosted Windows runners generally can't run nested virtualization
6. [minor] **gh-flow can create a duplicate project when it can't list projects** (`find_project` in `gh-flow.sh`) — a failed list returns empty, which `ensure_project` reads as "missing"
7. [minor] **`gh-flow`'s `SKILL.md` frontmatter isn't valid YAML for the `skills` CLI** — `skills update -g` skips it

## To Verify

- [major] #2: CI passes on macOS, Ubuntu and Windows/WSL on the first PR and on the first push to `master` (`check.yml` now triggers on `master`)
- [major] A person installs from the README on a clean machine with the public clone URL (clone → `./install.sh --with-claude-md --with-settings` → restart → `/gh-task` listed → `gh-flow.sh repo` in a GitHub repo)
- [major] gh-merge in a real session in another repo: "merge PR <n>" triggers it, it ticks only met criteria, blocks on a failing check, merges with the repo's method and keeps the branch, and closes the issue only when every box is ticked
- [minor] A real Windows machine through WSL 2, following README → Windows

## Verification Log

## Open Questions

## Architecture Decisions

- **Published as one commit, without the private history (2026-11-20, #2, user):** the private repository's 31 commits carry a personal email, internal issue links and notes about the maintainer's machine; the public repo gets the current files in one commit authored with the GitHub noreply address, and a fresh tracker. The private repository is archived with a pointer here. Rejected: pushing the full history (exposes the email and internal links), publishing the old tracker as is
- **`master` stays the default branch (2026-11-20, #2):** renaming it would change existing clone and link URLs; `check.yml` and README → Update use `master`; gh-flow and gh-merge detect the base on their own
- **LICENSE kept (2026-11-20, #2):** the MIT license is the one file from the old configs that stays; the skills declare `license: MIT`
- **The privacy check covers the tracker and personal email addresses (2026-11-20, #2):** `make privacy` no longer skips `context/` and fails on addresses at common personal mail providers, since everything here is public
- **Symlink by default, never overwrite:** `git pull` updates every install; `--copy` for people who move the checkout. Anything at a target that `install.sh` didn't put there goes to `~/.dotfiles-backups/<timestamp>/`
- **Team settings are merged, not linked:** Claude Code writes to `~/.claude/settings.json` itself, so `lib/settings_merge.py` merges the team keys in and can take them out again
- **Windows is supported through WSL only;** CI runs on all three systems, the Windows job inside WSL
- **LF everywhere through `.gitattributes`;** shellcheck fails on warnings or worse

## Next Steps

1. After the merge: archive the private repository with a pointer here, and repoint existing checkouts (`git remote set-url origin https://github.com/jayamorin/dotfiles.git`, then `git checkout master && git pull`)

## Suggestions / Future Suggestions

- A `git` component for `~/.config/git/ignore` (e.g. `**/.claude/settings.local.json`)
- Shell and editor components, as in the old configs, once they're current
