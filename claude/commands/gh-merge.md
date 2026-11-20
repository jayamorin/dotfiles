---
description: Merge a PR after verifying its issue's acceptance criteria (resolve issue → run checks → tick met criteria → report → tracker → merge → close if all met)
argument-hint: [<pr-number>]
allowed-tools: Bash(git:*), Bash(gh:*), Bash(bash ~/.claude/skills/gh-merge/scripts/gh-merge.sh:*), Bash(bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh:*), Bash(make:*), Bash(mktemp:*), Read, Edit, Write, Grep, Glob
---

Merge pull request **#$ARGUMENTS** in the current repository (no number: the current branch's PR) using the
**gh-merge** skill, following its procedure from start to finish.

The helper is `~/.claude/skills/gh-merge/scripts/gh-merge.sh`; always write the full path.

1. `resolve` the PR to its issue (ask if it's ambiguous), read the issue's acceptance criteria (`criteria`; write them if missing).
2. Check out the PR head, rebase it if it's behind, and run the repo's own lint, type-check and tests — never piped — plus `gh pr checks`.
3. Judge every criterion: ✅ met (evidence now), ⏳ post-deploy (provable only live), ❌ not met.
4. `tick` the met criteria, post the merge-verification report on the issue, and record it in the repo's progress tracker (Verification Log; ❌ → Known Issues; ⏳ → To Verify), committed on the PR branch.
5. Merge (`merge`) only if every check passes and every unchecked criterion is ⏳; otherwise stop and report.
6. Close the issue only if every criterion is checked; otherwise leave it open with a comment naming the post-deploy criteria.
7. Report the verdicts, the merge (method, SHA) or why not, what was recorded where (`[major]` first), and the leftovers — or "Leftovers: none".
