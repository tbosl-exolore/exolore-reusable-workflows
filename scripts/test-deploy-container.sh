#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/workspace/caller/services/api/scripts" "$tmp/workspace/caller/services/api" "$tmp/runner"
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
case "$1:${2:-}" in
  login:*) cat >/dev/null ;;
  build:*) ;;
  push:*) ;;
  buildx:imagetools)
    printf '%s\n' 'Name: ghcr.io/exampleorg/monorepo:attempt' \
      'Digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    ;;
  logout:*) ;;
  *) echo "Unexpected fake Docker command: $*" >&2; exit 90 ;;
esac
DOCKER
chmod +x "$tmp/bin/docker"
cat > "$tmp/workspace/caller/services/api/Dockerfile" <<'DOCKERFILE'
FROM scratch
DOCKERFILE
cat > "$tmp/workspace/caller/services/api/scripts/prepare.sh" <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -z "${GHCR_TOKEN:-}" ]] || { echo "GHCR token leaked to build hook" >&2; exit 1; }
echo prepared > build-hook-ran.txt
HOOK
cat > "$tmp/workspace/caller/services/api/deploy.env" <<'CONFIG'
PROJECT_SLUG=fixture-api
DEPLOY_BASE=/opt
DEPLOY_USER=deploy
CONTAINER_PORT=8080
HEALTH_PATH=/healthz
COMPOSE_PROJECT_NAME=fixture-api
APP_ENV_FILE=/opt/fixture-api/shared/.env
CONFIG

export PATH="$tmp/bin:$PATH"
export FAKE_DOCKER_LOG="$tmp/docker.log"
export GITHUB_WORKSPACE="$tmp/workspace"
export RUNNER_TEMP="$tmp/runner"
export GITHUB_OUTPUT="$tmp/output"
export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
export GITHUB_RUN_ID=654321
export GITHUB_RUN_ATTEMPT=2
export GITHUB_REPOSITORY=ExampleOrg/Monorepo
export GITHUB_ACTOR=fixture
export GHCR_TOKEN=test-token-not-a-real-secret
export SERVER_HOST=example.invalid
export SERVER_USER=deploy
export DEPLOY_ROOT_OVERRIDE=
export APP_PORT=18080
export RELEASE_RETENTION=5
export WORKING_DIRECTORY=services/api
export BUILD_CONTEXT=.
export DOCKERFILE=Dockerfile
export BUILD_HOOK=scripts/prepare.sh
export PROJECT_CONFIG_FILE=deploy.env

bash "$root/scripts/deploy-container.sh"

grep -q '^image_ref=ghcr.io/exampleorg/monorepo@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef$' "$GITHUB_OUTPUT"
grep -q "^release_id=$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT$" "$GITHUB_OUTPUT"
grep -q '^deploy_root=/opt/fixture-api$' "$GITHUB_OUTPUT"
[[ "$(cat "$tmp/workspace/caller/services/api/build-hook-ran.txt")" == prepared ]]
grep -q "^build .*--file $tmp/workspace/caller/services/api/Dockerfile .*--tag ghcr.io/exampleorg/monorepo:$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" "$FAKE_DOCKER_LOG"
grep -q "^push ghcr.io/exampleorg/monorepo:$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" "$FAKE_DOCKER_LOG"
grep -q '^logout ghcr.io' "$FAKE_DOCKER_LOG"

echo "Caller checkout, monorepo paths, build hook, and unique publication checks passed."
