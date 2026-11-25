#!/usr/bin/env python3
"""Guard workflow interfaces and core deployment invariants without a live server."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


workflow_dir = ROOT / ".github" / "workflows"
for filename in ("verify.yml", "deploy-container.yml", "prepare-ghcr-baseline.yml"):
    content = (workflow_dir / filename).read_text(encoding="utf-8")
    require(re.search(r"(?m)^  workflow_call:\s*$", content) is not None, f"{filename} must be reusable")

deploy = (workflow_dir / "deploy-container.yml").read_text(encoding="utf-8")
baseline = (workflow_dir / "prepare-ghcr-baseline.yml").read_text(encoding="utf-8")
for content, name in ((deploy, "deploy-container.yml"), (baseline, "prepare-ghcr-baseline.yml")):
    require("repository: ${{ job.workflow_repository }}" in content, f"{name} must check out the called workflow repository")
    require("ref: ${{ job.workflow_sha }}" in content, f"{name} must check out the exact called workflow revision")
    require("assert-workflow-revision.sh" in content, f"{name} must verify its central script revision")
    require("packages: write" in content, f"{name} must request package write for GHCR")

deploy_script = (ROOT / "scripts" / "deploy-container.sh").read_text(encoding="utf-8")
require("$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" in deploy_script, "image tags must distinguish source SHA, run, and attempt")
require("image_repository@$IMAGE_DIGEST" in deploy_script, "deploy image reference must be digest-pinned")
ghcr = (ROOT / "scripts" / "lib" / "ghcr.sh").read_text(encoding="utf-8")
require('docker buildx imagetools inspect "$tag"' in ghcr, "digest resolution must inspect the published tag")
require("awk '$1 == \"Digest:\" && !found {print $2; found=1}' <<< \"$inspect_output\"" in ghcr, "inspect output must be consumed before parsing")
require("sha256:[0-9a-f]{64}" in ghcr, "resolved digest must be strictly validated")

activation = (ROOT / "scripts" / "activate-release.sh").read_text(encoding="utf-8")
for marker, description in (
    ("docker compose", "Compose activation"),
    ("docker image inspect", "exact image verification"),
    ("org.opencontainers.image.revision", "source revision verification"),
    ("curl --fail --silent --show-error", "health verification"),
    ("rollback()", "rollback support"),
    ("release_id", "release identity support"),
    ("deploy-release-id.txt", "run-specific release identity marker"),
):
    # RELEASE_ID is intentionally validated by its lower-case shell variable.
    require(marker in activation, f"activation must preserve {description}")
require("StrictHostKeyChecking=yes" in (ROOT / "scripts" / "activate-remote.sh").read_text(encoding="utf-8"), "SSH host checking must stay enabled")
require("docker image prune" not in activation, "activation must not prune images server-wide")
require("--connect-timeout 2 --max-time 5" in activation, "health requests must have explicit timeouts")

sha_pin = re.compile(r"@[0-9a-f]{40}(?:\s|$)")
fixtures = ROOT / "test" / "fixtures" / "consumers"
fixture_workflows = list(fixtures.glob("*/.github/workflows/*.yml")) + list(fixtures.glob("*/**/.github/workflows/*.yml"))
require(fixture_workflows, "representative consumer workflows must exist")
for path in set(fixture_workflows):
    content = path.read_text(encoding="utf-8")
    require("uses: tbosl-exolore/exolore-reusable-workflows/.github/workflows/" in content, f"{path.relative_to(ROOT)} must call central workflows")
    require("@main" not in content, f"{path.relative_to(ROOT)} must not use a mutable main reference")
    require(sha_pin.search(content) is not None, f"{path.relative_to(ROOT)} must demonstrate a full SHA ref")
    require("docker push" not in content, f"{path.relative_to(ROOT)} must not duplicate shared implementation")

print("Workflow interface and deployment invariant checks passed.")
