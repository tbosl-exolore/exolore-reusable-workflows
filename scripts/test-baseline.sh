#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/workspace/caller" "$tmp/runner"
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
case "$1:${2:-}" in
  login:*) cat >/dev/null ;;
  build:*) ;;
  push:*) ;;
  buildx:imagetools)
    printf '%s\n' 'Digest: sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
    ;;
  logout:*) ;;
  *) echo "Unexpected fake Docker command: $*" >&2; exit 90 ;;
esac
DOCKER
cat > "$tmp/bin/git" <<'GIT'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == -C && "$2" == "$GITHUB_WORKSPACE/caller" && "$3" == rev-parse && "$4" == HEAD ]]; then
  printf '%s\n' "$FAKE_CHECKOUT_SHA"
else
  echo "Unexpected fake git command: $*" >&2
  exit 90
fi
GIT
chmod +x "$tmp/bin/docker" "$tmp/bin/git"
touch "$tmp/workspace/caller/Dockerfile"

export PATH="$tmp/bin:$PATH"
export GITHUB_WORKSPACE="$tmp/workspace"
export RUNNER_TEMP="$tmp/runner"
export GITHUB_OUTPUT="$tmp/output"
export GITHUB_STEP_SUMMARY="$tmp/summary"
export FAKE_DOCKER_LOG="$tmp/docker.log"
export GHCR_TOKEN=test-token-not-a-real-secret
export GITHUB_ACTOR=fixture
export GITHUB_REPOSITORY=ExampleOrg/Baseline
export GITHUB_RUN_ID=789
export GITHUB_RUN_ATTEMPT=1
export PRODUCTION_SHA=abcdef0123456789abcdef0123456789abcdef01
export FAKE_CHECKOUT_SHA="$PRODUCTION_SHA"
export WORKING_DIRECTORY=.
export BUILD_CONTEXT=.
export DOCKERFILE=Dockerfile

bash "$root/scripts/prepare-ghcr-baseline.sh"
grep -q '^image_ref=ghcr.io/exampleorg/baseline@sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789$' "$GITHUB_OUTPUT"
grep -q "^push ghcr.io/exampleorg/baseline:$PRODUCTION_SHA-789-1$" "$FAKE_DOCKER_LOG"
grep -q 'Built from production commit' "$GITHUB_STEP_SUMMARY"

: > "$GITHUB_OUTPUT"
export FAKE_CHECKOUT_SHA=1111111111111111111111111111111111111111
if bash "$root/scripts/prepare-ghcr-baseline.sh"; then
  echo "Expected baseline checkout mismatch rejection." >&2; exit 1
else
  [[ $? -eq 1 ]]
fi
[[ ! -s "$GITHUB_OUTPUT" ]]

echo "Baseline SHA verification and digest publication checks passed."
