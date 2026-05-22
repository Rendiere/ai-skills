---
name: landing-the-plane
description: Use when the user says "let's land the plane", asks to get current work into production, ship a feature, cut a release, or merge dev into main. Shepherds work feat → dev → main with mandatory /verify runs on every UI-touching PR and a full UAT-script sweep (mobile + web) gating any dev→main release.
---

# Landing the Plane

## Purpose

Get current work into production via the `feat/* → dev → main` flow, **with verification gates that cannot be skipped**. This skill replaces ad-hoc release behaviour with a single rule set:

1. **Every PR that touches UI runs `/verify` before merge.** UI = anything under `client/`, any `.tsx` file, any `.css`/Tailwind change, any route, any user-facing copy, any email template.
2. **Every `dev → main` release runs the full UAT script sweep locally** — mobile + desktop breakpoints — using the Etch UAT sheet as source of truth.
3. **Quality gates fix-forward.** Tests, lint, types, builds, deploys: red means stop and fix, not defer.

This applies to features, bugfixes, chores, copy changes, infra tweaks — **all PRs**, no exceptions.

## When to Use

Triggers:
- User says "land the plane", "let's ship this", "cut a release", "promote to main", "merge dev to main".
- A feature branch is ready to PR into `dev`.
- `dev` has accumulated changes that need promoting to `main`.
- A bugfix or hotfix needs to reach production.

Do NOT use this skill for:
- WIP commits or experimental branches that aren't being shipped yet.
- Documentation-only PRs that touch no `client/`, server route, or user-visible string (still PR via dev, but skip the verify sweep — see [PR Type Matrix](#pr-type-matrix)).

## The Two Gates

### Gate 1 — Feature branch → `dev` (per-PR verify)

**Trigger:** any PR with `client/` or `.tsx` changes, or that touches user-visible copy / emails / public routes.

Before requesting merge:

1. Run `/verify <task-id>` against the Beads task's acceptance criteria.
   - **Verify against the LOCAL dev server** (`localhost:5001`, `make dev-clean`) — before the PR is merged, never against the post-merge dev deploy.
   - Use Playwright MCP — not manual review, not unit tests.
   - Capture screenshots into `docs/verification/<YYYY-MM-DD>-<task-id>/`. This must be a **committed** location — do NOT use `e2e/verify/`, it is gitignored and screenshots there cannot be referenced from a PR.
2. Write the verification report back to the Beads task as a comment.
3. **Post the screenshots to the PR** — commit the `docs/verification/...` folder on the PR branch, then add a PR comment embedding them. See [Attaching screenshots to a PR](#attaching-screenshots-to-a-pr) for the exact URL form (the repo is private — `raw.githubusercontent.com` will NOT render).
4. If `/verify` returns PARTIAL or FAIL: fix and re-run. Do not push past a failing verify.
5. Only after a clean PASS comment on the task AND screenshots visibly rendering on the PR: green-light the merge.

If the PR has no associated Beads task (rare — back-merge, dependency bump, etc.), still run a focused local Playwright pass on the affected surface(s) and post the screenshots + outcome to the PR per the section below.

### Attaching screenshots to a PR

`sudo-labs-uk/etch` is a **private** repo. This breaks the obvious approaches:

- ❌ `raw.githubusercontent.com/...` — GitHub fetches this anonymously; private-repo blobs 404, image shows broken.
- ❌ Dragging into the web UI — not available from the CLI.

✅ **Correct method:**

1. Commit the screenshots on the PR branch under `docs/verification/<YYYY-MM-DD>-<task-id>/` and push. (They also render in the PR's "Files changed" tab this way.)
2. Embed them in a PR comment using the **`github.com` blob URL pinned to the commit SHA**, with `?raw=true`:

   ```markdown
   ![desc](https://github.com/sudo-labs-uk/etch/blob/<commit-sha>/docs/verification/<dir>/<file>.png?raw=true)
   ```

   This URL is on the `github.com` domain, so a logged-in reviewer's session authenticates the image fetch and it renders. Pin to the **commit SHA**, not the branch name (branch names with `/` break the URL and move under you).

3. Post via `gh pr comment <n> --body "..."`. To **edit** an existing comment, `gh pr comment` has no edit flag — use `gh api repos/sudo-labs-uk/etch/issues/comments/<comment-id> -X PATCH -f body="$(cat file.md)"`.

**Account note:** `gh pr ...` auto-resolves the account with repo access, but `gh api ...` uses the *active* account. If `gh api` returns 404 on this repo, run `gh auth switch --user Rendiere` first (the account with `sudo-labs-uk` org access), then switch back when done.

After posting, confirm the images actually render — fetch `.body_html` for the comment and check the `<img src>` is still a `github.com/...` URL (not rewritten to a broken `camo` proxy):

```bash
gh api repos/sudo-labs-uk/etch/issues/comments/<id> \
  -H "Accept: application/vnd.github.full+json" --jq '.body_html' | grep -oE '<img[^>]*src="[^"]*"'
```

### Gate 2 — `dev` → `main` (UAT script sweep)

**Trigger:** any release PR from `dev` into `main`.

Before requesting merge to `main`:

1. Identify which UAT scripts the release could touch. The 6 outcome scripts (from `scripts/uat/launch_readiness.py`):
   1. **Artist onboards** — sign-up + sign-in (4 journeys)
   2. **2a. Artist joins a student show** — cohort onboarding wizard
   2. **2b. Artist creates a solo show** — independent onboard → create-show → add-artwork → edit-show → publish/schedule
   3. **Buyer fixed-price** — discover → buy now → abandon-checkout
   4. **Buyer auction** *(optional — gated on auction harness)*
   5. **Artist post-sale** — fulfil order, sales analytics, mark sold
   6. **Buyer post-sale** — track order, view invoice

   For each script that intersects the release diff, run it end-to-end via Playwright MCP **at both viewports**:
   - **Desktop:** 1440×900
   - **Mobile:** 390×844 (iPhone 14 baseline)

2. Pull the per-step ACs straight from the UAT sheet via the existing tooling:

   ```bash
   # Refresh local cache of the AC sheet
   python3 scripts/uat/sheet_helper.py cache 1fgy7Nd9bwZv48REqRRDAvYU7UnNhkt3oYkI-oywHvCM

   # Find the ACs for a specific journey/step
   python3 scripts/uat/sheet_helper.py find 'A:onboard-as-graduating-student:3-first-work-step:1'
   ```

3. As each AC is verified in the browser, update its row:

   ```bash
   python3 scripts/uat/sheet_helper.py update '<key>' status='✅ Pass' tester=claude
   ```

   Canonical statuses (use **only** these):

   ```
   ✅ Pass    ⚠ Pass w/ caveat    ❌ Fail    ⚠ Blocked    N/A    ☐ Not tested    ⏭ Skipped
   ```

4. Refresh the rollup and read the audience verdict:

   ```bash
   python3 scripts/uat/launch_readiness.py --write
   ```

   The `dev → main` PR may only merge when every script touched by the release is **zero Fail / Blocked / Not-tested** across both viewports.

5. Attach the readiness summary (or a link to the "Launch Readiness" tab) in the release PR description, with a note on which scripts were re-tested for this release and which were not impacted.

The UAT sheet (`1fgy7Nd9bwZv48REqRRDAvYU7UnNhkt3oYkI-oywHvCM`) is the **single source of truth** for what counts as a verified path. If a journey isn't in the sheet but is in the release, add it via `rows.py` first, then verify.

## Workflow (step by step)

### 1. Pre-flight

- File Beads issues for any follow-up work the release leaves behind.
- Run local quality gates: `make test`, `make lint`, `make typecheck`, `make build` (or project equivalents). Fix every failure, including pre-existing ones. Nothing moves until local is green.
- Sync the issue tracker (beads ↔ Linear). See `backlog-management` skill.
- Clean git state:
  ```bash
  git stash clear
  git remote prune origin
  ```
- Verify clean working tree, all commits pushed, no untracked release-relevant files.

### 2. Feat → dev

1. Open PR from `feat/*` into `dev`. Use `/close-linear` if the beads task carries a `linear:ETC-XX` label.
2. **Gate 1 — /verify**: run as described above. Block on PARTIAL/FAIL.
3. Monitor CI. Fix any red checks. Re-push until all green.
4. Merge.
5. Wait for `deploy-dev.yml` to complete (`gh run watch`). Fix and re-trigger if any step fails.
6. Open dev (`https://etch-213922615220.europe-west1.run.app`) via Playwright MCP. Smoke the changed surface against the live dev deploy. This is a sanity check, separate from Gate 1.

### 3. Dev → main

1. Open release PR from `dev` into `main`.
2. **Gate 2 — UAT script sweep**: run every impacted script at both viewports, update the sheet, refresh `launch_readiness.py --write`. Block on any non-Pass.
3. Monitor CI. Fix and re-push until green.
4. Present to the user for merge approval with:
   - Diff summary of what's in the release.
   - List of UAT scripts re-tested and their verdicts.
   - Link to the "Launch Readiness" tab.
5. After user-approved merge: wait for `deploy-prod.yml`. Fix and re-trigger if any step fails.
6. Verify prod (`https://etchapp.art`) via Playwright MCP — at minimum, smoke the surface that this release changed at both viewports.

### 4. Hand-off

Provide a prompt for the next session:

> "Continue work on `bd-X`: <title>. <Short context on what shipped and what's next.>"

## PR Type Matrix

| PR type | Gate 1 (/verify on PR to dev) | Gate 2 (UAT sweep on dev→main) |
|---|---|---|
| `client/` / `.tsx` change | ✅ Required | ✅ Required for any impacted script |
| Server route exposed to the app | ✅ Required (verify the route end-to-end via UI) | ✅ Required for any impacted script |
| User-visible copy (incl. emails, templates) | ✅ Required | ✅ Required for any impacted script |
| Schema / migration | ✅ Required (any UI that reads the changed shape) | ✅ Full sweep — schema bugs cross-cut everything |
| Infra / CI / workflow only | ⏭ Skip | ⏭ Skip (verify CI itself runs, not the UAT scripts) |
| Docs-only | ⏭ Skip | ⏭ Skip |
| Back-merge / dependency bump (no UI delta) | ⏭ Skip | ⏭ Skip unless the bumped dep touches a runtime path |

If you're unsure which row applies, treat the PR as the next-stricter row up. Cost of an extra verify is low; cost of a missed regression is a prod incident.

## Non-Negotiables

- **Never push directly to `main` or `dev`.** Always via PR.
- **Never `--delete-branch` on `dev` or `main` merges.** Only on `feat/*`/`fix/*`/`chore/*`. See `feedback_never_delete_dev_or_main.md`.
- **Never bypass `/verify` on UI PRs.** Static review caught a no-op wizard once (Wave 2, etch-83fi); Playwright would have caught it in 30 seconds. Code reading is not verification.
- **Never merge with red CI.** Even if the failure is "unrelated" — fix it.
- **Never invent UAT statuses.** Use the seven canonical strings above and nothing else; `normalize_statuses.py` exists to undo drift, don't create work for it.

## Tooling Reference

| Tool | Purpose |
|---|---|
| `/verify <task-id>` | Per-PR Playwright MCP run against Beads ACs. Loaded from `.claude/commands/verify.md`. |
| `scripts/uat/sheet_helper.py` | Read/write a single AC row in the UAT sheet. |
| `scripts/uat/launch_readiness.py` | Group ACs → outcome scripts → audience verdict. Re-run with `--write` after every AC change. |
| `scripts/uat/rows.py` | Source of truth for what ACs exist. Add new journeys here before verifying them. |
| `scripts/uat/README.md` | Full toolkit docs. |
| `gh run watch` | Block on a CI/deploy workflow until completion. |
| Playwright MCP | The browser. `browser_resize` to switch viewports between desktop (1440×900) and mobile (390×844). |

## Linked Memories

- [[reference_launch_readiness_rollup]] — the outcome-script model behind Gate 2.
- [[feedback_run_verify_on_ui_prs]] — why Gate 1 exists (WS2 waitlist regression).
- [[feedback_no_straight_to_main]] — no hotfix bypass; always feat → dev → main.
- [[feedback_fix_failures_immediately]] — Gate 1 and Gate 2 both fail-closed; fix-forward only.
- [[feedback_never_delete_dev_or_main]] — branch-delete safety on merge.
