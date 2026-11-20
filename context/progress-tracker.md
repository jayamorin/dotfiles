# Progress Tracker

Update this file after every meaningful change.

## Current State

- #8 (2026-11-20): merged branches deleted on GitHub and in the maintainer's checkout; only `main` remains (each had no commit missing from `main`). gh-flow keeps a branch after its push; deleting merged ones is done on request
- #2 (2026-11-20): the outdated Ubuntu 17.04 configs (Jenkins, Vim, tmux, git) are replaced by the Claude Code dotfiles: a `claude/` component (global `CLAUDE.md`, team `settings.json`, the gh-flow, gh-merge and plan-first skills, `/gh-task`, `/gh-issue`, `/gh-verify`, `/gh-merge`) installed by `install.sh`, with installer tests and CI on macOS, Ubuntu and Windows/WSL. Published from a private repository as one commit

## Known Issues

8. [minor] **The archived private repository's pointer says `git checkout -B master origin/master`** (2026-11-20, #6) — it's read-only, so it can't be updated without unarchiving; the command still works through GitHub's redirect from `master` to `main`, and README → Update here has the one-time switch
1. [minor] **The old commits keep a personal address** (2026-11-20, #2) — some of the 6 commits from before #2 are authored with a personal Gmail address, public since they were pushed. New commits use the GitHub noreply address. Removing it needs a history rewrite and force-push of `master`; not done
2. [minor] **Install location is fixed to `~/.claude`** — the commands call `~/.claude/skills/gh-flow/scripts/gh-flow.sh` by path, so `CLAUDE_CONFIG_DIR` isn't supported
3. [minor] **An appended `CLAUDE.md` block doesn't update on `git pull`** — only linked installs do; people with their own `CLAUDE.md` re-run `./install.sh --with-claude-md` after a pull (README → Update)
4. [minor] **Native Windows is unsupported** — Claude Code running natively on Windows reads `%USERPROFILE%\.claude`, so it doesn't see a WSL install
5. [minor] **The CI Windows job uses WSL 1, while the README recommends WSL 2** — hosted Windows runners generally can't run nested virtualization
6. [minor] **gh-flow can create a duplicate project when it can't list projects** (`find_project` in `gh-flow.sh`) — a failed list returns empty, which `ensure_project` reads as "missing"
7. [minor] **`gh-flow`'s `SKILL.md` frontmatter isn't valid YAML for the `skills` CLI** — `skills update -g` skips it

## To Verify

- ~~[minor] #6: the merge of PR #7 is the first push to `main`; its CI run passes on all three systems (`check.yml` now triggers on `main`). Recorded on issue #6 when it runs~~ — verified 2026-11-20: push run 44761237499 on `f327414` passed on macOS, Ubuntu and WSL (issue #6 closed)
- ~~[major] #2: CI passes on the first push to `master` (`check.yml` now triggers on `master`); the PR run passed on all three (run 44754524443)~~ — verified 2026-11-20: push run 44755165034 passed
- [major] A person installs from the README on a clean machine with the public clone URL (clone → `./install.sh --with-claude-md --with-settings` → restart → `/gh-task` listed → `gh-flow.sh repo` in a GitHub repo)
- [major] gh-merge in a real session in another repo: "merge PR <n>" triggers it, it ticks only met criteria, blocks on a failing check, merges with the repo's method and keeps the branch, and closes the issue only when every box is ticked
- [minor] A real Windows machine through WSL 2, following README → Windows

## Verification Log

- 2026-11-20 — #6 / PR #7 — 4 of 5 criteria met before the merge (gh-merge): `main` is the default and `master` is gone on GitHub (renamed, open PR #5 retargeted and merged into `main`); README → Update; the maintainer's checkout tracks `origin/main` with no local `master`; tracker. CI green on the PR (macOS, Ubuntu, WSL). Criterion 2 (CI on a push to `main`) waits for the merge's push run (To Verify)
- 2026-11-20 — first push to `master` after PR #3: CI run 44755165034 passed on macOS, Ubuntu and WSL
- 2026-11-20 — #2 / PR #3 — ✅ all 5 criteria met (gh-merge): make check, shellcheck, gitleaks on the tree and the new commit, privacy and private-name greps clean; CI green on macOS, Ubuntu, WSL (https://github.com/jayamorin/dotfiles/issues/2#issuecomment-7042227455)

## Open Questions

## Architecture Decisions

- **Merged branches are deleted on request, not by gh-flow or gh-merge (2026-11-20, #8, user):** both keep branches by rule; a cleanup like #8 checks first that a branch has no commit missing from `main` (`git cherry`). The local `spaghetti` remote (the archived private repository) is kept for its history. Rejected: deleting branches in gh-merge's merge step (the rule exists so review links keep working)
- **Published as one commit, without the private history (2026-11-20, #2, user):** the private repository's 31 commits carry a personal email, internal issue links and notes about the maintainer's machine; the public repo gets the current files in one commit authored with the GitHub noreply address, and a fresh tracker. The private repository is archived with a pointer here. Rejected: pushing the full history (exposes the email and internal links), publishing the old tracker as is
- ~~**`master` stays the default branch (2026-11-20, #2):** renaming it would change existing clone and link URLs~~ — replaced 2026-11-20 (#6, user): the default branch is `main`
- **The default branch is `main` (2026-11-20, #6, user):** renamed with GitHub's branch rename (`POST /repos/{owner}/{repo}/branches/master/rename`), which makes `main` the default, removes `master`, retargets open PRs and redirects old `master` links; `check.yml` and README → Update use `main`, and README shows the one-time switch for old checkouts. Rejected: pushing `main` and deleting `master` by hand (no redirects, open PRs would close)
- **LICENSE kept (2026-11-20, #2):** the MIT license is the one file from the old configs that stays; the skills declare `license: MIT`
- **The privacy check covers the tracker and personal email addresses (2026-11-20, #2):** `make privacy` no longer skips `context/` and fails on addresses at common personal mail providers, since everything here is public
- **Symlink by default, never overwrite:** `git pull` updates every install; `--copy` for people who move the checkout. Anything at a target that `install.sh` didn't put there goes to `~/.dotfiles-backups/<timestamp>/`
- **Team settings are merged, not linked:** Claude Code writes to `~/.claude/settings.json` itself, so `lib/settings_merge.py` merges the team keys in and can take them out again
- **Windows is supported through WSL only;** CI runs on all three systems, the Windows job inside WSL
- **LF everywhere through `.gitattributes`;** shellcheck fails on warnings or worse

## Next Steps

1. ~~After the merge: archive the private repository with a pointer here, and repoint existing checkouts~~ — done 2026-11-20: the private repository's README points here and it is archived read-only; the maintainer's checkout tracks this repo (`origin`), the old remote kept as `spaghetti`. Other people's checkouts switch with the command in that README

## Suggestions / Future Suggestions

- A `git` component for `~/.config/git/ignore` (e.g. `**/.claude/settings.local.json`)
- Shell and editor components, as in the old configs, once they're current
