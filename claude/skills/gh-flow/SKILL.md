---
name: gh-flow
description: GitHub issue-to-completion workflow for any GitHub repo. Use whenever asked to implement a feature, hotfix, bugfix, chore, or general issue in a git repo hosted on GitHub — creates an issue titled "<type>: <title>", assigns it to you, adds it to the GitHub Project named after the repo (creating and linking it, with the Labels column visible, if missing; status: In Progress), creates a linked <type>/<slug>-<issue#> development branch from the repo's default branch and records it on the issue, labels the issue ONGOING-DEVELOPMENT, commits as "<type>: <summary>", pushes, comments a line-by-line changes summary, and swaps the label to FOR-AGENT-REVIEW (does not create a PR). Also works existing issues (reopens if closed, creates acceptance criteria if missing) and verifies acceptance criteria after completion.
license: MIT
metadata:
  labels: "issue feature hotfix bugfix chore"
---

# gh-flow

Every code change goes through the same path:
**issue → branch → code → commit → push → issue-comment**. The helper script does the
git and GitHub steps and checks the naming rules. You do the coding and write
the text.

Nothing is hardcoded to a repository. The script detects everything from the
current checkout.

## Helper script

Use the first path that exists (check with `ls`):

- `.claude/skills/gh-flow/scripts/gh-flow.sh` (installed in the repo)
- `~/.claude/skills/gh-flow/scripts/gh-flow.sh` (installed globally)

Below, this path is written as `GHF`. Always call it with `bash <path> ...`.
Shell variables don't carry over between tool calls, so write the full path
every time.

| Step | Command |
|---|---|
| Detect repo | `bash GHF repo` (prints `OWNER`, `NAME`, `REPO`, `REMOTE`, `BASE`, `PROJECT`) |
| Ensure project | `bash GHF project` (create + link the repo-named project if missing; show the Labels column) |
| Start (new issue) | `bash GHF start <type> "<issue title>" "<issue body>"` |
| Work (existing issue) | `bash GHF work <issue-number>` |
| Sync (before every edit round) | `bash GHF sync` (rebase the current dev branch on the latest `<remote>/<base>`) |
| Continue (after resolving conflicts) | `bash GHF continue` |

## Rebase conflicts: detect and fix automatically

Every rebase on `<remote>/<base>` (`work`, `sync`, `finish`) detects conflicts.
When it hits one, the script leaves the rebase in progress, prints
`CONFLICT=1` and a `CONFLICT_FILE=<path>` line per file, and exits with status **3**.
Don't stop and ask; resolve it yourself:

1. Open each `CONFLICT_FILE`. Between `<<<<<<<` and `=======` is the base
   branch's version (what's already on `<base>`); between `=======` and `>>>>>>>` is
   this branch's commit being replayed.
2. Merge them so **both sides' intent survives**: keep new upstream code and
   re-apply this branch's change on top of it. For lists, logs, and docs (e.g. a
   progress tracker), keep both entries. Remove every conflict marker.
3. Run `bash GHF continue`. It stages the fixes, refuses if any marker is left,
   and finishes the rebase. If a later commit conflicts too, it exits **3** again;
   repeat from step 1.
4. When it prints `CONFLICT=0`, re-run the interrupted command (`work <n>`,
   `sync`, or `finish`). It's safe to re-run.
5. After resolving, run the repo's checks before committing or finishing. A
   textually clean merge can still break the build.

Only ask the user if the two sides contradict each other and the issue and
repo docs don't say which behavior is intended.
| Commit | `git add <files>` then `bash GHF commit "<summary>" "<body>"` |
| Finish | `bash GHF finish "<comment body>"` (push + comment on issue, no PR) |

## Repo detection

| Value | How it is found | Override |
|---|---|---|
| Remote | `origin`, else the first remote | `GH_FLOW_REMOTE` |
| Repo (`owner/name`) | Parsed from the remote URL (https, ssh, ssh aliases, GitHub Enterprise) | — |
| Base branch | The remote's default branch (`<remote>/HEAD`, then the GitHub API) | `GH_FLOW_BASE` |
| Project | The GitHub Project, user- or org-owned, whose title equals the repo name. **Created and linked to the repo when missing**, and every table view shows the **Labels** column | `GH_FLOW_CREATE_PROJECT=0` disables creation |

Run `bash GHF repo` first and use its `BASE` and `REMOTE` wherever this skill
says `<base>` or `<remote>`. Never assume `main` or `origin`.

If there's no project with the repo's name, `start`/`work`/`project` create one under the
repo's owner (user or organization), link it to the repo, and make the **Labels** column
visible in its table views, so the `ONGOING-DEVELOPMENT` / `FOR-AGENT-REVIEW` status labels
show on the board. Existing projects get the Labels column the next time they're used. With
`GH_FLOW_CREATE_PROJECT=0` the script only warns and skips the project step. If the `gh` token lacks project access, it says to run
`gh auth refresh -s project`.

## Type: pick exactly one

The type goes in the issue title, branch name and commit subject. It is **not**
added to the issue as a GitHub label.

| Type | Use for |
|---|---|
| `issue` | General task or issue not yet classified as feature/bugfix/chore |
| `feature` | New user-facing or API functionality |
| `bugfix` | Wrong behavior that is not an urgent production incident |
| `hotfix` | Urgent fix for something broken in production right now |
| `chore` | Dependencies, CI/CD, config, tooling, docs, refactors with no behavior change |

If the user named a type, use that one. If the request fits more than one
type (for example "fix + small refactor"), choose based on the user-visible
effect. Ask the user only if the choice is still unclear after that.

## Development section (linked branch)

GitHub lists a branch under an issue's **Development** section only when GitHub
itself created the branch for that issue (`gh issue develop`). It can't link a
branch that already exists. So gh-flow always lets GitHub create the branch:
at `start`/`work` for a new branch, or at `finish` just before the first push if it
had to be created locally.

A branch that was already pushed without a link can't be linked afterwards
without deleting and recreating it. gh-flow never does that; it warns instead.
The branch is still recorded in the issue body.

## Status labels

The only labels gh-flow sets are these two status labels. Each one replaces the other:

| Label | Set by | Meaning |
|---|---|---|
| `ONGOING-DEVELOPMENT` | `start`, `work` | Development has started on the branch |
| `FOR-AGENT-REVIEW` | `finish` | Development is done and pushed; ready for agent/AI review |

Both are created in the repo when missing. GitHub label names ignore case, so an
existing label with different casing (e.g. `for-agent-review`) is renamed to
the uppercase form, not duplicated.

## Naming

| Thing | Format | Example |
|---|---|---|
| Issue title | `<type>: <title>` | `bugfix: Fix login timeout on slow networks` |
| Branch | `<type>/<slugified-title>-<issue-number>` | `bugfix/fix-login-timeout-on-slow-networks-37` |
| Commit subject | `<type>: <summary>` (≤ 72 chars) | `bugfix: retry token refresh on network timeout` |

The script adds the type prefix to issue titles and commit subjects. Pass only
the title or summary. `bash GHF slug "<title>"` prints the branch slug without
running anything.

## Procedure

### 0. Preflight
- Run `gh auth status`, `git status --short`, and `bash GHF repo`.
- If there are uncommitted changes, **stop and ask** whether to stash or commit
  them. Never throw them away.

### 1. Issue + branch
- Title: short and imperative, 60 characters or fewer.
- Body: use this format:
  ```
  ## Context
  <why this is needed / what's broken>

  ## Acceptance criteria
  - [ ] <observable outcome>
  - [ ] <tests added/updated>
  ```
- Run `start`. It prints `REPO=`, `BASE=`, `REMOTE=`, `ISSUE=`, `ISSUE_URL=`,
  `BRANCH=`, `LABEL=` (the type), `TITLE=`. Remember these. The script:
  1. Creates the issue titled `<type>: <title>` with no type label, and assigns it to you (`@me`)
  2. Adds the issue to the repo-named GitHub Project with status "In Progress" (creating and
     linking the project, with the Labels column visible, if it doesn't exist yet)
  3. Creates the development branch `<type>/<slug>-<issue#>` from `<base>` on GitHub
     with `gh issue develop`, which links it under the issue's **Development**
     section, then checks it out locally. If the branch already exists, it checks
     it out and rebases on `<remote>/<base>`. If GitHub couldn't create it, the branch
     is created locally and linked at `finish`, before the first push.
  4. Updates the issue body with `## Development` / `Branch: \`<branch>\``
  5. Adds the `ONGOING-DEVELOPMENT` label

### 2. Implement
- Read the code before changing it. Follow the repo's own conventions: its
  CLAUDE.md, AGENTS.md, CONTRIBUTING.md, linters and formatter config, and
  neighboring files.
- Keep changes limited to the issue. If you notice work that isn't related,
  mention it at the end instead of doing it.
- Add or update tests. Before each commit, run the repo's own lint, type-check
  and test commands. Find them in its docs or build files (`package.json` scripts,
  `Makefile`, `pyproject.toml`, `Cargo.toml`, `go.mod`, CI workflows). Fix failures.
  If the repo has none, say so.
- Stay on the development branch. **Every time you start working or go back to
  editing files** (including follow-up changes, review fixes, or a new session on
  an existing branch), run `bash GHF sync` first. It rebases the branch on the
  latest `<remote>/<base>`. If it exits 3 (conflict), follow **Rebase conflicts**
  above, then continue editing.

- **Keep the README's setup and sign-up instructions current.** When the change
  adds or changes something a person has to do by hand, update the `README.md` of
  the repo that owns that step, in the same issue. This covers one-time setup
  (Vault paths and policies, secrets, accounts, registering an app at a provider,
  DNS or tunnel routes, deploy order) and the sign-up, sign-in or onboarding flow
  as its users see it. Write steps someone can follow without asking you: what to
  open, the values to enter, the command to run, and how to check it worked. A
  step owned by another repo goes into that repo's README (its own issue), with a
  one-line pointer here. Also correct any README text the change makes untrue. If
  nothing a person does changes, leave the README alone. Before the last commit,
  check that no README step this change touched is out of date.

### 3. Commit (one or more times)
- Stage files explicitly with `git add <paths>` after checking `git status`.
  Never use `git add -A` or `git add .` without checking first.
- Summary: imperative, lowercase start, no trailing period. The script adds the
  `<type>: ` prefix and a `Refs #<issue>` trailer.
- Body: explain *what* changed and *why* in 1–5 short lines or bullets. Don't
  restate the diff.
- Example result:
  ```
  bugfix: retry token refresh on network timeout

  - Wrap refresh call in exponential backoff (3 attempts)
  - Surface a user-facing error after final failure

  Refs #42
  ```
- Split the work into logical commits when that makes sense, such as the
  change itself and its tests.

### 4. Push + comment on issue (no PR)
- Run `finish` with an optional comment body. The script:
  1. Rebases on `<remote>/<base>`
  2. If the branch isn't on GitHub yet, has GitHub create it linked to the issue
     (so it appears under **Development**), then pushes the branch. If the branch was pushed before, it uses
     `--force-with-lease`, because the rebase rewrote it. That refuses to push
     if anyone else pushed to the branch.
  3. Confirms the push: GitHub's branch must point at the local `HEAD`
  4. **Only after a confirmed push**, replaces `ONGOING-DEVELOPMENT` with
     `FOR-AGENT-REVIEW`, then re-reads the issue's labels to check it worked
  5. Posts a comment on the issue: file statistics, the changed lines per file,
     the branch, and the commit list
- Steps 2–5 are each **retried** up to 3 times (2s, 4s, 8s apart) before giving up.
  Set `GH_FLOW_RETRIES` to change the count.
- If the push still fails or can't be confirmed, `finish` stops and the issue stays
  `ONGOING-DEVELOPMENT`. If the label swap still fails after a good push, `finish`
  stops with an error, never a silent warning. Fix the cause and run `finish` again;
  it's safe to re-run.
- `finish` prints `SHA=` and `STATUS=FOR-AGENT-REVIEW` on success.
- Do NOT create a PR.

### Pending gaps → the repo's progress tracker

This is the global rule in `~/.claude/CLAUDE.md` ("Record everything in the repo's progress tracker"), applied to gh-flow. When a repo keeps a context tracker (`context/progress-tracker.md`, usually pointed to from its CLAUDE.md / AGENTS.md), **every decision, gap, open item and verification result** of the current issue is written into it — as it comes up, and checked again before the final commit — so nothing lives only in chat, an issue comment or a commit message. Small items are recorded too.

| Item | Section |
|---|---|
| **Decision** — approach, tool, version, trade-off, scope cut, how an ambiguous request was read; by the user or by you | **Architecture Decisions** (date, what, why, alternatives, issue/ADR link; architectural ones also get an ADR) |
| **Pending** — started but unfinished, blocked, or waiting on someone or something (approval, credentials, a manual step, another repo, a deploy) | **Known Issues** (or a Pending section) |
| **Gap or problem found** — bugs, security or reliability gaps, repo/cluster drift, stale docs, an unmet criterion | **Known Issues** |
| **To verify** — done but not yet proven (manual or browser check, live call, post-deploy check, criteria not yet verified, untested assumption) | **To Verify** (create it after Known Issues if missing) |
| **Verification result** — each `/gh-verify` report | **Verification Log** (create it if missing): date, issue, verdict, comment link; unmet criteria also in Known Issues |
| **To-do** — agreed or clearly required next work | **Next Steps** |
| **Nice to have** — improvements nobody has asked for yet | **Suggestions / Future Suggestions** |
| **Questions only the user can answer** | **Open Questions** |
| **Fixed / answered / verified by this issue** | mark in place: `~~…~~ — fixed in #N` / `— answered <date>` / `— verified <date> (link)` (don't delete) |

- Tag every open item **`[major]`** (blocks merge or deploy, security or data-loss risk, user-visible breakage, needs a user decision) or **`[minor]`** (everything else)
- One numbered line or bullet each: what, where, why it matters, and what's needed (decision, manual step, other repo, date)
- Update an existing entry instead of adding a duplicate
- A gap in another repo goes into that repo's tracker (its own issue), with a one-line pointer here

Commit the tracker update with the change (same issue). If the repo has no tracker, list the items in the `finish` comment and the final report, and offer to create one.

**Leftovers sweep (before the last commit and `finish`)** — the global `CLAUDE.md` rule. List everything the issue leaves behind and check each one is in the tracker, tagged: unfinished or deferred work and cut scope; skipped, impossible or partial steps (tests, checks, a deploy, a verification); done-but-unproven checks (To Verify); manual steps still waiting; clean-up not done (temp files, containers, branches, test data, unused secrets, resources kept for rollback); problems noticed on the way (another repo's go into its tracker); and every follow-up, risk or question the `finish` comment or report will mention. If something turns up after `finish`, record it, commit and `finish` again.

### 5. Report
Reply with the issue URL, branch, commit list (`git log --oneline <remote>/<base>..HEAD`),
and anything not done. Every decision, pending, to-verify, to-do, nice-to-have and leftover item you
mention must already be in the repo's progress tracker (see above) — the report never mentions an open
item the tracker doesn't have — and the report says which tracker sections you updated, `[major]` items
first, or "Leftovers: none". The issue stays open. The user decides when it is **Done**.

## Working on Existing Issues

When asked to work on an existing issue (e.g., `/gh-issue 42`), use `work` instead of `start`:

```bash
bash GHF work <issue-number>
```

1. Fetches the issue from the detected repo
2. **Reopens it if closed** (logs a notice, does not refuse)
3. Takes the type from the title's `<type>: ` prefix. Older issues without a prefix
   fall back to a `feature`/`bugfix`/`hotfix`/`chore`/`issue` label; the default is `issue`.
4. Takes the branch slug from the title, without the `<type>: ` prefix
5. Assigns you (`@me`) and adds the issue to the repo-named project with status "In Progress"
6. **Work commences:** sets `ONGOING-DEVELOPMENT`, removing `FOR-AGENT-REVIEW` if the
   issue is coming back from review
7. Checks out the branch and rebases it on `main` as part of ongoing development:
   - Local branch exists → checkout + rebase on `<remote>/<base>`
   - Remote-only branch → create local tracking branch + rebase on `<remote>/<base>`
   - No branch → create it on GitHub linked to the issue (`gh issue develop`), then check it out
   - Rebase conflict → exits 3; follow **Rebase conflicts**, then re-run `work <n>`
8. Updates the issue body with the development branch
9. Prints `REPO=`, `BASE=`, `REMOTE=`, `ISSUE=`, `ISSUE_URL=`, `BRANCH=`, `LABEL=`, `TITLE=`,
   then `BODY=` followed by the full multi-line issue body

### Acceptance criteria

After `work`:

1. **Check** whether the issue body has an `## Acceptance criteria` section.
2. **If missing**: write concrete, testable criteria from the issue and the repo's
   docs and code. Post them as an issue comment and add them to the issue body.
3. **If present**: use them as they are for planning and verification.

### Full existing-issue flow

```
work → criteria check → plan → implement → test → commit → finish → verify
```

## Verification

### When to verify

- **Always** at the end of `/gh-issue`
- On demand via `/gh-verify <issue-number>`
- Before closing an issue or merging related branches

### Procedure

1. Fetch the issue's acceptance criteria from the issue body.
2. Run `bash GHF repo`, then `git fetch <remote> <base>`, then compare against the remote base:
   ```bash
   git log <remote>/<base>..HEAD --oneline
   git diff <remote>/<base>...HEAD --stat
   ```
3. For each criterion, look for evidence in the diff and source files:
   - **✅ Met**: give file paths, function names, or a short explanation
   - **❌ Not met**: explain what's missing
4. Write the report to a temp file (`mktemp`) and post it with
   `gh issue comment <n> --body-file <file>`.
5. Record the result in the repo's progress tracker (required): a **Verification Log** line (date, issue,
   verdict, comment link); unmet criteria → **Known Issues** (`[major]` if they block the merge); criteria
   the diff can't prove (live deploy, browser check, real API call) → **To Verify**; anything else noticed
   → its section. Commit on the issue's branch and `finish` (or a `chore` if already merged).
6. Report the verdict to the user, the unmet and to-verify criteria, and what was recorded where.

### Report format

```markdown
## Verification Report

**Branch:** `<branch>` (vs `<base>`)
**Verified:** <date>

### Acceptance Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | ... | ✅ Met | `path/to/file:42` |
| 2 | ... | ❌ Not met | Missing X |

### Change Summary
- <commit messages>

### Incomplete Items
- [ ] Criterion 2 — needs X

### Verdict
✅ All criteria met / ❌ N criteria unmet
```

## Workflow Rules

1. **Type**: `issue`, `feature`, `bugfix`, `hotfix`, or `chore`, carried in the title only (no type label)
2. **Issue title**: `<type>: <title>`
3. **Commit**: `<type>: <summary>`
4. **Branch**: `<type>/<slugified-title>-<issue-number>`, created from the repo's default branch and linked to the issue
5. **Assignee**: the current GitHub user is assigned automatically
6. **Project**: the issue is added to the GitHub Project named after the repo; the project is created (linked, Labels column visible) if missing
7. **No PR**: don't create a PR after the task
8. **Issue comments**: every push gets a per-file changes comment on the issue
9. **Branch in issue**: the issue body records the development branch as soon as it is created
10. **Status labels**: `ONGOING-DEVELOPMENT` when development starts; replaced by `FOR-AGENT-REVIEW` when it's done
11. **Rebase**: rebase on `<remote>/<base>` every time work starts or files are about to change. `start` branches from the latest base, `work` rebases, `sync` rebases before each round of edits, and `finish` rebases before pushing
12. **Keep branches**: never delete the local development branch
13. **Plan first**: present a plan and explain the changes before editing
14. **Reopen**: when working an existing issue, reopen it if closed
15. **Acceptance criteria**: create them if missing; always verify after completion
16. **Pending gaps**: everything the issue leaves undone — pending, to-do, nice to have, open questions — goes into the repo's `context/progress-tracker.md` (Known Issues / Next Steps / Suggestions / Open Questions) in the same commit; fixed items are marked fixed (global rule, `~/.claude/CLAUDE.md`)
17. **Leftovers sweep**: before the last commit, check that every leftover — unfinished, skipped, unproven, waiting on someone, clean-up not done, problems found, follow-ups the report mentions — is in the tracker; the report never mentions an open item the tracker doesn't have
18. **README instructions**: a change to a manual setup step or to the sign-up, sign-in or onboarding flow updates the owning repo's `README.md` in the same issue (Implement step)

## Rules
- Never commit directly to the base branch, plain force-push, or delete branches
  unless the user explicitly asks. The only force push is `finish`'s
  `--force-with-lease` after its own rebase.
- Never skip hooks (`--no-verify`). If the commit-msg hook rejects a message,
  fix the message. Run `bash GHF install-hook` to install the hook in a repo.
- If any `gh` or `git` step fails, show the error, fix the cause (auth, missing
  remote, conflicts), and retry once. If it still fails, stop and ask the user.
- If the user asks to continue on an existing flow branch, skip step 1, run
  `bash GHF sync`, and keep using that branch's type and issue.
