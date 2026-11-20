---
name: gh-merge
description: "Merge a GitHub pull request only after its issue's acceptance criteria are verified. Use whenever asked to merge a PR (\"merge PR 12\", \"merge this\", \"file and merge the PR\", /gh-merge) in a git repo hosted on GitHub: finds the issue linked to the PR's development branch, runs the repo's tests and checks to satisfy each acceptance criterion, checks off (- [x]) every criterion that is met in the issue body, posts a verification report, records it in the repo's progress tracker, then merges (rebase preferred, branch kept). Blocks the merge on failing checks or unmet criteria, except criteria that can only be proven after a deploy; closes the issue only when every criterion is checked."
license: MIT
---

# gh-merge

A pull request is merged only after the issue it belongs to has had its acceptance criteria checked:
**PR → issue → criteria → run checks → tick what's met → report → tracker → merge → close if all ticked**.

It complements gh-flow (which never opens or merges PRs) and `/gh-verify` (which reports but doesn't tick or merge).
The helper script does the GitHub plumbing; you run the checks and judge each criterion.

## Helper script

Use the first path that exists: `.claude/skills/gh-merge/scripts/gh-merge.sh` (in the repo) or
`~/.claude/skills/gh-merge/scripts/gh-merge.sh` (global). Below it's `GHM`; always call it as `bash <path> …`.

| Step | Command |
|---|---|
| Find the issue | `bash GHM resolve [<pr>]` → `REPO PR STATE MERGEABLE HEAD BASE ISSUE ISSUE_VIA LINKED AUTO_CLOSE ISSUE_URL` |
| List criteria | `bash GHM criteria <issue>` → one line per criterion: `N<TAB>x\|-<TAB>text` (`x` = already checked) |
| Check off criteria | `bash GHM tick <issue> <n> [<n>…]` → edits only those `[ ]` → `[x]`, confirms on GitHub, prints `TICKED=` |
| Merge | `bash GHM merge <pr>` → rebase > squash > merge (whatever the repo allows), never deletes the branch, prints `MERGED= METHOD= SHA=` |

Exit codes: `2` issue ambiguous or missing · `4` no acceptance criteria · `5` PR not open or not mergeable.

## Procedure

### 0. Preflight
- `gh auth status`, `git status --short`. Uncommitted changes: **stop and ask** (stash or commit), never discard them.
- No PR yet (e.g. after gh-flow's `finish`): open one first — `gh pr create --base <base> --head <branch>`, title = the
  issue title, body `Refs #<issue>` plus the commit list. Don't write `Closes #<issue>`: closing is decided in step 8.

### 1. Find the issue
- `bash GHM resolve <pr>`. The issue comes from the PR's closing references, else the gh-flow branch suffix
  (`<type>/<slug>-<n>`), else a single `Refs #n` in the PR body or commits.
- Exit 2: show the candidates and ask the user which issue it is. Don't guess.
- `LINKED=no`: neither the branch nor the PR is under the issue's *Development* section. Say so in the report; it
  doesn't block.
- `AUTO_CLOSE=yes`: GitHub will close the issue when the PR merges. That happens when the PR says `Closes #n`, and
  also when it was opened from a branch linked to the issue: GitHub then moves the link from the branch to the PR.
  Step 8 reopens the issue if criteria are still open.
- `STATE` not `OPEN`: stop and report.

### 2. Read the criteria
- `bash GHM criteria <issue>`.
- Exit 4 (none): write concrete, testable criteria from the issue, the diff and the repo's docs, add them to the issue
  body under `## Acceptance criteria` (`gh issue edit --body-file`), post them as a comment, then continue.

### 3. Check out the PR head and bring it up to date
- `gh pr checkout <pr>`. If the PR is behind its base or `MERGEABLE=CONFLICTING`: on a gh-flow branch run
  `bash ~/.claude/skills/gh-flow/scripts/gh-flow.sh sync` (resolve conflicts per gh-flow's **Rebase conflicts**), then
  push with `--force-with-lease`. Never merge the base into the branch.

### 4. Run the checks
- Run the repo's own lint, type-check and tests (its README, CLAUDE.md / AGENTS.md, `Makefile`, `package.json`,
  `pyproject.toml`, CI workflow). **Never pipe a check into another command** — a pipe hides its exit status:
  `make check > "$log" 2>&1; echo rc=$?`, then read the log.
- Look at the PR's CI too: `gh pr checks <pr>`. A failing required check blocks the merge like a local failure.
- A criterion that names a specific behaviour may need its own focused test or command; run it.

### 5. Judge each criterion
For every criterion decide one of:

| Verdict | Meaning | Box |
|---|---|---|
| ✅ **Met** | Evidence now: a passing test or check, a file/function in the diff, a command's output | tick it |
| ⏳ **Post-deploy** | Can only be proven live after the merge and deploy (a live call, a browser check, a cluster state) — nothing in the code contradicts it | leave unchecked |
| ❌ **Not met** | Missing, wrong, failing, or unproven although it could be proven before merging | leave unchecked |

Be strict: "the code looks like it would" is not evidence when a test could prove it. A criterion already checked
(`x`) is re-verified, not trusted; if it no longer holds, say so in the report (don't untick silently — ask).

### 6. Tick, report, record
1. `bash GHM tick <issue> <met numbers…>` (skip when none are met).
2. Post the report on the issue (`gh issue comment <issue> --body-file <tmp>`), format below.
3. Record it in the repo's progress tracker (global `CLAUDE.md` rule): a **Verification Log** line (date, issue, PR,
   verdict, report link); ❌ items → **Known Issues** (`[major]`, they block the merge); ⏳ items → **To Verify**
   (`[major]` if a broken result would be user-visible). Commit the tracker on the PR branch
   (`gh-flow.sh commit`, or a plain `<type>: …` commit with `Refs #<issue>`), push, so it lands with the merge.
   No tracker: put the items in the report and the final reply, and offer to create one.

### 7. Merge — or don't
- **Merge** when the checks pass and every unchecked criterion is ⏳ post-deploy: `bash GHM merge <pr>`.
- **Don't merge** when any check fails or any criterion is ❌: report what's missing and stop. The user decides
  whether to fix it on the branch (gh-flow `work <issue>`) or to change the criterion.
- Exit 5 from `merge`: the PR isn't mergeable (conflicts, required review, merge queue). Report it; don't bypass
  branch protection (`--admin`) unless the user explicitly asks.

### 8. Close the issue — only when every criterion is checked
- All criteria ticked: `gh issue close <issue> -c "All acceptance criteria met; merged in #<pr> (<sha>)."`.
- Any ⏳ left: keep the issue open and comment which criteria wait for the deploy. If `AUTO_CLOSE=yes`, GitHub has
  just closed it: `gh issue reopen <issue> -c "<which criteria wait for the deploy>"`. After the deploy, verify them,
  tick them (`GHM tick`), update the tracker (To Verify → verified), and close the issue then.

### 9. Report to the user
PR and issue links, merge method and SHA (or why it wasn't merged), each criterion with its verdict, what was ticked,
what was recorded in which tracker section (`[major]` first), and the leftovers — or "Leftovers: none".

## Report format

```markdown
## Merge verification — PR #<pr>

**Issue:** #<issue> · **Branch:** `<head>` → `<base>` · **Verified:** <date>
**Checks:** `<command>` ✅ (<n> passed) · CI ✅

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | … | ✅ Met | `tests/test_x.py::test_y`, `src/x.py:42` |
| 2 | … | ⏳ Post-deploy | needs a live call after deploy |
| 3 | … | ❌ Not met | no test covers the empty case |

**Decision:** merged (rebase, `<sha>`) / not merged — <reason>
**Issue:** closed (all criteria met) / left open — criteria 2 wait for the deploy
```

## Rules
- Never merge with a failing check or a ❌ criterion; never tick a criterion without evidence.
- Never delete the branch, never force-push except `--force-with-lease` after gh-flow's own rebase, never skip hooks.
- Never merge the base into the branch (rebase instead); never bypass branch protection unless asked.
- Repo rules still apply: deploys, cluster changes and secret writes after the merge need the approvals the repo's
  `CLAUDE.md` / `AGENTS.md` ask for. gh-merge itself never deploys.
- Plan first (global `CLAUDE.md`): "merge PR 12" is the approval to verify and merge that PR. Anything beyond it —
  fixing code on the branch, editing criteria, deploying — needs its own approval.
