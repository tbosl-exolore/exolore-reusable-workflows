# Release and upgrade guide

## Versioning policy

Release reusable workflow changes as semantic versions (`v1.0.0`, `v1.1.0`, `v2.0.0`) with a changelog entry. Document inputs, secrets/variables, outputs, permission changes, deployment contract changes, and migration notes for each release.

Consumers must pin calls to the complete 40-character commit SHA. Annotated release tags are for people and release notes; a mutable major tag such as `v1` is not a reproducible consumer reference. Protect release tags and limit who can create or move them. Pin actions used by the reusable workflows to full SHAs as well.

All central scripts executed by a workflow are checked out from `job.workflow_repository@job.workflow_sha`, and the job asserts that the checkout is the expected public repository at that exact commit. Do not replace this with a `main` checkout or a tag lookup.

## First versioned release checklist

The current working tree is an implementation candidate, not a release. After review and approval:

1. Run `bash scripts/validate.sh` on a Bash-capable host with Python 3 and `actionlint` available.
2. Inspect the complete diff and public-content scan; confirm the public repository contains no secrets, private hostnames/IPs, customer configuration, or internal-only notes.
3. Commit the approved implementation to the central repository's default branch.
4. Push that commit to GitHub using the repository's normal approved process.
5. Record the full commit SHA from the pushed commit and create an annotated semantic version tag at that commit, for example `v1.0.0`.
6. Protect the tag/release from unauthorized movement and publish release notes describing the interface and compatibility contract.
7. Reference the full 40-character commit SHA in a sandbox caller—not `main` or the release tag—and verify the repository visibility, Environment protection, outputs, GHCR package permissions, SSH host verification, health checks, and rollback.
8. Only after the sandbox call passes, open a separate reviewed consumer migration PR. Do not migrate consumers as part of this repository release.

Example operator commands after approval (review the staged list before committing):

```bash
git add .github/workflows README.md docs scripts test
git diff --cached --check
git commit -m "feat: add Exolore reusable workflows"
git push origin main
git rev-parse HEAD
git tag -a v1.0.0 -m "Exolore reusable workflows v1.0.0"
git push origin v1.0.0
```

Use the full SHA printed by `git rev-parse HEAD` in sandbox callers. Create/publish the GitHub Release after the tag is pushed and the SHA-pinned sandbox call passes. Apply the repository's branch and tag protections before consumer rollout.

This agent does not commit, push, or create a release. The first release remains a human-approved repository operation.

## Upgrade process

For each central release, provide a consumer PR that changes the full-SHA reference and records the matching semantic version beside it. Run consumer validation and sandbox deployment before merge. Keep the previous SHA in the PR diff/history so reverting the caller reference is straightforward. Upgrade consumers deliberately; central `main` does not change the behavior of pinned callers.

## Compatibility

- Patch releases should fix bugs without changing input meaning or deployment semantics.
- Minor releases may add optional inputs/outputs and new compatible features.
- Major releases may remove/rename fields, change environment contracts, or change release behavior; include a migration guide and a tested compatibility path.
- Do not change the Docker Compose `app` service contract, server release metadata, health-check/rollback sequence, or environment secret names without documenting the migration and testing it against old releases.
