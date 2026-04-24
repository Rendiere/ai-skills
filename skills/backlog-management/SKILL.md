---
name: backlog-management
description: Use when syncing beads with Linear (or other stakeholder trackers), when Linear hits its issue limit, when deciding which beads should be visible to stakeholders, or when cleaning up a bloated issue tracker. Keeps Linear as a curated stakeholder view while beads holds all implementation detail.
---

# Backlog Management

## Overview

**Two trackers, two audiences.** Linear is the stakeholder/human view — epics, user-facing features, bugs worth reporting. Beads is the agent/implementation view — every task, sub-task, and internal detail. They must not be mirrors of each other, or Linear bloats and you hit the plan's issue cap.

**Core rule:** Only epics, features, and externally-visible bugs flow from beads to Linear. Implementation `task` beads stay local.

## When to Use

- Beads ↔ Linear sync returns `usage limit exceeded` on issue creation
- Linear has 200+ issues and most are implementation noise
- You're about to create a beads issue and wondering whether it belongs in Linear
- Stakeholders complain Linear is unreadable
- You want a clean epic view in Linear with child work summarised

## Sync Model

| Beads `issue_type` | Sync to Linear? | Meaning |
|---|---|---|
| `epic` | ✅ yes | High-level deliverable, stakeholder-tracked |
| `feature` | ✅ yes | User-facing unit worth external visibility |
| `bug` | ✅ yes | Bug the user/stakeholder would recognise |
| `task` | ❌ local only | Implementation step under an epic |
| `chore` | ❌ local only | Housekeeping |

**Default push command:**
```bash
bd linear sync --push --exclude-type=task,chore
```

Bidirectional sync on pull still imports everything from Linear (issues filed by humans there), and anything imported keeps a `linear:ETC-XX` label — use `/close-linear` for those.

## Creating Work

**Implementation tasks** (most work):
```bash
bd create "Playwright: cancel dialog wording" --type=task --parent=<epic-id>
```
No external_ref, never pushed to Linear.

**Stakeholder-visible deliverables:**
```bash
bd create "Epic: Show-gated auctions" --type=epic --labels=epic
# Sync will push this to Linear automatically on next `bd linear sync --push`
```

**When to promote a task → feature:** If you catch yourself explaining the task to the user (not the team), it probably belongs in Linear as a `feature`.

## Linear Cleanup Procedure

When Linear approaches its issue cap (250 on Free plan), run:

```bash
# 1. Check subscription & count
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query { organization { subscription { type } } team(id: \"TEAM_ID\") { issueCount } }"}'

# 2. Archive all Done + Canceled issues (reversible)
# Use scripts/archive-completed.sh (see below)
```

Archiving in Linear is soft-delete — it removes the issue from the cap but preserves history. Un-archive via Linear UI if needed.

### scripts/archive-completed.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${LINEAR_API_KEY:?need LINEAR_API_KEY}"
: "${LINEAR_TEAM_ID:?need LINEAR_TEAM_ID}"

# Fetch all completed + canceled issue IDs, archive each
query='query($teamId: ID!, $after: String) {
  issues(first: 100, after: $after, filter: {
    team: {id: {eq: $teamId}},
    state: {type: {in: [completed, canceled]}}
  }) { nodes { id identifier } pageInfo { hasNextPage endCursor } }
}'

after="null"
while :; do
  resp=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg q "$query" --arg t "$LINEAR_TEAM_ID" --argjson a "$after" \
        '{query:$q, variables:{teamId:$t, after:$a}}')")
  ids=$(echo "$resp" | jq -r '.data.issues.nodes[].id')
  for id in $ids; do
    curl -s -X POST https://api.linear.app/graphql \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"mutation{ issueArchive(id: \\\"$id\\\") { success } }\"}" \
      >/dev/null
    echo "archived $id"
  done
  hasNext=$(echo "$resp" | jq -r '.data.issues.pageInfo.hasNextPage')
  [ "$hasNext" = "true" ] || break
  after=$(echo "$resp" | jq -r '.data.issues.pageInfo.endCursor' | jq -Rs .)
done
```

## Summarising Children Into a Linear Epic

Linear epics should show their child beads as a checklist. Pattern:

```bash
# For beads epic <epic-id> already linked to Linear (has external_ref ETC-XX):
bd children <epic-id> --json | jq -r '.[] | "- [\(if .status=="closed" then "x" else " " end)] \(.title)"'
# → paste this block into the Linear issue description via GraphQL issueUpdate
```

Automate with a helper command `/sync-epic-to-linear <epic-id>` that:
1. Reads the beads epic and its children
2. Builds the checklist markdown
3. Fetches current Linear description, replaces/appends the `<!-- BEADS --> ... <!-- /BEADS -->` block
4. Posts `issueUpdate` via GraphQL

Keep the markers so the block is idempotent and won't clobber human-written description content.

## Closing a Linear-Originated Issue

Use the existing `/close-linear <task-id>` skill — it only fires on beads with a `linear:ETC-XX` label (set when the issue was pulled from Linear or pushed via sync). Beads without that label close with plain `bd close`.

## Red Flags

- **Creating a `task` bead for something a stakeholder will ask about** → use `feature` instead
- **Adding many `task` beads to Linear via default sync** → re-check the `--exclude-type=task` flag on the sync command or `bd config`
- **Pushing before cleanup when near the cap** → run `scripts/archive-completed.sh` first or new-issue creation fails silently
- **Editing a Linear epic description by hand after `/sync-epic-to-linear` set it** → your edits outside the `<!-- BEADS -->` markers are safe; edits inside will be overwritten on next sync

## Quick Reference

```bash
# Never sync every beads to Linear
bd linear sync --push --exclude-type=task,chore       # preferred default
bd linear sync --pull                                  # import human-filed issues

# Pre-flight before push
bd linear sync --dry-run --push --exclude-type=task,chore

# Periodic cleanup (run when total count > 200 on Free plan)
LINEAR_API_KEY=... LINEAR_TEAM_ID=... ./scripts/archive-completed.sh

# When creating new work, pick the right type
bd create "User-facing deliverable" --type=feature     # → Linear
bd create "Implementation step"     --type=task        # → local only
```
