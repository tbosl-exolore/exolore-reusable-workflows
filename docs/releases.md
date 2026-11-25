# Release and upgrade guide

## Versioning policy

Release reusable workflow changes using semantic versioning:

- Patch releases (`v1.0.1`): compatible bug fixes.
- Minor releases (`v1.1.0`): compatible features and optional interface extensions.
- Major releases (`v2.0.0`): breaking changes requiring explicit consumer migration.

Immutable semantic release tags identify individual releases. Moving major-version tags such as `v1` reference the latest approved compatible release.

Consumers use `@v1` by default. A full 40-character commit SHA remains available as an immutable alternative.

Moving major-version tags must be lightweight Git tags. Annotated tags can cause a mismatch between `job.workflow_sha` and the checked-out commit.

## Release checklist

1. Review the complete implementation diff.
2. Run `bash scripts/validate.sh`.
3. Verify that the public repository contains no secrets or customer-specific configuration.
4. Commit and push the approved implementation.
5. Validate the candidate using its exact commit SHA in an appropriate test consumer.
6. Create an annotated semantic version tag and publish release notes.
7. Move the lightweight major-version tag to the approved release commit.
8. Monitor subsequent consumer workflow runs.

Use a risk-appropriate test environment. Validate deployment and rollback behavior whenever relevant to the changes.

## Publishing a compatible release

Example for a future release `v1.0.1`, after validation and approval:

```bash
git tag -a v1.0.1 -m "Exolore reusable workflows v1.0.1"
git push origin refs/tags/v1.0.1

gh release create v1.0.1 --verify-tag --generate-notes
```

Update the moving major-version tag:

```bash
old="$(git ls-remote --exit-code origin refs/tags/v1 | cut -f1)"

git tag -f --no-sign v1 'v1.0.1^{}'

git push --force-with-lease="refs/tags/v1:$old" \
  origin refs/tags/v1

git ls-remote origin refs/tags/v1
```

The remote major-version tag must resolve directly to the intended commit.

Never move an existing semantic release tag. Only authorized maintainers may update moving major-version tags.

## Consumer upgrades

Consumers referencing `@v1` automatically receive compatible updates on subsequent new workflow runs. Moving the tag does not itself trigger deployments in consumer repositories.

Avoid moving major-version tags while consumer workflows are active.

Consumers pinned to a full commit SHA require an explicit reference update. Breaking changes require migration to a new major-version tag.

To recover from a defective central release, restore the major-version tag to the last known good release commit using the same protected update procedure.

## Security and reproducibility

All central scripts executed by a workflow are checked out from `job.workflow_repository@job.workflow_sha`. The workflow verifies the exact checked-out revision before executing central scripts.

Do not replace this verification with a branch checkout or an independent lookup of the moving tag.

External GitHub Actions remain pinned to full commit SHAs. Production images remain pinned to validated immutable digests.

A moving major-version tag trades immutable consumer version binding for centralized upgrade management. Use full commit-SHA references where strict reproducibility is required.

## Compatibility

Do not change required inputs, environment secret names, Docker Compose contracts, release metadata, or deployment and rollback semantics incompatibly within an existing major version.

Document relevant interface changes, deployment behavior changes, and migration requirements in each release.