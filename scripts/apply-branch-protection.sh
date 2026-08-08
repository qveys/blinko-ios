#!/usr/bin/env bash
#
# Apply the branch protection rule for `main` documented in
# docs/branch-protection.md, then verify it took effect.
#
# Requires admin on the repository. `maintain` is not enough for this endpoint.
#
#   ./scripts/apply-branch-protection.sh
#   REPO=owner/name BRANCH=develop ./scripts/apply-branch-protection.sh
#
set -euo pipefail

REPO="${REPO:-qveys/blinko-ios}"
BRANCH="${BRANCH:-main}"

command -v gh >/dev/null || { echo "error: gh CLI not found — https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated; run 'gh auth login'" >&2; exit 1; }

# A GitHub App token has no user identity and 403s on /user, so fall back quietly.
ACTOR="$(gh api user --jq .login 2>/dev/null)" || ACTOR=""
echo "Applying branch protection to ${REPO}@${BRANCH} as ${ACTOR:-<app or unknown identity>}"

# Require the CI check only once its workflow actually exists on ${BRANCH}.
# Requiring a check that never reports would wedge every PR in "Expected —
# waiting for status", so this is gated on the workflow being merged rather
# than hardcoded. CHECK_NAME is the job's `name:`, not its YAML key.
CHECK_NAME="${CHECK_NAME:-Build and Test}"
WORKFLOW_PATH="${WORKFLOW_PATH:-.github/workflows/ios-ci.yml}"

if gh api "repos/${REPO}/contents/${WORKFLOW_PATH}?ref=${BRANCH}" >/dev/null 2>&1; then
  required_checks="{\"strict\": true, \"checks\": [{\"context\": \"${CHECK_NAME}\"}]}"
  echo "CI workflow found on ${BRANCH} — requiring status check: ${CHECK_NAME}"
else
  required_checks="null"
  echo "No ${WORKFLOW_PATH} on ${BRANCH} yet — applying without required status checks."
  echo "Re-run this script after the CI pipeline merges to add the gate."
fi

if ! gh api -X PUT "repos/${REPO}/branches/${BRANCH}/protection" --input - >/dev/null <<JSON
{
  "required_status_checks": ${required_checks},
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
then
  cat >&2 <<EOF

Failed to apply protection to ${REPO}@${BRANCH}.

A 403 "Resource not accessible by integration" means the authenticated identity
lacks admin. If you are running as the Paperclip bot, grant the GitHub App
Administration: Read & write — see docs/branch-protection.md.
EOF
  exit 1
fi

echo "Applied. Verifying..."
gh api "repos/${REPO}/branches/${BRANCH}/protection" --jq '{
  reviews: .required_pull_request_reviews.required_approving_review_count,
  dismiss_stale: .required_pull_request_reviews.dismiss_stale_reviews,
  admins: .enforce_admins.enabled,
  force_push: .allow_force_pushes.enabled,
  deletions: .allow_deletions.enabled,
  conversations: .required_conversation_resolution.enabled
}'

cat <<EOF

Expected: reviews=1, dismiss_stale=true, admins=true,
          force_push=false, deletions=false, conversations=true

Behavioural check — from an up-to-date clone, this push should now be rejected
with 'GH006: Protected branch update failed':

  git checkout ${BRANCH} && git commit --allow-empty -m 'test: protection' && git push origin ${BRANCH}
EOF
