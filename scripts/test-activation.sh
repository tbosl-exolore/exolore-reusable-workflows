#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Git for Windows needs this mode for real native symlinks. On Linux this is
# harmless; tests below use real links and mv replacement wherever supported.
export MSYS=winsymlinks:nativestrict

cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
if [[ "$1" == compose ]]; then
  for name in APP_IMAGE APP_ENV_FILE APP_PORT CONTAINER_PORT COMPOSE_PROJECT_NAME; do
    [[ -n "${!name:-}" ]] || { echo "Missing Compose interpolation variable: $name" >&2; exit 64; }
  done
  printf 'compose env APP_IMAGE=%s APP_ENV_FILE=%s APP_PORT=%s CONTAINER_PORT=%s COMPOSE_PROJECT_NAME=%s\n' \
    "$APP_IMAGE" "$APP_ENV_FILE" "$APP_PORT" "$CONTAINER_PORT" "$COMPOSE_PROJECT_NAME" >> "$FAKE_DOCKER_LOG"
  shift
  case " $* " in
    *" pull app "*) exit 0 ;;
    *" up "*)
      image="$(sed -n 's/^APP_IMAGE=//p' deploy/image.env)"
      sha="$(cat deploy-sha.txt)"
      printf '%s\n%s\n' "$image" "$sha" > "$TEST_STATE"
      exit 0
      ;;
    *" ps "*) echo abcdef123456 ;;
    *" logs "*) echo 'simulated app logs' >&2 ;;
    *) echo "Unexpected fake compose command: $*" >&2; exit 90 ;;
  esac
elif [[ "$1" == inspect ]]; then
  format="$3"
  mapfile -t state < "$TEST_STATE"
  if [[ "$format" == '{{.Image}}' ]]; then
    printf 'img-%s\n' "${state[0]##*:}"
  else
    printf '%s\n' "${state[1]}"
  fi
elif [[ "$1" == image && "$2" == inspect ]]; then
  image_ref="${@: -1}"
  printf 'img-%s\n' "${image_ref##*:}"
else
  echo "Unexpected fake Docker command: $*" >&2; exit 90
fi
DOCKER
cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ " $* " == *" --connect-timeout 2 "* ]] || { echo 'Missing curl connect timeout' >&2; exit 65; }
[[ " $* " == *" --max-time 5 "* ]] || { echo 'Missing curl request timeout' >&2; exit 66; }
mapfile -t state < "$TEST_STATE"
if [[ -n "${FAIL_DIGEST:-}" && "${state[0]}" == *"$FAIL_DIGEST"* ]]; then
  exit 22
fi
CURL
cat > "$tmp/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
chmod +x "$tmp/bin/docker" "$tmp/bin/curl" "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH"
export PROJECT_SLUG=fixture-app
export TEST_STATE="$tmp/running-image"
export FAKE_DOCKER_LOG="$tmp/docker.log"

fixture_root="$root/test/fixtures/consumers"
basic_compose="$fixture_root/basic/compose.yaml"
monorepo_compose="$fixture_root/monorepo/services/api/compose.yaml"
old_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
new_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
new_digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

make_old_release() {
  local deploy_root="$1"
  local release="$deploy_root/releases/$old_sha"
  mkdir -p "$release/deploy"
  cp "$basic_compose" "$release/compose.yaml"
  printf '%s\n' 'legacy backup runner' > "$release/deploy/backup-agenda.sh"
  chmod 0755 "$release/deploy/backup-agenda.sh"
  mkdir -p "$release/deploy/systemd"
  printf '%s\n' 'legacy backup unit' > "$release/deploy/systemd/backup.service"
  cat > "$release/deploy/project.env" <<EOF
PROJECT_SLUG=fixture-app
DEPLOY_USER=deploy
CONTAINER_PORT=8080
HEALTH_PATH=/healthz
COMPOSE_PROJECT_NAME=fixture-app
APP_ENV_FILE=$deploy_root/shared/.env
EOF
  printf 'APP_IMAGE=ghcr.io/example/app@%s\n' "$old_digest" > "$release/deploy/image.env"
  printf '%s\n' "$old_sha" > "$release/deploy-sha.txt"
  touch -t 202001010000 "$release"
  ln -s "$release" "$deploy_root/current"
  printf '%s\n%s\n' "ghcr.io/example/app@$old_digest" "$old_sha" > "$TEST_STATE"
}

make_new_archive() {
  local deploy_root="$1" release_id="$2" archive="$3" compose_file="$4" staging
  staging="$(mktemp -d "$tmp/stage.XXXXXX")"
  mkdir -p "$staging/deploy"
  cp "$compose_file" "$staging/compose.yaml"
  cat > "$staging/deploy/project.env" <<EOF
PROJECT_SLUG=fixture-app
DEPLOY_USER=deploy
CONTAINER_PORT=8080
HEALTH_PATH=/healthz
COMPOSE_PROJECT_NAME=fixture-app
APP_ENV_FILE=$deploy_root/shared/.env
EOF
  printf 'APP_IMAGE=ghcr.io/example/app@%s\n' "$new_digest" > "$staging/deploy/image.env"
  printf '%s\n' "$new_sha" > "$staging/deploy-sha.txt"
  printf '%s\n' "$release_id" > "$staging/deploy-release-id.txt"
  printf 'backup runner for %s\n' "$release_id" > "$staging/deploy/backup-agenda.sh"
  chmod 0755 "$staging/deploy/backup-agenda.sh"
  mkdir -p "$staging/deploy/systemd"
  printf 'backup unit for %s\n' "$release_id" > "$staging/deploy/systemd/backup.service"
  tar -czf "$archive" -C "$staging" .
  rm -rf "$staging"
}

# First deploy: root exists, but current and releases do not. Activation must
# succeed and atomically create current only after the health check passes.
initial_root="$tmp/initial"
mkdir -p "$initial_root"
initial_id="$new_sha-090-1"
initial_archive="$tmp/initial.tar.gz"
make_new_archive "$initial_root" "$initial_id" "$initial_archive" "$basic_compose"
bash "$root/scripts/activate-release.sh" "$new_sha" "$initial_id" fixture-app "$initial_root" 18080 5 "$initial_archive"
[[ -L "$initial_root/current" ]]
[[ "$(basename -- "$(readlink -f "$initial_root/current")")" == "$initial_id" ]]
[[ "$(cat "$initial_root/current/deploy/backup-agenda.sh")" == "backup runner for $initial_id" ]]
[[ "$(cat "$initial_root/current/deploy/systemd/backup.service")" == "backup unit for $initial_id" ]]

# Existing deployment: use the monorepo fixture, verify successful activation,
# and confirm release retention does not invoke server-wide image pruning.
success_root="$tmp/success"
mkdir -p "$success_root"
make_old_release "$success_root"
success_id="$new_sha-100-1"
success_archive="$tmp/success.tar.gz"
make_new_archive "$success_root" "$success_id" "$success_archive" "$monorepo_compose"
bash "$root/scripts/activate-release.sh" "$new_sha" "$success_id" fixture-app "$success_root" 18080 1 "$success_archive"
[[ "$(basename -- "$(readlink -f "$success_root/current")")" == "$success_id" ]]
[[ ! -e "$success_root/releases/$old_sha" ]]
[[ "$(head -n1 "$TEST_STATE")" == "ghcr.io/example/app@$new_digest" ]]
[[ "$(cat "$success_root/current/deploy/backup-agenda.sh")" == "backup runner for $success_id" ]]
[[ "$(cat "$success_root/current/deploy/systemd/backup.service")" == "backup unit for $success_id" ]]

# An unhealthy new release leaves current on the prior release and restarts
# that release. Both Compose fixture forms are exercised across these cases.
rollback_root="$tmp/rollback"
mkdir -p "$rollback_root"
make_old_release "$rollback_root"
rollback_id="$new_sha-101-1"
rollback_archive="$tmp/rollback.tar.gz"
make_new_archive "$rollback_root" "$rollback_id" "$rollback_archive" "$basic_compose"
export FAIL_DIGEST="$new_digest"
if bash "$root/scripts/activate-release.sh" "$new_sha" "$rollback_id" fixture-app "$rollback_root" 18080 5 "$rollback_archive"; then
  echo "Expected unhealthy deployment to fail." >&2; exit 1
else
  [[ $? -eq 1 ]]
fi
unset FAIL_DIGEST
[[ "$(basename -- "$(readlink -f "$rollback_root/current")")" == "$old_sha" ]]
[[ "$(head -n1 "$TEST_STATE")" == "ghcr.io/example/app@$old_digest" ]]
[[ "$(cat "$rollback_root/current/deploy/backup-agenda.sh")" == "legacy backup runner" ]]
[[ "$(cat "$rollback_root/current/deploy/systemd/backup.service")" == "legacy backup unit" ]]
[[ "$(cat "$rollback_root/releases/$rollback_id/deploy/backup-agenda.sh")" == "backup runner for $rollback_id" ]]

# With no rollback target, a failed initial deployment leaves current absent,
# retains the failed release for diagnosis, and clearly reports manual recovery.
initial_fail_root="$tmp/initial-failure"
mkdir -p "$initial_fail_root"
initial_fail_id="$new_sha-102-1"
initial_fail_archive="$tmp/initial-failure.tar.gz"
make_new_archive "$initial_fail_root" "$initial_fail_id" "$initial_fail_archive" "$basic_compose"
export FAIL_DIGEST="$new_digest"
if bash "$root/scripts/activate-release.sh" "$new_sha" "$initial_fail_id" fixture-app "$initial_fail_root" 18080 5 "$initial_fail_archive" > "$tmp/initial-failure.log" 2>&1; then
  echo "Expected unhealthy initial deployment to fail." >&2; exit 1
else
  [[ $? -eq 1 ]]
fi
unset FAIL_DIGEST
[[ ! -e "$initial_fail_root/current" && ! -L "$initial_fail_root/current" ]]
[[ -d "$initial_fail_root/releases/$initial_fail_id" ]]
grep -q 'Deployment and rollback failed; manual intervention required.' "$tmp/initial-failure.log"

# Existing current paths must be symlinks to direct, valid release directories.
invalid_root="$tmp/invalid-current"
mkdir -p "$invalid_root/releases" "$tmp/outside-release"
ln -s "$tmp/outside-release" "$invalid_root/current"
invalid_archive="$tmp/invalid-current.tar.gz"
make_new_archive "$invalid_root" "$new_sha-103-1" "$invalid_archive" "$basic_compose"
before="$(wc -l < "$FAKE_DOCKER_LOG")"
if bash "$root/scripts/activate-release.sh" "$new_sha" "$new_sha-103-1" fixture-app "$invalid_root" 18080 5 "$invalid_archive"; then
  echo "Expected external current symlink rejection." >&2; exit 1
else
  [[ $? -eq 1 ]]
fi
[[ "$(wc -l < "$FAKE_DOCKER_LOG")" -eq "$before" ]]

file_current_root="$tmp/file-current"
mkdir -p "$file_current_root"
echo invalid > "$file_current_root/current"
file_archive="$tmp/file-current.tar.gz"
make_new_archive "$file_current_root" "$new_sha-104-1" "$file_archive" "$basic_compose"
if bash "$root/scripts/activate-release.sh" "$new_sha" "$new_sha-104-1" fixture-app "$file_current_root" 18080 5 "$file_archive"; then
  echo "Expected non-symlink current path rejection." >&2; exit 1
else
  [[ $? -eq 1 ]]
fi

! grep -q '^image prune' "$FAKE_DOCKER_LOG"
grep -q 'compose env APP_IMAGE=ghcr.io/example/app@sha256:' "$FAKE_DOCKER_LOG"
grep -q 'APP_PORT=18080 CONTAINER_PORT=8080 COMPOSE_PROJECT_NAME=fixture-app' "$FAKE_DOCKER_LOG"
echo "First deployment, Compose interpolation, health timeouts, retention, invalid current, and rollback checks passed."
