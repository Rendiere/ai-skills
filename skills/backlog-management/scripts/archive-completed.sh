#!/usr/bin/env bash
# Archive all Done + Canceled Linear issues in a team.
# Soft-delete — reversible via Linear UI.
#
# Requires:
#   LINEAR_API_KEY - Linear personal API key
#   LINEAR_TEAM_ID - UUID of the team

set -euo pipefail
: "${LINEAR_API_KEY:?set LINEAR_API_KEY}"
: "${LINEAR_TEAM_ID:?set LINEAR_TEAM_ID}"

GQL='query($teamId: ID!, $after: String) {
  issues(first: 100, after: $after, filter: {
    team: {id: {eq: $teamId}},
    state: {type: {in: [completed, canceled]}}
  }) { nodes { id identifier } pageInfo { hasNextPage endCursor } }
}'

after_arg='null'
archived=0

while :; do
  payload=$(jq -cn \
    --arg q "$GQL" \
    --arg t "$LINEAR_TEAM_ID" \
    --argjson a "$after_arg" \
    '{query:$q, variables:{teamId:$t, after:$a}}')

  resp=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  if echo "$resp" | jq -e '.errors' >/dev/null 2>&1; then
    echo "GraphQL error:" >&2
    echo "$resp" | jq '.errors' >&2
    exit 1
  fi

  mapfile -t ids < <(echo "$resp" | jq -r '.data.issues.nodes[].id')
  mapfile -t keys < <(echo "$resp" | jq -r '.data.issues.nodes[].identifier')

  for i in "${!ids[@]}"; do
    id="${ids[$i]}"
    key="${keys[$i]}"
    mut=$(curl -s -X POST https://api.linear.app/graphql \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"mutation{ issueArchive(id: \\\"$id\\\") { success } }\"}")
    if echo "$mut" | jq -e '.data.issueArchive.success == true' >/dev/null; then
      archived=$((archived + 1))
      printf '  archived %s\n' "$key"
    else
      echo "failed to archive $key: $mut" >&2
    fi
  done

  has_next=$(echo "$resp" | jq -r '.data.issues.pageInfo.hasNextPage')
  [ "$has_next" = "true" ] || break
  cursor=$(echo "$resp" | jq -r '.data.issues.pageInfo.endCursor')
  after_arg=$(jq -cn --arg c "$cursor" '$c')
done

echo "Done. Archived $archived issues."
