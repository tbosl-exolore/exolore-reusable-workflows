# Consumer migration guide

Migrate one repository at a time. The central workflow is designed for repositories following the Dockerfile, Compose service `app`, GHCR, and SSH release contract. A consumer with a different runtime or deployment model needs an explicit interface extension before migration.

## 1. Inventory the current consumer

Record its current workflow ref, triggers, branch rules, test/build commands, working directory, Dockerfile and context, GHCR package permissions, production Environment reviewers, variables and secrets, SSH host key, deployment root, Compose configuration, health endpoint, release retention, and rollback behavior. Compare the server release directories and active `current` target with the project's checked-in deployment config.

Do not assume template ancestry. Existing projects may have changed deployment scripts or release formats independently.

## 2. Configure the consumer Environment

Create the Environment named by the caller input (normally `production`). Add the variables and secrets listed in [the workflow interface](interface.md). Preserve the existing required reviewers and branch restrictions. Independently verify the server host fingerprint before saving `SSH_KNOWN_HOSTS`.

Confirm the consumer repository is allowed to use public reusable workflows and that its GHCR package grants write access to Actions for the caller repository. The reusable workflow's token is the consumer's `GITHUB_TOKEN`, not a token from this repository. For private server-side images, retain a separate read-only pull credential on the server.

## 3. Replace duplicated workflow logic with callers

Use the fixture at `test/fixtures/consumers/basic` as the starting point. For a monorepo, use `test/fixtures/consumers/monorepo` and set `working_directory`, Docker context, and script paths explicitly. Keep consumer event triggers local. Keep application CI/build hooks and project config in the consumer. Remove copied shared build/push/SSH/activation code after the caller is reviewed.

If the release needs consumer-owned runtime support files, pass their repository-root-relative paths using `additional_release_paths` (one path per line), for example:

```yaml
with:
  additional_release_paths: |
    deploy/backup-agenda.sh
    deploy/systemd
```

The packager copies those files into the release before SSH transfer and activation, preserving their relative structure and tracked executable bit. Keep credentials and runtime environment files out of this list. Directory selections are recursive; symlinks, special Git entries, paths overlapping managed release files, and sensitive path names are rejected. Omit the input when no additional release files are required.

The verification call should run for pull requests with only `contents: read`. Gate the deploy call to the same branches and manual dispatch behavior currently allowed. Make it depend on verification. Give only the deploy call `packages: write`. Explicitly pass `DEPLOY_SSH_KEY` and `SSH_KNOWN_HOSTS` by name under the deploy job's `secrets:` mapping, referencing the same-named Environment secrets; do not use `secrets: inherit` or move these values to repository scope. The called deployment job keeps its `environment_name` binding, so Environment reviewers continue to gate the whole build and deployment. Keep the consumer workflow's top-level permissions empty.

Pin both called workflow jobs to the same full SHA for a release. Do not use `main`, a branch, or an expression as the ref.

## 4. Validate away from production

Before the consumer's first production run:

1. Run its test hook and template validation.
2. Call the candidate central SHA from a scratch or sandbox consumer repository.
3. Use a dedicated non-production Environment, disposable target server, and test package.
4. Confirm reviewer gating, secret resolution, GHCR permissions, image digest output, host-key verification, health-check failure, rollback, and release retention.
5. Compare the proposed release contents and server paths to the existing contract; retain a recovery path to the previous release and workflow SHA.

The baseline workflow should be used only when the server already uses the release layout that its corresponding migration helper expects. Verify the active release SHA before dispatching it.

## 5. Consumer-specific caveats

- A commit SHA is the OCI revision label and release source marker. Each workflow attempt creates a distinct publication tag and release ID so reruns cannot replace the image behind an older release path.
- Older release directories without `deploy-release-id.txt` remain readable when their directory name equals their `deploy-sha.txt`; this preserves compatibility with existing SHA-named releases.
- Runtime `.env` files are not uploaded, including through `additional_release_paths`. The Compose contract must continue reading them from the persistent server path.
- Additional release files are packaged in the same immutable archive as the Compose contract and central activator. They are available in the activated release and any retained rollback release, avoiding post-activation edits to release directories.
- If the first deployment fails before a healthy release exists, the workflow fails, leaves `current` absent, and keeps the failed release directory for diagnostics. There is no rollback target; an operator must inspect the service and correct the cause before retrying. On later failed deployments, the previous verified `current` target is restarted and retained.
- Release retention removes old release directories only. Deployment does not run a server-wide Docker image prune; image cleanup is an independent operator policy.
- The activator supplies `APP_IMAGE`, `APP_ENV_FILE`, `APP_PORT`, `CONTAINER_PORT`, and `COMPOSE_PROJECT_NAME` to every Compose command, including `ps` and failure-log collection. Health requests use a 2-second connection timeout and a 5-second request deadline, with 20 bounded attempts and 3-second pauses (157 seconds maximum).
- Do not migrate a consumer with custom activation semantics by merely changing its caller workflow. Port its semantics to a reviewed central change or preserve its current workflow until the central contract supports them.
