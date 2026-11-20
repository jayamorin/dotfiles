---
description: Work an existing GitHub issue end-to-end (query → criteria → plan → implement → test → commit → verify)
argument-hint: <issue-number>
allowed-tools: Bash(git:*), Bash(gh:*), Bash(bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh:*), Read, Edit, Write, Grep, Glob
---

Work on GitHub issue **#$ARGUMENTS** in the current repository to completion, using the **gh-flow** skill.

The helper script below is written as `GHF` = `~/.claude/skills/gh-flow/scripts/gh-flow.sh`. Always write the full path. Use the `REPO`, `BASE` and `REMOTE` values the script prints; never assume `main` or `origin`.

## 1. Query & Branch

```bash
bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh work $ARGUMENTS
```

This:
- fetches the issue from the detected repo and reopens it if closed
- assigns you and adds it to the GitHub Project named after the repo (status "In Progress"); the project is created and linked, with the Labels column visible, if it doesn't exist
- creates or checks out the development branch `<type>/<slug>-<issue#>`. The type comes from the title's `<type>: ` prefix. A new branch is created on GitHub, linked to the issue; an existing one is rebased on `<REMOTE>/<BASE>`.
- records the branch in the issue body
- sets the `ONGOING-DEVELOPMENT` label, removing `FOR-AGENT-REVIEW` if the issue is coming back from review

Read `REPO=`, `BASE=`, `REMOTE=`, `ISSUE=`, `ISSUE_URL=`, `BRANCH=`, `LABEL=` (the type), `TITLE=` from the output. Everything after `BODY=` is the issue body.

## 2. Acceptance Criteria Check

If the body has no `## Acceptance criteria` section:

1. Read the repo's own docs (CLAUDE.md, AGENTS.md, CONTRIBUTING.md, README, and any files they point to) and the related code to understand what the issue needs.
2. Write an `## Acceptance criteria` section of concrete, testable checkboxes. Each item must be checkable from code or tests, e.g. "`<function>` returns X when Y" or "test covering Z passes".
3. Post the criteria as a comment: `gh issue comment $ARGUMENTS --body-file <tmpfile>`.
4. Add them to the issue body: `gh issue edit $ARGUMENTS --body-file <tmpfile-with-full-body>`.

Create temp files with `mktemp`. If the issue already has criteria, use them as they are.

## 3. Plan

Before writing code:

1. For each criterion, list the files to change, the approach, and how you'll verify it.
2. Present the plan as a short list (criterion → files → verification).

Don't implement until the plan is clear.

## 4. Execute

Before editing any file, and again before each later round of edits, rebase on the latest default branch:

```bash
bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh sync
```

If `work`, `sync` or `finish` exits with status 3 (`CONFLICT=1`), resolve the conflicts yourself as the skill's **Rebase conflicts** section describes: merge each `CONFLICT_FILE` so both sides' intent survives, run `bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh continue` until it prints `CONFLICT=0`, re-run the interrupted command, then run the checks. Then:

- Follow the repo's documented conventions and the style of neighboring files.
- Stay within the issue's scope. Don't invent behavior the issue or the repo's docs don't call for.
- Note unrelated problems instead of fixing them, and record them as pending gaps (step 6).

## 5. Test

Run the repo's **own** checks. Find them in its docs and build files: `package.json` scripts, `Makefile`, `justfile`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `.github/workflows/`. Typical checks are lint, type-check, unit tests, and E2E tests if the repo documents them.

Don't guess commands the repo doesn't define. If it has no checks, say so. Fix failures before committing.

## 6. Commit & Finish

If the repo has a `context/progress-tracker.md`, first record every decision, gap and open item of this issue — as they come up, then checked again before the final commit — per the skill's **Pending gaps** section (global rule in `~/.claude/CLAUDE.md`): decisions → Architecture Decisions; pending/blocked items and problems found → Known Issues; done-but-unproven checks → To Verify; to-do → Next Steps; nice to have → Suggestions; questions for the user → Open Questions; tag each open item `[major]` or `[minor]`, small ones included; update existing entries instead of duplicating; mark items this task fixes, answers or verifies in place. Include it in the commit. After verification (step 7), the verification result is recorded too (`/gh-verify` step 5).

Before the last commit, do the skill's **Leftovers sweep**: unfinished or deferred work, skipped or partial steps, done-but-unproven checks, manual steps still waiting, clean-up not done, problems found on the way, and every follow-up the report will mention all go in the tracker, tagged `[major]`/`[minor]`.

Check `git status`, stage the files for this change explicitly, then commit and finish:

```bash
git add <paths>
bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh commit "<summary>" "<body>"
bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh finish
```

`finish` rebases and pushes. Only after the push is confirmed (GitHub's branch matches the local `HEAD`), it replaces `ONGOING-DEVELOPMENT` with `FOR-AGENT-REVIEW`, checks the labels, and posts the per-file changes comment. It prints `SHA=` and `STATUS=FOR-AGENT-REVIEW` on success. If it fails, the issue stays `ONGOING-DEVELOPMENT`; fix the cause and re-run `finish`. **Do NOT create a PR.**

## 7. Verify

Follow the `/gh-verify` procedure for #$ARGUMENTS:

1. Take the acceptance criteria from the issue body.
2. Check each criterion against `git diff <REMOTE>/<BASE>...HEAD` and the source.
3. Post a verification comment with ✅/❌ and evidence for each criterion, plus the change summary.
4. Report any unmet criterion clearly and suggest follow-up.

## Output

Report:
- Issue URL
- Branch name and base
- Commits made
- Current status label (should be `FOR-AGENT-REVIEW`)
- Acceptance criteria status (all met / which are unmet)
- Verification comment URL
- Decisions, pending, to-verify, to-do, nice-to-have and leftover items (`[major]` first), and which progress-tracker sections they're in — never an open item the tracker doesn't have; "Leftovers: none" when there are none

Current repo state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Detected: !`bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh repo 2>&1 || true`

If the status shows uncommitted changes, stop and ask before starting.
