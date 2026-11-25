#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/ghcr.sh"

ssh_opts=(-i "$HOME/.ssh/id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes)
remote_archive="/tmp/$PROJECT_SLUG-$RELEASE_ID.tar.gz"
run_checked "Release upload over verified SSH" scp "${ssh_opts[@]}" "$ARCHIVE_PATH" "$SERVER_USER@$SERVER_HOST:$remote_archive"

if ssh "${ssh_opts[@]}" "$SERVER_USER@$SERVER_HOST" bash -s -- \
  "$SOURCE_SHA" "$RELEASE_ID" "$PROJECT_SLUG" "$DEPLOY_ROOT" "$APP_PORT" "$RELEASE_RETENTION" "$remote_archive" <<'REMOTE'
set -Eeuo pipefail
sha="$1"; release_id="$2"; project="$3"; root="$4"; app_port="$5"; retention="$6"; archive="$7"
script="$(mktemp)"
trap 'rm -f -- "$script"' EXIT
tar -xOf "$archive" ./deploy/activate-release.sh > "$script"
chmod 0700 "$script"
"$script" "$sha" "$release_id" "$project" "$root" "$app_port" "$retention" "$archive"
REMOTE
then
  :
else
  status=$?
  workflow_error "Remote deployment" "SSH activation failed with exit code $status."
  exit "$status"
fi
