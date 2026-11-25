#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
case "$1:${2:-}" in
  login:*) cat >/dev/null; echo 'Login Succeeded' ;;
  build:*) [[ "${FAKE_DOCKER_MODE:-}" != build-fail ]] || exit 19 ;;
  push:*) [[ "${FAKE_DOCKER_MODE:-}" != push-fail ]] || exit 31 ;;
  buildx:imagetools)
    [[ "${FAKE_DOCKER_MODE:-}" != inspect-fail ]] || { echo 'simulated registry inspection error' >&2; exit 29; }
    if [[ "${FAKE_DOCKER_MODE:-}" == invalid-digest ]]; then
      echo 'Digest: not-a-sha'
    else
      echo 'Name: ghcr.io/example/app:fixture'
      echo 'Digest: sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
      for i in {1..3000}; do echo "platform detail $i"; done
    fi
    ;;
  logout:*) [[ "${FAKE_DOCKER_MODE:-}" != logout-fail ]] || exit 41 ;;
  *) echo "Unexpected fake Docker command: $*" >&2; exit 90 ;;
esac
DOCKER
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH"
export FAKE_DOCKER_LOG="$tmp/docker.log"
export GHCR_TOKEN='test-token-not-a-real-secret'
export GITHUB_ACTOR=fixture
source "$root/scripts/lib/ghcr.sh"

publish_image ghcr.io/example/app:fixture 0123456789abcdef0123456789abcdef01234567 Dockerfile .
[[ "$IMAGE_DIGEST" == sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef ]]
[[ "$(wc -l < "$FAKE_DOCKER_LOG")" -eq 5 ]]
[[ "$(sed -n '3p' "$FAKE_DOCKER_LOG")" == push\ * ]]
[[ "$(sed -n '4p' "$FAKE_DOCKER_LOG")" == buildx\ imagetools\ inspect\ * ]]
[[ "$(sed -n '5p' "$FAKE_DOCKER_LOG")" == logout\ ghcr.io ]]

export FAKE_DOCKER_MODE=inspect-fail
if resolve_image_digest ghcr.io/example/app:fixture; then
  echo "Expected inspect failure." >&2; exit 1
else
  [[ $? -eq 29 ]]
fi

export FAKE_DOCKER_MODE=invalid-digest
if resolve_image_digest ghcr.io/example/app:fixture; then
  echo "Expected invalid digest rejection." >&2; exit 1
else
  [[ $? -eq 1 ]]
fi

export FAKE_DOCKER_MODE=push-fail
export GHCR_TOKEN=test-token-not-a-real-secret
if publish_image ghcr.io/example/app:fixture 0123456789abcdef0123456789abcdef01234567 Dockerfile .; then
  echo "Expected push failure." >&2; exit 1
else
  [[ $? -eq 31 ]]
fi

export FAKE_DOCKER_MODE=logout-fail
export GHCR_TOKEN=test-token-not-a-real-secret
if publish_image ghcr.io/example/app:fixture 0123456789abcdef0123456789abcdef01234567 Dockerfile .; then
  echo "Expected logout failure." >&2; exit 1
else
  [[ $? -eq 41 ]]
fi

echo "Digest resolution regression checks passed."
