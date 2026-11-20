---
description: Verify an issue's acceptance criteria against the current branch and post a verification comment
argument-hint: <issue-number>
allowed-tools: Bash(git:*), Bash(gh:*), Bash(bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh:*), Bash(mktemp:*), Read, Edit, Write, Grep, Glob
---

Verify that the current branch meets the acceptance criteria of GitHub issue **#$ARGUMENTS** in the current repository.

Use the `REMOTE` and `BASE` values from "Detected" below; never assume `main` or `origin`.

## 1. Fetch Issue

```bash
gh issue view $ARGUMENTS --json number,title,state,body,url
```

Take the `## Acceptance criteria` section from the body. If there isn't one, say the criteria are undefined and stop.

## 2. Identify Current Work

Compare against the up-to-date remote base, not a possibly stale local branch:

```bash
git fetch <REMOTE> <BASE>
git log <REMOTE>/<BASE>..HEAD --oneline
git diff <REMOTE>/<BASE>...HEAD --stat
```

If the branch has no commits ahead of `<REMOTE>/<BASE>`, say there is no work to verify and stop.

## 3. Verify Each Criterion

For each checkbox:

1. Read the criterion.
2. Look for evidence in `git diff <REMOTE>/<BASE>...HEAD` and the relevant source files.
3. Mark it **✅ Met** or **❌ Not met**.
4. Give evidence: file paths with line numbers, function names, or a short explanation.

Be honest. Don't mark a criterion met without concrete evidence.

## 4. Post Verification Comment

Create a temp file with `mktemp` and write the report into it with this structure:

```markdown
## Verification Report

**Branch:** `<branch>` (vs `<BASE>`)
**Verified:** <date>

### Acceptance Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | ... | ✅ Met | `path/to/file:42` |
| 2 | ... | ❌ Not met | Missing X |

### Change Summary

- <commit 1>
- <commit 2>

### Files Changed

<file list from git diff --stat>

### Incomplete Items

- [ ] Criterion 2 — needs X

### Verdict

✅ All criteria met / ❌ N criteria unmet
```

Then post it:

```bash
gh issue comment $ARGUMENTS --body-file <tmpfile>
```

Use **❔ To verify** instead of ✅/❌ for a criterion the diff can't prove (a live deploy, a browser sign-in, a real API call) and say what check would prove it. List those under **Incomplete Items** too.

## 5. Record the Result in the Tracker (required)

If the repo has a `context/progress-tracker.md` (global rule in `~/.claude/CLAUDE.md`):

1. **Verification Log** (create the section after Known Issues if missing): one line — date, `#<n>`, verdict, link to the comment just posted
2. Each **❌ Not met** criterion → **Known Issues**, tagged `[major]` if it blocks the merge, else `[minor]`
3. Each **❔ To verify** criterion → **To Verify** (create the section if missing), with the check that would prove it
4. Decisions, gaps, follow-ups or questions you noticed while verifying → their sections (Architecture Decisions, Known Issues, Next Steps, Suggestions, Open Questions); update existing entries instead of duplicating
5. **Leftovers sweep** (skill and global `CLAUDE.md`): checks you couldn't run, clean-up not done (test data, containers, temp files), and anything the report will mention are in the tracker, tagged `[major]`/`[minor]`
6. Commit on the issue's own branch: `git add context/progress-tracker.md`, `bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh commit "record verification of #<n>" "<verdict>"`, then `bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh finish "<one-line verdict + comment link>"`. If the branch was already merged, use a `chore` issue instead (`/gh-task chore …`)

If the repo has no tracker, put these items in the report and offer to create one.

## Output

Report to the user:
- Verification comment URL
- Verdict (all met / which unmet / which still to verify)
- What was recorded in the tracker, in which sections, `[major]` items first, and the commit — never an open item the tracker doesn't have; "Leftovers: none" when there are none

Current repo state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Detected: !`bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh repo 2>&1 || true`
