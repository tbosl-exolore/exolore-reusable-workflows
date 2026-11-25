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
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || { workflow_error "Source revision" "SOURCE_SHA must be a full lower-case commit SHA."; exit 1; }
checkout_sha="$(git -C "$root" rev-parse --verify HEAD)" || { workflow_error "Caller checkout" "Unable to determine checked-out commit."; exit 1; }
[[ "$checkout_sha" == "$SOURCE_SHA" ]] || { workflow_error "Caller checkout" "Checked-out source does not match the published image revision."; exit 1; }

staging="$(mktemp -d "$RUNNER_TEMP/exolore-release.XXXXXX")"
metadata_file=""
cleanup() {
  rm -rf -- "$staging"
  [[ -z "$metadata_file" ]] || rm -f -- "$metadata_file"
}
trap cleanup EXIT
install -d "$staging/deploy"
install -m 0644 "$compose_file" "$staging/compose.yaml"
install -m 0644 "$project_config" "$staging/deploy/project.env"
printf 'APP_IMAGE=%s\n' "$IMAGE_REF" > "$staging/deploy/image.env"
printf '%s\n' "$SOURCE_SHA" > "$staging/deploy-sha.txt"
printf '%s\n' "$RELEASE_ID" > "$staging/deploy-release-id.txt"
install -m 0755 "$GITHUB_WORKSPACE/central-workflow/scripts/activate-release.sh" "$staging/deploy/activate-release.sh"

# Each non-empty line is one literal repository-relative path. Read files from
# Git objects at SOURCE_SHA, not from potentially modified or untracked files in
# the runner's working tree. Git records only the executable bit for regular
# files; reproduce it without copying ownership or special mode bits.
declare -a additional_paths=() additional_files=() additional_modes=() additional_objects=()
managed_paths=(
  "compose.yaml"
  "deploy/project.env"
  "deploy/image.env"
  "deploy/activate-release.sh"
  "deploy-sha.txt"
  "deploy-release-id.txt"
)
raw_paths="${ADDITIONAL_RELEASE_PATHS:-}"
while IFS= read -r requested_path || [[ -n "$requested_path" ]]; do
  requested_path="${requested_path%$'\r'}"
  [[ -z "${requested_path//[[:space:]]/}" ]] && continue
  [[ ! "$requested_path" =~ ^[[:space:]]|[[:space:]]$ ]] || { workflow_error "Additional release paths" "Paths cannot have leading or trailing whitespace."; exit 1; }
  [[ ! "$requested_path" =~ [[:cntrl:]] ]] || { workflow_error "Additional release paths" "Control characters are not supported in paths."; exit 1; }
  [[ "$requested_path" != /* && "$requested_path" != *$'\x5c'* && "$requested_path" != *:* ]] || {
    workflow_error "Additional release paths" "Each path must be a portable relative path using forward slashes."; exit 1;
  }
  IFS='/' read -r -a requested_components <<< "$requested_path"
  for component in "${requested_components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || {
      workflow_error "Additional release paths" "Empty, current-directory, and parent-directory components are not allowed."; exit 1;
    }
  done

  for managed in "${managed_paths[@]}"; do
    [[ "$requested_path" != "$managed" && "$requested_path" != "$managed/"* && "$managed" != "$requested_path/"* ]] || {
      workflow_error "Additional release paths" "An additional path overlaps a centrally managed release path."; exit 1;
    }
  done
  for prior in "${additional_paths[@]}"; do
    [[ "$requested_path" != "$prior" && "$requested_path" != "$prior/"* && "$prior" != "$requested_path/"* ]] || {
      workflow_error "Additional release paths" "Duplicate or overlapping paths are not allowed."; exit 1;
    }
  done
  additional_paths+=("$requested_path")

  metadata_file="$(mktemp "$RUNNER_TEMP/exolore-git-tree.XXXXXX")"
  if ! git -C "$root" ls-tree -r -z --full-tree "$SOURCE_SHA" -- ":(literal)$requested_path" > "$metadata_file"; then
    workflow_error "Additional release paths" "Unable to inspect a requested path in the verified caller commit."; exit 1
  fi
  mapfile -d '' -t tree_entries < "$metadata_file"
  rm -f -- "$metadata_file"
  metadata_file=""
  ((${#tree_entries[@]} > 0)) || { workflow_error "Additional release paths" "A requested path is missing from the verified caller commit."; exit 1; }

  for entry in "${tree_entries[@]}"; do
    [[ "$entry" == *$'\t'* ]] || { workflow_error "Additional release paths" "The Git tree returned an invalid entry."; exit 1; }
    metadata="${entry%%$'\t'*}"
    source_path="${entry#*$'\t'}"
    read -r mode object_type object_id <<< "$metadata"
    [[ "$source_path" == "$requested_path" || "$source_path" == "$requested_path/"* ]] || {
      workflow_error "Additional release paths" "A requested path resolved outside its repository-relative prefix."; exit 1;
    }
    [[ ! "$source_path" =~ [[:cntrl:]] ]] || { workflow_error "Additional release paths" "Control characters are not supported in paths."; exit 1; }
    [[ "$object_type" == blob && ( "$mode" == 100644 || "$mode" == 100755 ) ]] || {
      workflow_error "Additional release paths" "Symlinks, submodules, and non-regular files are not supported."; exit 1;
    }

    IFS='/' read -r -a source_components <<< "$source_path"
    for component in "${source_components[@]}"; do
      lower_component="${component,,}"
      case "$lower_component" in
        .git*|.ssh|.aws|.docker|*credential*|*secret*|*token*|*private-key*|*private_key*|private-keys|private_keys|authorized_keys|known_hosts|id_rsa*|id_ed25519*|.env*|*.env|*.env.*|*.pem|*.key|*.p12|*.pfx|*.asc|*.secret*)
          workflow_error "Additional release paths" "A selected path contains a Git metadata, credential, or runtime environment name."; exit 1 ;;
      esac
    done
    for managed in "${managed_paths[@]}"; do
      [[ "$source_path" != "$managed" ]] || { workflow_error "Additional release paths" "A selected path collides with a centrally managed release file."; exit 1; }
    done

    additional_files+=("$source_path")
    additional_modes+=("$mode")
    additional_objects+=("$object_id")
  done
done <<< "$raw_paths"

for index in "${!additional_files[@]}"; do
  source_path="${additional_files[$index]}"
  destination="$staging/$source_path"
  mkdir -p -- "$(dirname -- "$destination")"
  if ! git -C "$root" cat-file blob "${additional_objects[$index]}" > "$destination"; then
    workflow_error "Additional release paths" "Unable to read a selected file from the verified caller commit."; exit 1
  fi
  if [[ "${additional_modes[$index]}" == 100755 ]]; then
    chmod 0755 -- "$destination"
  else
    chmod 0644 -- "$destination"
  fi
done

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

tar -C "$staging" -czf "$ARCHIVE_PATH" .
echo "Packaged release contract for $PROJECT_SLUG at $IMAGE_REF"
