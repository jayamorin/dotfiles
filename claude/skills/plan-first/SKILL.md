---
name: plan-first
description: Plan a change before making it — investigate read-only, present a structured plan (current state, flow, per-repo/file changes, decisions with rejected alternatives, risks, the user's manual steps, verification, out of scope, open questions), then ask the user to Proceed / Change / Stop. Use for every task that changes files, repos, infrastructure, secrets or deploys, in every project, unless the user says "just do it". Nothing is edited, committed, pushed, deployed or written to Vault before an explicit "proceed".
license: MIT
---

# plan-first

Every change starts with a plan the user approves. Planning is read-only; executing starts only after an explicit yes.

## When it applies

- **Always** for a task that would edit files, create repos, commit or push, deploy, change a cluster, or write secrets — in any project (global rule in `~/.claude/CLAUDE.md`).
- **Skip** only when the user says so ("just do it", "no plan", "go ahead"), for read-only questions, or for a follow-up step that the approved plan already covers.
- Approval covers the plan as presented. A change of scope, a new repo, a new dependency, a deploy or a Vault write that the plan didn't name needs a new approval.

## 1. Investigate (read-only)

- Read the repo's `CLAUDE.md` / `AGENTS.md` and its progress tracker (`context/progress-tracker.md` or the file those name).
- Read the code, branches and docs the task touches. Check what's merged vs. unmerged and what's deployed.
- Allowed: reading files, `git status/log/diff/fetch`, `make check`/tests, `kubectl get/describe`, `--dry-run`. Not allowed: edits, commits, pushes, issues, deploys, `kubectl apply|delete|edit`, Vault writes.

## 2. Present the plan

Use this structure; leave out a section only when it's genuinely empty.

```markdown
# Plan: <goal in one line>

## Current state
<what exists today and what's merged/unmerged/deployed — facts found in step 1>

## Flow
<diagram or numbered steps of how it will work afterwards>

## Changes per repo / file
**<repo>** (new / existing branch #N / new issue)
- <change> — <why>

## Decisions
- <choice> — <why>; rejected: <alternative> (<why not>)

## Risks
- [major] / [minor] <risk> — <mitigation>

## What you'll do
<manual steps only the user can do: accounts, secrets, repo creation, DNS, approvals>

## How I'll verify it
<tests, local end-to-end, post-deploy checks>

## Not included
<out of scope / later issues>

## Decisions for you
1. <question> — <options, recommendation first>
```

Keep it concise: concrete file and repo names, no restating the request, a recommendation for every open question.

## 3. Ask for confirmation

End with an `AskUserQuestion` call (or, if unavailable, a direct question) offering:

- **Proceed** — execute the plan as written (with the answers to "Decisions for you")
- **Change the plan** — the user says what to change; revise and present again
- **Stop** — do nothing further

Answers to "Decisions for you" alone are not a "proceed" unless the user says so; after recording them, ask once more with the updated plan summary.

## 4. After "proceed"

1. Record every decision, risk, pending item, manual step and to-verify item in the affected repos' trackers first (global tracker rule).
2. Execute through the repo's workflow (gh-flow for GitHub repos).
3. Stay within the approved plan. If something forces a deviation, stop, explain, and ask before continuing.
4. **Leftovers sweep** (global `CLAUDE.md`), before the last commit: everything the plan leaves behind goes into the affected repo's tracker, tagged `[major]`/`[minor]` — unfinished or deferred work, skipped or partial steps, done-but-unproven checks (To Verify), manual steps still waiting, clean-up not done (temp files, containers, branches, test data, old resources kept for rollback), problems found on the way (another repo's go into its tracker), and every follow-up, risk or question the report will mention.
5. Final report: what was done per repo, what's recorded where (`[major]` first), what's still waiting on the user. It must not mention an open item that isn't in a tracker; say "Leftovers: none" when there are none.
