This repo holds the team's shared global configuration (dotfiles). Each top-level folder mirrors a dotfolder in the home directory (`claude/` → `~/.claude/`), and `install.sh` links it into place. It's public (github.com/jayamorin/dotfiles); people install it from here, and `README.md` is their guide.

Note: `claude/CLAUDE.md` is the team's *global* Claude Code instructions that this repo distributes, not instructions for working on this repo. This file is.

- `claude/settings.json` holds **team** settings only; it is merged into each person's `~/.claude/settings.json` (never linked) by `lib/settings_merge.py`. Personal hooks and preferences stay out of this repo.
- Edit configuration here, never in `~/.claude` directly (with a symlink install they are the same files).
- **This repo is public.** Commit with your GitHub noreply address; no private organization, repository, hostname or personal email in files or commit messages.
- Shared means portable: no secrets, personal state, home-directory paths, user names or personal tools/hooks (README → What never goes in this repo). `make check` enforces part of this.
- Don't add Anthropic's built-in skills (docx, pdf, …): they are licensed per account, not redistributable.
- Supported platforms: macOS, Linux, and Windows through WSL (native Windows shells are refused). Scripts must run on macOS bash 3.2 and on Linux; CI runs all three. `make check` before every commit; it runs the installer tests in a throwaway `$HOME`.
- A new dotfile is a new top-level folder plus an `install.sh` component and tests (README → Adding dotfiles).
- A behaviour change to gh-flow or the global `CLAUDE.md` affects every repo the team works in: say so in the issue and the README.
- Work through gh-flow (`/gh-task chore …`); record decisions and gaps in `context/progress-tracker.md`.
