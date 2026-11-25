#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
caller="$tmp/workspace/caller"
mkdir -p "$caller/deploy/systemd" "$caller/assets/health" "$tmp/workspace/central-workflow/scripts" "$tmp/bin" "$tmp/runner" "$tmp/home"
cat > "$tmp/bin/ssh-keygen" <<'SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
  -y) echo 'ssh-ed25519 AAAATEST fixture' ;;
  -F) echo 'example.invalid ssh-ed25519 AAAATEST' ;;
  *) exit 90 ;;
esac
SSH
chmod +x "$tmp/bin/ssh-keygen"
cat > "$caller/compose.yaml" <<'COMPOSE'
services:
  app:
    image: ${APP_IMAGE}
COMPOSE
cat > "$caller/deploy/project.env" <<'CONFIG'
PROJECT_SLUG=package-fixture
DEPLOY_BASE=/opt
DEPLOY_USER=deploy
CONTAINER_PORT=8080
HEALTH_PATH=/healthz
COMPOSE_PROJECT_NAME=package-fixture
APP_ENV_FILE=/opt/package-fixture/shared/.env
CONFIG
cat > "$caller/deploy/backup-agenda.sh" <<'RUNNER'
#!/usr/bin/env bash
exit 0
RUNNER
chmod 0755 "$caller/deploy/backup-agenda.sh"
printf '[Unit]\nDescription=fixture service\n' > "$caller/deploy/systemd/backup.service"
printf '[Timer]\nOnCalendar=daily\n' > "$caller/deploy/systemd/backup.timer"
printf 'health=ready\n' > "$caller/assets/health/check.conf"
printf 'runtime-secret=not-for-release\n' > "$caller/.env.production"
printf 'password=not-for-release\n' > "$caller/deploy/credentials.json"
printf 'central activator fixture\n' > "$tmp/workspace/central-workflow/scripts/activate-release.sh"

(
  cd "$caller"
  git init -q
  git config user.name Fixture
  git config user.email fixture@example.invalid
  git add .
  git commit -qm 'verified consumer fixture'
)

export PATH="$tmp/bin:$PATH"
export GITHUB_WORKSPACE="$tmp/workspace"
export WORKING_DIRECTORY=.
export COMPOSE_FILE=compose.yaml
export PROJECT_CONFIG_FILE=deploy/project.env
export IMAGE_REF=ghcr.io/example/package-fixture@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
backslash_path='deploy\backup-agenda.sh'
printf 'literal backslash path\n' > "$caller/$backslash_path"
(
  cd "$caller"
  git add -- "$backslash_path"
  git commit -qm 'add backslash path'
)
export SOURCE_SHA="$(git -C "$caller" rev-parse HEAD)"
export PROJECT_SLUG=package-fixture
export RELEASE_ID="$SOURCE_SHA-123-1"
export ARCHIVE_PATH="$tmp/runner/default.tar.gz"
export RUNNER_TEMP="$tmp/runner"
export HOME="$tmp/home"
export DEPLOY_SSH_KEY=fixture-key
export SSH_KNOWN_HOSTS='example.invalid ssh-ed25519 AAAATEST'
export SERVER_HOST=example.invalid
export SERVER_USER=deploy
export DEPLOY_ROOT_OVERRIDE=
export APP_PORT=18080
export RELEASE_RETENTION=5

run_package() {
  local name="$1" paths="${2:-}"
  ARCHIVE_PATH="$tmp/runner/$name.tar.gz" \
    ADDITIONAL_RELEASE_PATHS="$paths" \
    bash "$root/scripts/package-release.sh"
}
assert_rejected() {
  local name="$1" paths="$2"
  rm -f "$tmp/runner/$name.tar.gz"
  if run_package "$name" "$paths" > "$tmp/$name.log" 2>&1; then
    echo "Expected package request '$name' to be rejected." >&2
    exit 1
  fi
  [[ ! -e "$tmp/runner/$name.tar.gz" ]]
}

# Omitted input keeps the original managed release layout.
unset ADDITIONAL_RELEASE_PATHS
bash "$root/scripts/package-release.sh" >/dev/null
! tar -tzf "$ARCHIVE_PATH" | grep -q 'backup-agenda\|systemd\|assets/health'

# Read files from the verified Git object, even if the checkout worktree was
# modified or given an untracked file after checkout.
printf 'mutated after checkout\n' > "$caller/deploy/backup-agenda.sh"
printf 'untracked\n' > "$caller/deploy/untracked.sh"
paths=$'deploy/backup-agenda.sh\ndeploy/systemd\nassets/health'
run_package complete "$paths" >/dev/null
mkdir -p "$tmp/extracted"
tar -xzf "$tmp/runner/complete.tar.gz" -C "$tmp/extracted"
[[ -x "$tmp/extracted/deploy/backup-agenda.sh" ]]
[[ "$(stat -c '%a' "$tmp/extracted/deploy/backup-agenda.sh")" == 755 ]]
[[ "$(cat "$tmp/extracted/deploy/backup-agenda.sh")" == $'#!/usr/bin/env bash\nexit 0' ]]
[[ "$(cat "$tmp/extracted/deploy/systemd/backup.service")" == '[Unit]'* ]]
[[ "$(cat "$tmp/extracted/assets/health/check.conf")" == 'health=ready' ]]

assert_rejected missing 'deploy/not-present.sh'
assert_rejected untracked 'deploy/untracked.sh'
assert_rejected absolute '/etc/passwd'
assert_rejected backslash "$backslash_path"
assert_rejected windows_absolute 'C:\\Windows\\win.ini'
assert_rejected traversal '../outside'
assert_rejected tab_control $'deploy/backup-agenda.sh\t'
assert_rejected dot_component 'deploy/../compose.yaml'
assert_rejected collision_compose 'compose.yaml'
assert_rejected collision_project_config 'deploy/project.env'
assert_rejected collision_parent 'deploy'
assert_rejected runtime_env '.env.production'
assert_rejected credentials 'deploy/credentials.json'
assert_rejected duplicate $'deploy/systemd\ndeploy/systemd/backup.service'
injection=$'deploy/backup-agenda.sh\n$(touch '"$tmp/pwned"')'
assert_rejected injection "$injection"
[[ ! -e "$tmp/pwned" ]]

# Git symlinks and submodules are not regular release files and are rejected.
ln -s "$tmp/outside" "$caller/deploy/escape-link"
(
  cd "$caller"
  git add deploy/escape-link
  git commit -qm 'add linked path'
)
export SOURCE_SHA="$(git -C "$caller" rev-parse HEAD)"
export RELEASE_ID="$SOURCE_SHA-124-1"
assert_rejected symlink 'deploy/escape-link'

mkdir -p "$tmp/subrepo"
(
  cd "$tmp/subrepo"
  git init -q
  git config user.name Fixture
  git config user.email fixture@example.invalid
  echo submodule > README.md
  git add README.md
  git commit -qm 'fixture submodule'
)
sub_sha="$(git -C "$tmp/subrepo" rev-parse HEAD)"
(
  cd "$caller"
  git update-index --add --cacheinfo "160000,$sub_sha,deploy/submodule"
  git commit -qm 'add gitlink'
)
export SOURCE_SHA="$(git -C "$caller" rev-parse HEAD)"
export RELEASE_ID="$SOURCE_SHA-125-1"
assert_rejected submodule 'deploy/submodule'

echo "Additional release path packaging, validation, and executable-mode checks passed."
