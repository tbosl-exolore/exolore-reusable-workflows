#!/usr/bin/env bash
set -Eeuo pipefail

expected_repository="tbosl-exolore/exolore-reusable-workflows"
[[ "$JOB_WORKFLOW_REPOSITORY" == "$expected_repository" ]] || {
  echo "::error::Unexpected reusable workflow repository: $JOB_WORKFLOW_REPOSITORY"
  exit 1
}
[[ "$JOB_WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  echo "::error::Reusable workflow SHA is not a full commit SHA."
  exit 1
}
actual_sha="$(git -C "$GITHUB_WORKSPACE/central-workflow" rev-parse HEAD)"
[[ "$actual_sha" == "$JOB_WORKFLOW_SHA" ]] || {
  echo "::error::Central scripts do not match the called workflow revision."
  exit 1
}
echo "Central deployment scripts match $expected_repository@$actual_sha"
