#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 7 ]] || { echo "Usage: $0 SOURCE_SHA RELEASE_ID PROJECT DEPLOY_ROOT APP_PORT RETENTION ARCHIVE" >&2; exit 2; }
sha="$1"; release_id="$2"; project="$3"; root="$4"; app_port="$5"; retention="$6"; archive="$7"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ "$release_id" =~ ^[0-9a-f]{40}(-[0-9]+-[0-9]+)?$ ]] || exit 1
[[ "$project" =~ ^[a-z0-9][a-z0-9-]*$ ]] || exit 1
[[ "$root" =~ ^/[a-zA-Z0-9._/-]+$ ]] || exit 1
[[ "$root" != *"/../"* && "$root" != */.. ]] || exit 1
[[ "$app_port" =~ ^[0-9]{2,5}$ ]] && (( app_port >= 1024 && app_port <= 65535 )) || exit 1
[[ "$retention" =~ ^[1-9][0-9]*$ ]] || exit 1

releases="$root/releases"; current="$root/current"; release="$releases/$release_id"
previous=""
if [[ -e "$current" || -L "$current" ]]; then
  [[ -L "$current" ]] || { echo "Current release path exists but is not a symlink." >&2; exit 1; }
  previous="$(readlink -f "$current" 2>/dev/null)" || { echo "Current release symlink cannot be resolved." >&2; exit 1; }
  releases_real="$(realpath -m -- "$releases")"
  previous_name="$(basename -- "$previous")"
  [[ -d "$previous" && "$(dirname -- "$previous")" == "$releases_real" && "$previous_name" =~ ^[0-9a-f]{40}(-[0-9]+-[0-9]+)?$ ]] || {
    echo "Current release symlink does not point to a valid release directory." >&2
    exit 1
  }
fi
[[ ! -e "$release" ]] || { echo "Release already exists: $release_id" >&2; exit 1; }
mkdir -p "$releases" "$release"
tar -xzf "$archive" -C "$release"
rm -f -- "$archive"

load_release() {
  local dir="$1" marker_sha marker_id
  [[ -f "$dir/deploy/project.env" && -f "$dir/deploy/image.env" && -f "$dir/deploy-sha.txt" ]] || return 1
  marker_sha="$(tr -d '\r\n' < "$dir/deploy-sha.txt")"
  [[ "$marker_sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  if [[ -f "$dir/deploy-release-id.txt" ]]; then
    marker_id="$(tr -d '\r\n' < "$dir/deploy-release-id.txt")"
    [[ "$marker_id" == "$(basename -- "$dir")" && "$marker_id" =~ ^[0-9a-f]{40}(-[0-9]+-[0-9]+)?$ ]] || return 1
  else
    # Compatibility with existing releases created before unique run IDs.
    [[ "$(basename -- "$dir")" == "$marker_sha" ]] || return 1
  fi
  unset APP_IMAGE CONTAINER_PORT HEALTH_PATH PROJECT_SLUG COMPOSE_PROJECT_NAME APP_ENV_FILE
  export DEPLOY_ROOT="$root"
  set -a
  source "$dir/deploy/project.env" || { set +a; return 1; }
  source "$dir/deploy/image.env" || { set +a; return 1; }
  set +a
  [[ "$PROJECT_SLUG" == "$project" ]] || return 1
  [[ "$APP_IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] || return 1
  [[ "$CONTAINER_PORT" =~ ^[0-9]{1,5}$ ]] && (( CONTAINER_PORT >= 1 && CONTAINER_PORT <= 65535 )) || return 1
  [[ "$HEALTH_PATH" =~ ^/[a-zA-Z0-9._~/%-]*$ ]] || return 1
  [[ "$APP_ENV_FILE" == "$root/shared/.env" ]] || return 1
  LOADED_RELEASE_SHA="$marker_sha"
}

if [[ -n "$previous" ]] && ! load_release "$previous"; then
  echo "Current release contents are invalid; refusing deployment without a verified rollback target." >&2
  exit 1
fi
if ! load_release "$release"; then
  echo "New release contents are invalid; refusing activation." >&2
  exit 1
fi

compose() {
  APP_PORT="$app_port" \
    CONTAINER_PORT="$CONTAINER_PORT" \
    APP_IMAGE="$APP_IMAGE" \
    APP_ENV_FILE="$APP_ENV_FILE" \
    COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" \
    DEPLOY_ROOT="$root" \
    docker compose -p "$COMPOSE_PROJECT_NAME" "$@"
}

start_release() {
  local dir="$1"
  load_release "$dir" || return 1
  cd "$dir"
  compose pull app || return 1
  compose up -d --no-build --force-recreate --remove-orphans app || return 1
}

verify_release() {
  local container_id running_image_id expected_image_id revision
  container_id="$(compose ps -q app)"
  [[ "$container_id" =~ ^[0-9a-f]{12,64}$ ]] || return 1
  running_image_id="$(docker inspect --format '{{.Image}}' "$container_id")"
  expected_image_id="$(docker image inspect --format '{{.Id}}' "$APP_IMAGE")"
  revision="$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$container_id")"
  [[ "$running_image_id" == "$expected_image_id" && "$revision" == "$LOADED_RELEASE_SHA" ]] || return 1
  # At most 20 requests of 5 seconds and 19 pauses of 3 seconds: 157 seconds.
  for attempt in {1..20}; do
    curl --fail --silent --show-error --connect-timeout 2 --max-time 5 \
      "http://127.0.0.1:${app_port}${HEALTH_PATH}" >/dev/null && return 0
    if (( attempt < 20 )); then sleep 3; fi
  done
  return 1
}

rollback() {
  [[ -n "$previous" && -d "$previous" && "$previous" == "$releases/"* ]] || return 1
  echo "Rolling back to $(basename -- "$previous")"
  start_release "$previous" && verify_release
}

link_current_atomically() {
  local target="$1" tmp="$root/.current-$release_id"
  rm -f -- "$tmp"
  ln -s "$target" "$tmp"
  mv -Tf -- "$tmp" "$current"
}

if start_release "$release" && verify_release; then
  link_current_atomically "$release"
  find "$releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' |
    sort -nr | tail -n "+$((retention + 1))" | cut -d' ' -f2- | xargs -r rm -rf
  echo "Deployed $APP_IMAGE from $sha"
else
  compose logs --tail=100 || true
  if rollback; then
    echo "Deployment failed; rollback succeeded." >&2
  else
    echo "Deployment and rollback failed; manual intervention required." >&2
  fi
  exit 1
fi
