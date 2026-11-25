# Exolore reusable workflows

Versioned GitHub Actions workflows for caller-owned application verification and Docker Compose deployments. The shared workflows run in the consumer repository's context: its source, GHCR package, production Environment, variables, secrets, and `GITHUB_TOKEN` remain owned by that consumer.

## Workflows

| Workflow | Purpose | Required caller permission |
| --- | --- | --- |
| `.github/workflows/verify.yml` | Check out the caller commit and run its test hook | `contents: read` |
| `.github/workflows/deploy-container.yml` | Build and push a unique GHCR attempt tag, resolve its digest, and deploy the digest through verified SSH | `contents: read`, `packages: write` |
| `.github/workflows/prepare-ghcr-baseline.yml` | Optional rebuild of an exact historical caller commit for legacy GHCR migration | `contents: read`, `packages: write` |

Read [the workflow interface](docs/interface.md), [migration guide](docs/migration.md), and [release and upgrade guide](docs/releases.md) before adopting a workflow.

## Security and support

This repository contains no consumer secrets or production host details. Secrets and production variables are configured in the caller repository's protected Environment. The deployed image is always referenced by a validated digest. Central deployment scripts are checked out using the exact repository and commit SHA of the called reusable workflow.

Reusable workflow inputs are designed for GitHub Actions on GitHub.com. The deployment uses Ubuntu hosted runners, Docker CLI/Buildx, Docker Compose on the target Linux server, and a caller-owned Dockerfile/Compose contract.

## Validation

Run the regression suite on a Bash-capable host with Python 3 and `actionlint` installed:

```bash
bash scripts/validate.sh
```

The GitHub Actions validation workflow downloads a fixed actionlint release and verifies its published checksum before checking all production and fixture workflows.
