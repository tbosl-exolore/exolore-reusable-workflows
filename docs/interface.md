# Reusable workflow interface

All workflow files are in `.github/workflows` and expose `workflow_call`. Callers supply a literal full-SHA workflow reference. These workflows run against the caller repository and its event commit; central workflow source is only used for the shared scripts.

## Verification

Workflow: `.github/workflows/verify.yml`

| Input | Type | Default | Contract |
| --- | --- | --- | --- |
| `working_directory` | string | `.` | Existing directory inside the caller checkout |
| `test_script` | string | `scripts/ci.sh` | Bash script path relative to `working_directory` |

The workflow grants its job `contents: read`, checks out `${{ github.repository }}@${{ github.sha }}` with persisted credentials disabled, validates that both paths stay inside the checkout, and runs `bash <test_script>` from the selected directory. The script and its dependencies belong to the caller. The hook must not depend on write access to `GITHUB_TOKEN` or production secrets.

## Container deployment

Workflow: `.github/workflows/deploy-container.yml`

| Input | Type | Default | Contract |
| --- | --- | --- | --- |
| `working_directory` | string | `.` | Caller directory containing the app and deployment contract |
| `build_context` | string | `.` | Docker build context relative to `working_directory` |
| `dockerfile` | string | `Dockerfile` | Dockerfile path relative to `working_directory` |
| `build_hook` | string | empty | Optional caller Bash script, run before Docker build |
| `compose_file` | string | `compose.yaml` | Compose file packaged as `compose.yaml` in the release |
| `project_config_file` | string | `deploy/project.env` | Non-secret project config packaged as `deploy/project.env` |
| `additional_release_paths` | string | empty | Optional newline-separated repository-relative files or directories copied into the release at their same paths |
| `environment_name` | string | `production` | Consumer Environment used for protection rules, variables, and secrets |

The caller must grant `contents: read` and `packages: write` to the reusable workflow call job. The shared job further limits its own token scope to those permissions. It checks out the caller repository and the central repository at `job.workflow_repository` and `job.workflow_sha`, then verifies that the checkout is the expected central repo and exact workflow commit before executing central scripts.

The image package is `ghcr.io/${{ github.repository }}`. Publication tags have the form `<source-sha>-<run-id>-<run-attempt>`. The OCI revision label remains the source SHA. The workflow captures all Buildx inspect output before parsing the first digest, validates `sha256:<64 lowercase hex>`, and deploys only the resulting `repository@sha256:...` reference.

### Consumer Environment configuration

Create the named Environment in each consumer repository and add:

| Kind | Name | Required | Meaning |
| --- | --- | --- | --- |
| Variable | `SERVER_HOST` | yes | SSH host covered by `SSH_KNOWN_HOSTS` |
| Variable | `SERVER_USER` | yes | Must equal `DEPLOY_USER` in the project config |
| Variable | `APP_PORT` | yes | Host loopback port, 1024–65535 |
| Variable | `RELEASE_RETENTION` | yes | Positive number of release directories to keep |
| Variable | `DEPLOY_ROOT` | no | Absolute safe override; otherwise `${DEPLOY_BASE}/${PROJECT_SLUG}` |
| Secret | `DEPLOY_SSH_KEY` | yes | ED25519 private key for the deployment account |
| Secret | `SSH_KNOWN_HOSTS` | yes | Pinned host key entry confirmed by an operator |

The called deployment job attaches `environment_name` itself. Environment protection and required reviewers therefore gate the entire build, push, and deployment job, matching the existing template. Environment secrets are resolved by that called job; callers should not use `secrets: inherit` or pass broad secret sets.

The caller's `deploy/project.env` (or configured project file) must define the project slug, deployment user, container port, health path, Compose project name, and server runtime env-file path. It is sourced as Bash by the workflow and again on the server; it is trusted caller configuration, must contain no secret values, and must not be user-generated input. Keep runtime values in the server's protected `.env` file.

`additional_release_paths` is an optional multiline string with one path per non-empty line. Paths are relative to the caller repository root, regardless of `working_directory`; blank lines are ignored. Use a YAML literal block for multiple entries:

```yaml
with:
  additional_release_paths: |
    deploy/backup-agenda.sh
    deploy/systemd
```

Files and directory contents keep their repository-relative paths in the release archive. Git-tracked executable bits are retained. The package step reads blobs from the checked-out caller commit at `SOURCE_SHA`, so untracked or locally modified worktree content is not included. The input defaults to empty and leaves the existing release layout unchanged.

The Compose contract is a service named `app` using `APP_IMAGE`, `APP_ENV_FILE`, `APP_PORT`, and `CONTAINER_PORT`. The image must be pulled by digest. The release archive contains Compose configuration, project configuration, image digest, source SHA, release ID, the central activation script, and only the explicitly selected additional paths. Additional paths cannot replace centrally managed release files. Runtime `.env` data, credential-named paths, Git metadata, symlinks, submodules, and non-regular files are rejected; SSH credentials are never packaged.

### Outputs

Successful deployment exposes `image_ref`, `image_digest`, and `source_sha`. They are outputs of the called workflow job, not environment variables in the caller. Failed publish, validation, health check, or rollback does not produce a successful deployment output.

## Optional GHCR migration baseline

Workflow: `.github/workflows/prepare-ghcr-baseline.yml`

| Input | Type | Required | Contract |
| --- | --- | --- | --- |
| `production_sha` | string | yes | Exact 40-character lower-case SHA currently deployed |
| `working_directory` | string | no | Caller path; default `.` |
| `build_context` | string | no | Relative Docker context; default `.` |
| `dockerfile` | string | no | Relative Dockerfile; default `Dockerfile` |

It checks out and verifies the caller commit, then creates a unique attempt tag, records the historical SHA as OCI revision, and publishes a digest-pinned baseline. This is an opt-in migration helper. A rebuild is not evidence that the bytes match the original production image.

## GitHub Actions context and access limits

- In a called workflow, `github.repository`, `github.sha`, `github.ref`, and `GITHUB_TOKEN` refer to the caller. `actions/checkout` checks out the caller unless a repository is explicitly supplied.
- Caller workflow-level `env` values do not propagate. Use the typed inputs above or variables on the caller Environment.
- A reusable-workflow call is a job; the caller cannot add steps to that job or set its `environment`. The shared deploy job therefore declares the consumer Environment.
- Workflow references cannot be built from expressions. Pin a full SHA in the caller YAML.
- `GITHUB_TOKEN` permissions can only be reduced in the called workflow, never elevated over the caller grant.
- Public reusable workflows work for eligible public and private callers, subject to consumer organization Actions policy. A public caller cannot use a private reusable workflow. Private cross-repository sharing is limited by GitHub's owner, organization, and enterprise access settings.
- These workflows use GitHub.com [`job.workflow_repository` and `job.workflow_sha`](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts) to fetch the central scripts at the exact called commit. GitHub Enterprise Server versions that do not expose those context properties are not supported by this implementation. The pinned actionlint release does not yet model those documented fields, so validation suppresses only its two unknown-property diagnostics; all other actionlint checks remain enabled.
