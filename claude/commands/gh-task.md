---
description: Issue → branch → implement → commit → push → issue-comment (gh-flow convention, no PR)
argument-hint: <issue|feature|hotfix|bugfix|chore> <what to do>
allowed-tools: Bash(git:*), Bash(gh:*), Bash(bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh:*), Read, Edit, Write, Grep, Glob
---

Use the **gh-flow** skill and follow its procedure from start to finish in the current repository for this task:

$ARGUMENTS

How to read the arguments:
- If the first word is `issue`, `feature`, `hotfix`, `bugfix` or `chore`, that is the type and the rest is the task.
- If not, choose the type using the skill's type table. Say which type you chose and why in one line, then continue.

The script `~/.claude/skills/gh-flow/scripts/gh-flow.sh` detects the repo, remote, default branch and project. Use the values it prints; never assume `main`, `origin`, or a repo name.

Workflow requirements:
1. Issue title format: `<type>: <title>`. Don't add the type as a GitHub label; the title carries it.
2. Development branch: `<type>/<slugified-title>-<issue-number>`, created from the repo's default branch, linked to the issue, and recorded in the issue body
3. Commit format: `<type>: <summary>`
4. Auto-assign current user as issue assignee
5. Auto-add issue to the GitHub Project named after the repo (the script creates and links it, with the Labels column visible, if it doesn't exist)
6. Label `ONGOING-DEVELOPMENT` when development starts
7. When done: commit with `gh-flow.sh commit`, then `gh-flow.sh finish` pushes to GitHub and, only after the push is confirmed, replaces `ONGOING-DEVELOPMENT` with `FOR-AGENT-REVIEW` and comments a per-file changes summary. If the push fails, the issue stays `ONGOING-DEVELOPMENT`; fix the cause and re-run `finish`.
8. Do NOT create PR after task completion
9. Stay on the development branch. Run `bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh sync` before every round of file edits to rebase on the latest default branch. If a rebase exits 3 (`CONFLICT=1`), resolve the conflicts yourself per the skill's **Rebase conflicts** section, run `gh-flow.sh continue`, and re-run the interrupted command
10. Run the repo's own lint, type-check and test commands before committing
11. Do not delete the local development branch
12. Record every decision, gap and open item of this task in the repo's `context/progress-tracker.md` if it has one — as they come up, then checked again before the final commit — per the skill's **Pending gaps** section (global rule in `~/.claude/CLAUDE.md`): decisions → Architecture Decisions; pending/blocked items and problems found → Known Issues; done-but-unproven checks → To Verify; to-do → Next Steps; nice to have → Suggestions; questions for the user → Open Questions; tag each open item `[major]` or `[minor]`, small ones included; update existing entries instead of duplicating; mark items this task fixes, answers or verifies in place
13. Before the last commit, do the skill's **Leftovers sweep**: unfinished or deferred work, skipped or partial steps, done-but-unproven checks, manual steps still waiting, clean-up not done, problems found on the way, and every follow-up the report will mention all go in the tracker, tagged `[major]`/`[minor]`

Order: `start` creates the issue, creates the linked development branch on GitHub, checks it out locally, records it on the issue, then labels the issue `ONGOING-DEVELOPMENT` (covering 1, 2, 4, 5, 6). Only then start working. `finish` handles 7.

Current repo state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Detected: !`bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh repo 2>&1 || true`

If the status shows uncommitted changes, stop and ask before starting. When the work is done, report the issue URL, branch, commits, and confirm the issue comment was posted and the label is now `FOR-AGENT-REVIEW`. List the decisions, pending, to-verify, to-do, nice-to-have and leftover items (`[major]` first) and confirm which progress-tracker sections they're in. Don't mention an open item the tracker doesn't have; say "Leftovers: none" when there are none.
