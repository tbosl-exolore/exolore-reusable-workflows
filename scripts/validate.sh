#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${PYTHON:-python3}"
mapfile -d '' shell_files < <(find "$root" -path "$root/.git" -prune -o -type f -name '*.sh' -print0)
for file in "${shell_files[@]}"; do bash -n "$file"; done
"$python_bin" "$root/scripts/test-interface.py"
"$python_bin" "$root/scripts/test-public-content.py"
bash "$root/scripts/test-digest-resolution.sh"
bash "$root/scripts/test-deploy-container.sh"
bash "$root/scripts/test-baseline.sh"
bash "$root/scripts/test-activation.sh"

if command -v actionlint >/dev/null 2>&1; then
  mapfile -d '' workflow_files < <(find "$root" -type f \( -name '*.yml' -o -name '*.yaml' \) -path '*/.github/workflows/*' -print0)
  # actionlint v1.7.12 does not yet model GitHub.com's documented
  # job.workflow_repository and job.workflow_sha properties. Ignore only
  # those two unknown-property reports; keep all other workflow checks active.
  actionlint -color \
    -ignore 'property .*workflow_repository.* is not defined in object type' \
    -ignore 'property .*workflow_sha.* is not defined in object type' \
    "${workflow_files[@]}"
else
  echo "actionlint is not installed; workflow schema checks are covered by the GitHub Actions validation job." >&2
fi

echo "Reusable workflow validation passed."
