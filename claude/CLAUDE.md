# Global instructions

These apply in every project and every session.

## Record everything in the repo's progress tracker — decisions, gaps, things to verify, big or small

In a repo that keeps a progress tracker (`context/progress-tracker.md`, or the file its CLAUDE.md / AGENTS.md names), **every** decision, gap, open item and verification result is written there. This covers every kind of task, not only gh-flow issues: features, fixes, reviews, verifications, investigations, deployments, incidents, and questions whose answer uncovers work. Nothing lives only in chat, in an issue comment, or in a commit message. No item is too small to record.

Read the tracker at the start of a task. Record items **as they come up** (a decision made, a gap found, a check you couldn't do), and check the tracker again before the final commit.

| Item | Goes in |
|---|---|
| **Decision** — anything chosen, by the user or by you: approach, tool, version, trade-off, scope cut, interpretation of an ambiguous request | **Architecture Decisions** — date, what, why, alternatives rejected, issue/ADR link. A decision that changes the architecture also gets an ADR (`docs/adr/`) if the repo uses them |
| **Pending** — started but not finished, blocked, or waiting on someone or something (approval, credentials, a manual step, another repo, a deploy) | **Known Issues** (or a Pending section if the tracker has one) |
| **Gap or problem found** — bug, security or reliability gap, drift between repo and cluster, stale docs, a criterion not met | **Known Issues** |
| **To verify** — done but not yet proven: a manual check (browser sign-in, live API call), a post-deploy check, acceptance criteria without a verification report, an assumption you couldn't test | **To Verify** (create the section after Known Issues if missing) |
| **Verification result** — every acceptance-criteria verification report posted | **Verification Log** (create the section if missing): date, issue, verdict, link to the report comment. Unmet criteria also go to Known Issues |
| **To-do** — agreed or clearly required next work | **Next Steps** |
| **Nice to have** — improvements nobody has asked for yet | **Suggestions / Future Suggestions** |
| **Questions only the user can answer** | **Open Questions** |
| **Done / answered / verified** | Mark it in place, e.g. `~~…~~ — fixed in #N` / `— answered 2026-10-26: …` / `— verified 2026-10-26 (link)`; never delete it |

- Tag every open item with its size: **`[major]`** — blocks a merge or deploy, security or data-loss risk, user-visible breakage, or a decision needed from the user; **`[minor]`** — everything else. Small items are recorded too.
- One numbered line or bullet per item: what, where, why it matters, and what's needed (decision, manual step, other repo, date).
- Look for an existing entry first and update it rather than adding a duplicate.
- A gap that needs a change in another repo goes into **that** repo's tracker; leave a one-line pointer in the current one.
- Commit tracker edits together with the change they belong to. A tracker-only update is its own `chore` (gh-flow `/gh-task chore …`), or a commit on the issue's own branch when it records that issue's verification.
- If the repo has no tracker: list the items in the final report (and in the gh-flow issue comment) and offer to create one.
- The final report says what was recorded, in which tracker and section, and lists the `[major]` items first.

### Leftovers sweep — before the final report

Before the last commit and the final report, list everything the task leaves behind and make sure each one is in the tracker, in its section, tagged `[major]`/`[minor]`:

- work not finished, and scope that was cut or deferred
- steps skipped, not possible, or only partly done: tests, checks, a deploy, a verification
- things done but not proven → **To Verify**
- manual steps waiting on the user or someone else
- clean-up not done: temporary files, containers, branches, test data, unused secrets, old resources kept for rollback
- README setup or sign-up steps the change made out of date (gh-flow Workflow Rule 18)
- problems noticed on the way, including in other repos (→ that repo's tracker, with a pointer here)
- every follow-up, suggestion, risk or question the final report is about to mention

**The final report must not mention an open item the tracker doesn't have.** If you find one while writing the report, record it and commit it first. Say "Leftovers: none" when there are none. Without a tracker, list the leftovers in the report under **Leftovers** and offer to create one.

## Plan first, then ask before executing

Before any task that changes something — editing files, creating repos or issues, committing, pushing, deploying, changing a cluster, writing secrets — follow the `plan-first` skill (`~/.claude/skills/plan-first/SKILL.md`), in every project:

1. Investigate read-only.
2. Present the plan: current state, flow, changes per repo/file, decisions with rejected alternatives, risks `[major]`/`[minor]`, the user's manual steps, verification, out of scope, decisions for the user.
3. Ask **Proceed / Change the plan / Stop**, and wait. Answering the plan's questions is not a "proceed" by itself.
4. After "proceed": record the plan's decisions and open items in the tracker, then execute within the plan. A deviation (new scope, repo, dependency, deploy, Vault write) needs a new approval.
5. Before the final report: do the **leftovers sweep** above.

Skip the plan only when the user says "just do it" (or similar), for read-only questions, or for steps the approved plan already covers.
