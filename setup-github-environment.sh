#!/usr/bin/env bash
# Configures the GitHub side of the infrastructure pipeline:
# the "production" environment (required reviewer, main branch only) and the alert e-mail variable.
# Usage: ./setup-github-environment.sh <alert-email>
set -euo pipefail
export GH_PAGER=cat

REPO="ehc-io/gcp-challenge-iac"
ALERT_EMAIL="${1:?usage: $0 <alert-email>}"
[[ "$ALERT_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { echo "not an e-mail address: $ALERT_EMAIL" >&2; exit 1; }

reviewer_id=$(gh api user --jq .id)

# Environment with the current user as required reviewer and a custom branch policy
gh api -X PUT "repos/$REPO/environments/production" --input - >/dev/null <<EOF
{"reviewers":[{"type":"User","id":$reviewer_id}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
echo "environment: production created/updated (reviewer id $reviewer_id)"

# Only main may deploy to production (skip if the policy already exists)
if gh api "repos/$REPO/environments/production/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main; then
  echo "branch policy: main already present"
else
  gh api -X POST "repos/$REPO/environments/production/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  echo "branch policy: main added"
fi

gh variable set ALERT_EMAIL --repo "$REPO" --body "$ALERT_EMAIL"

echo "--- verification"
gh api "repos/$REPO/environments/production" --jq '.protection_rules[].type'   # expect required_reviewers, branch_policy
gh api "repos/$REPO/environments/production/deployment-branch-policies" --jq '.branch_policies[] | .name + " (" + .type + ")"'
gh variable list --repo "$REPO"
