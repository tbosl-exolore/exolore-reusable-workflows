#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/ghcr.sh"
source "$script_dir/lib/paths.sh"

root="$(realpath -e -- "$GITHUB_WORKSPACE/caller")"
workdir="$(resolve_working_directory "$root" "$WORKING_DIRECTORY")"
compose_file="$(resolve_inside "$workdir" "$COMPOSE_FILE" "Compose file")"
project_config="$(resolve_inside "$workdir" "$PROJECT_CONFIG_FILE" "Project configuration")"
[[ -f "$compose_file" && -f "$project_config" ]] || { workflow_error "Release contract" "Compose and project configuration must be files."; exit 1; }
[[ -n "$IMAGE_REF" && "$IMAGE_REF" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] || { workflow_error "Image reference" "A validated digest-pinned GHCR image is required."; exit 1; }
: "${DEPLOY_SSH_KEY:?Missing production environment secret DEPLOY_SSH_KEY}"
: "${SSH_KNOWN_HOSTS:?Missing production environment secret SSH_KNOWN_HOSTS}"
: "${SERVER_HOST:?Missing production variable SERVER_HOST}"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
printf '%s\n' "$DEPLOY_SSH_KEY" > "$HOME/.ssh/id_ed25519"
printf '%s\n' "$SSH_KNOWN_HOSTS" > "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/known_hosts"
run_checked_quiet "SSH private key validation" ssh-keygen -y -f "$HOME/.ssh/id_ed25519"
run_checked_quiet "SSH known-host validation" ssh-keygen -F "$SERVER_HOST" -f "$HOME/.ssh/known_hosts"

staging="$(mktemp -d "$RUNNER_TEMP/exolore-release.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
install -d "$staging/deploy"
install -m 0644 "$compose_file" "$staging/compose.yaml"
install -m 0644 "$project_config" "$staging/deploy/project.env"
printf 'APP_IMAGE=%s\n' "$IMAGE_REF" > "$staging/deploy/image.env"
printf '%s\n' "$SOURCE_SHA" > "$staging/deploy-sha.txt"
printf '%s\n' "$RELEASE_ID" > "$staging/deploy-release-id.txt"
install -m 0755 "$GITHUB_WORKSPACE/central-workflow/scripts/activate-release.sh" "$staging/deploy/activate-release.sh"
tar -C "$staging" -czf "$ARCHIVE_PATH" .
echo "Packaged release contract for $PROJECT_SLUG at $IMAGE_REF"
