# dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Personal collection of configuration files, shared with the teams I work with. Each top-level folder mirrors a dotfolder in your home directory, and `install.sh` links it into place, so everyone runs the same setup and `git pull` keeps it current.

| Folder | Installs to | Contents |
|---|---|---|
| `claude/` | `~/.claude/` | [Claude Code](https://docs.claude.com/en/docs/claude-code): global `CLAUDE.md`, team `settings.json`, the **gh-flow**, **gh-merge** and **plan-first** skills, the `/gh-task`, `/gh-issue`, `/gh-verify`, `/gh-merge` commands |

More dotfiles (shell, git, editor) go in as new folders and new `install.sh` components; see [Adding dotfiles](#adding-dotfiles).

## Requirements

- **macOS, Linux, or Windows through WSL 2** with bash 3.2+ (see [Windows](#windows); Git Bash, PowerShell and Cygwin aren't supported)
- **git**
- For the `claude` component:
  - **Claude Code** (CLI, desktop app or IDE extension), signed in
  - **GitHub CLI** `gh` 2.x, signed in with project access:
    ```bash
    gh auth login
    gh auth refresh -s project      # gh-flow adds issues to the repo's GitHub Project
    ```
  - **python3** 3.9+ for `--with-settings` (macOS: comes with the Xcode Command Line Tools, like git; Debian, Ubuntu and WSL: `sudo apt install python3`; Fedora: `sudo dnf install python3`)
  - Optional: `jq` (lets gh-flow show the Labels column on the project board; skipped without it)

## Install

```bash
git clone https://github.com/jayamorin/dotfiles.git ~/Workspace/dotfiles
cd ~/Workspace/dotfiles
./install.sh --with-claude-md --with-settings
```

Then **restart Claude Code** (or start a new session).

These commands are the same on macOS, Linux and WSL.

### Windows

Windows is supported **through WSL**: the checkout, the installer, `gh` and Claude Code all live inside your Linux distribution. `install.sh` refuses to run in Git Bash, MSYS or Cygwin.

1. In PowerShell: `wsl --install`, then restart if asked and open your distribution (Ubuntu by default).
2. Inside WSL, install the tools: `sudo apt update && sudo apt install git python3 gh`. If `gh` isn't in your distribution's packages, follow [the GitHub CLI's Linux instructions](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).
3. Inside WSL, [install Claude Code](https://code.claude.com/docs/en/setup#install-in-wsl) with the Linux command, set up an SSH key and run `gh auth login`.
4. Follow the [Install](#install) commands above, inside WSL.
5. Start `claude` from the WSL terminal. In VS Code, open the folder through the WSL extension first.

Keep the checkout in your WSL home (`~/Workspace/dotfiles`), not under `/mnt/c`: it's faster and file permissions behave normally. Claude Code running natively on Windows reads `%USERPROFILE%\.claude`, so it won't see this install.

### Options

By default `install.sh` **symlinks** each file or folder into your home directory, so a later `git pull` updates you immediately. It **never overwrites** anything it didn't install: an existing file or folder that differs from the repo's is moved to `~/.dotfiles-backups/<timestamp>/` (same path under your home folder) first. Backups are kept outside `~/.claude` on purpose — Claude Code would load a backed-up skill folder as a second, live skill. One that's already identical to the repo's is simply replaced by the link.

| Option | Effect |
|---|---|
| *(none)* | Install every component, symlinked (recommended) |
| `claude` | Install only that component (`./install.sh claude`) |
| `--with-claude-md` | Also install the global `CLAUDE.md` (see below) |
| `--with-settings` | Also merge the team settings into `~/.claude/settings.json` (see below) |
| `--copy` | Copy instead of symlink, if you'll move or delete the checkout. Updates then need `git pull && ./install.sh --copy …` |
| `--dry-run` | Show what would change, change nothing |
| `--uninstall` | Remove what this script installed; keeps backups and anything it didn't install |

**How `--with-claude-md` treats your `~/.claude/CLAUDE.md`:**

| You have | Result |
|---|---|
| no `CLAUDE.md`, or one identical to `claude/CLAUDE.md` | linked to the repo's file (updates with `git pull`) |
| your own `CLAUDE.md` | the team rules are **appended** between `<!-- dotfiles:claude-md:begin/end -->` markers; your content stays. Re-run `./install.sh --with-claude-md` after a pull to refresh the block; `--uninstall` removes just the block |
| your own `CLAUDE.md` that already contains the progress-tracker rule | left as is |

**How `--with-settings` treats your `~/.claude/settings.json`:** it is **never a link** — Claude Code writes that file itself (`/model`, `/config`), and those personal choices must not end up in this repo. Instead `claude/settings.json` is merged in:

- missing keys and list entries (e.g. a `permissions.allow` rule) are added; no file yet → it's created
- anything you already set — hooks, model, your own permission rules — is kept; where your value differs from the team's, yours wins and the installer says so
- an invalid `settings.json` is left untouched with a warning
- what was added is recorded in `~/.claude/.dotfiles-settings-applied.json`, so `--uninstall` removes exactly that

Team settings today: `$schema` (editor autocomplete) and one permission rule, `Bash(bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh *)`, so gh-flow's helper runs without a prompt. A compound command such as `… gh-flow.sh finish && rm -rf x` still asks, because Claude Code checks every part of it. **Personal settings stay personal:** keep your own hooks, model and permission rules in your `~/.claude/settings.json`; they are never copied into this repo.

### Check it works

```bash
ls -l ~/.claude/skills/gh-flow ~/.claude/skills/gh-merge ~/.claude/skills/plan-first ~/.claude/commands/gh-*.md ~/.claude/CLAUDE.md
grep -F 'gh-flow.sh' ~/.claude/settings.json                  # the team permission rule
cd ~/Workspace/your-repo                                      # any git repo hosted on GitHub
bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh repo          # prints OWNER, REPO, REMOTE, BASE, PROJECT
```

In Claude Code, type `/gh-`: you should see `/gh-task`, `/gh-issue`, `/gh-verify` and `/gh-merge`.

## Update

```bash
cd ~/Workspace/dotfiles && git checkout master && git pull && ./install.sh --with-claude-md --with-settings
```

This switches the checkout back to `master` (in case you were on a branch), pulls the latest, and re-runs the installer: new files get linked, an appended `CLAUDE.md` block is refreshed, and new team settings are merged. It's safe to run any time; nothing you didn't install is overwritten. Restart Claude Code afterwards.

## Uninstall

```bash
cd ~/Workspace/dotfiles && ./install.sh --uninstall
```

## Claude Code: what you get

| Path | What it does |
|---|---|
| `claude/settings.json` | Team settings merged into `~/.claude/settings.json` (`--with-settings`): a permission rule that lets gh-flow's helper script run without prompting |
| `claude/CLAUDE.md` | Global instructions for every project. Today: **record everything in the repo's progress tracker** — every decision, gap, to-verify item and verification result goes into `context/progress-tracker.md`, tagged `[major]`/`[minor]`, committed with the change — with a **leftovers sweep** before every final report (unfinished, skipped, unproven, waiting, clean-up not done, follow-ups), so a report never mentions an open item the tracker doesn't have; and **plan first** before changing anything |
| `claude/skills/gh-flow/` | The **gh-flow** skill and its helper `scripts/gh-flow.sh`: every change goes issue → linked branch → `<type>: <summary>` commits → push → per-file summary comment on the issue |
| `claude/skills/gh-merge/` | The **gh-merge** skill and its helper `scripts/gh-merge.sh`: a PR is merged only after its issue's acceptance criteria are verified — it finds the issue of the PR's branch, runs the repo's checks, checks off (`- [x]`) each criterion that is met, posts a report, records it in the tracker, then merges |
| `claude/skills/plan-first/` | The **plan-first** skill that the global `CLAUDE.md` tells every session to follow: investigate read-only, present a plan, then ask Proceed / Change / Stop before changing anything |
| `claude/commands/gh-task.md` | `/gh-task <type> <what to do>`: new work, start to finish |
| `claude/commands/gh-issue.md` | `/gh-issue <number>`: work an existing issue (criteria → plan → implement → test → commit → verify) |
| `claude/commands/gh-merge.md` | `/gh-merge [<pr>]`: verify the PR's issue criteria, tick the met ones, merge, close the issue when all are met |
| `claude/commands/gh-verify.md` | `/gh-verify <number>`: check an issue's acceptance criteria against its branch and post a verification report |

### Using it in your repos

Open Claude Code in the repo and use a command, or just ask for the work ("fix the login timeout"); the skill triggers on its own for implementation work in a GitHub repo.

```text
/gh-task feature add the vulnerability inventory page
/gh-task chore bump the Traefik chart
/gh-issue 42
/gh-verify 42
/gh-merge 57
```

What happens:

1. **Issue** `<type>: <title>` is created (or reopened), assigned to you, and added to the GitHub Project named after the repo with status *In Progress*. The project is created and linked if missing.
2. **Branch** `<type>/<slug>-<issue#>` is created from the default branch by GitHub, so it appears under the issue's *Development* section. Label `ONGOING-DEVELOPMENT`.
3. Claude implements the change, runs the repo's own checks (`make check`, `npm test`, …) and commits as `<type>: <summary>` with `Refs #<issue>`. It rebases on the default branch before every round of edits and resolves conflicts itself.
4. **Push**, then a per-file changes comment on the issue; the label becomes `FOR-AGENT-REVIEW`.
5. **No PR is opened.** You review and open the PR. `/gh-verify <n>` posts an acceptance-criteria report and records it in the tracker.
6. **Merge with `/gh-merge <pr>`** (or ask "merge PR 57"). It finds the issue from the PR's branch, runs the repo's checks, judges each acceptance criterion and checks off the met ones in the issue, posts a report and records it in the tracker. It merges (rebase when the repo allows it, branch kept) only when every check passes and every unchecked criterion can only be proven after the deploy; those go to the tracker's To Verify. It closes the issue only when every criterion is checked; otherwise the issue stays open until you verify the rest after the deploy.

Types (in the title, branch and commit, never as a label): `feature`, `bugfix`, `hotfix`, `chore`, `issue`.

**Leftovers sweep.** Before its final report, every task now records what it leaves behind in the repo's tracker: unfinished or deferred work, skipped or partial steps, checks it couldn't prove, manual steps waiting on you, clean-up not done, and every follow-up it mentions. This applies in **every repo** you work in, through the global `CLAUDE.md`, plan-first, gh-flow and the three commands. Expect a few more tracker lines per task, and a report that ends with the leftovers or "Leftovers: none".

**Repo rules still apply.** Each repo's `CLAUDE.md` / `AGENTS.md` (and any spec they point to) say which checks to run and which live actions (deploys, `kubectl apply`, Vault writes, Supabase changes) need your approval. gh-flow never deploys and never merges; gh-merge merges only what passed its checks, and never deploys.

**Commit-message hook (optional, per repo):** rejects commits that don't follow `<type>: <summary>`:

```bash
bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh install-hook
```

**Environment overrides** for unusual repos: `GH_FLOW_REMOTE`, `GH_FLOW_BASE`, `GH_FLOW_CREATE_PROJECT=0` (don't create a project), `GH_FLOW_RETRIES`.

The install location is fixed: the commands call `~/.claude/skills/gh-flow/scripts/gh-flow.sh` by that path, so a custom `CLAUDE_CONFIG_DIR` isn't supported.

## What never goes in this repo

Everything here is public and shared with everyone who installs it, so only portable configuration belongs in it:

- **Secrets and credentials** of any kind (tokens, API keys, `~/.claude/.credentials.json`, `.netrc`, SSH keys)
- **Personal state:** Claude Code history, sessions, `projects/` (transcripts and memory), `file-history`, telemetry, caches, backups
- **Machine-specific paths** (`/Users/<name>/…`); use `$HOME` or a path relative to the repo
- **Anthropic's built-in skills** (docx, pdf, pptx, xlsx, browser, …): they come with each person's Claude account and their license doesn't allow redistributing them
- **Personal tools and hooks** that others don't have installed (a hook pointing at a tool you alone use breaks every session for everyone else). They belong in your own `~/.claude/settings.json`, which `--with-settings` merges into and never replaces

- **Private names and addresses:** personal email addresses (commit with your GitHub noreply address), private organizations, repositories and hostnames

`make check` fails on home-directory paths, personal email addresses and common secret formats.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `warning: gh token lacks project access` | `gh auth refresh -s project` |
| `/gh-task` doesn't appear | Restart Claude Code; check `ls -l ~/.claude/commands/gh-task.md` points into your checkout |
| Links broken after moving the checkout | Run `./install.sh --with-claude-md` again from the new location (or install with `--copy`) |
| `native Windows shells aren't supported` | You ran `install.sh` in Git Bash, MSYS or Cygwin; use [WSL](#windows) instead |
| `/gh-task` doesn't appear on Windows | Claude Code is running natively, not in WSL. Start `claude` from the WSL terminal |
| `bad interpreter` or `$'\r': command not found` | The scripts have CRLF line endings, from a checkout made before `.gitattributes` was added. In the checkout: `git rm --cached -r . -q && git reset --hard` (this discards uncommitted changes) |
| `commit-msg already exists and is not gh-flow's` | The repo already has a hook; merge it by hand or skip `install-hook` |
| Push refused after a rebase | Someone else pushed to the branch; `finish` uses `--force-with-lease` and stops rather than overwrite. Pull their work, then run `finish` again |
| Branch not listed under the issue's *Development* | It was pushed before gh-flow linked it; GitHub can't link an existing branch. The branch is still recorded in the issue body |
| Something you had was replaced | It's in `~/.dotfiles-backups/<timestamp>/` under the same path (e.g. `.claude/skills/<name>`); `./install.sh --uninstall`, then move it back |
| A skill shows up twice (e.g. `gh-flow.bak-…`) | Left by an early install, inside `~/.claude/skills`; move it out (to `~/.dotfiles-backups/`) or delete it, then restart Claude Code |

## Adding dotfiles

1. Add a top-level folder named after what it installs (e.g. `git/` for `~/.gitconfig`, `zsh/` for `~/.zshrc`).
2. In `install.sh`: add the component to `ALL_COMPONENTS` and write `install_<name>` / `uninstall_<name>` using `install_one` / `uninstall_one` (they handle linking, copying, backups and ownership).
3. Add cases to `tests/test_install.sh`; `make check` must pass.
4. Document the component in the table at the top and its contents below.

## Contributing

1. Clone and install with the default symlink mode; your edits are live for you immediately.
2. Change files here, never in `~/.claude` directly (with symlinks they are the same files).
3. `make check`: syntax, shellcheck (if installed; warnings and errors fail), the privacy check, and the installer tests in a throwaway `$HOME`. CI runs the same checks on macOS, Linux and Windows through WSL on every PR.
4. Use the workflow on itself: `/gh-task chore <what changed>` in this repo, then open a PR. Record decisions and gaps in `context/progress-tracker.md`.
5. After the merge, tell the team to `git pull` and restart Claude Code.

## Noteworthy dotfiles

Noteworthy dotfiles [here](https://dotfiles.github.io/).
