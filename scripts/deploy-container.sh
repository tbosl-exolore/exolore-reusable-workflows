#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/ghcr.sh"
source "$script_dir/lib/paths.sh"
trap ghcr_cleanup EXIT

root="$(realpath -e -- "$GITHUB_WORKSPACE/caller")"
workdir="$(resolve_working_directory "$root" "$WORKING_DIRECTORY")"
config_file="$(resolve_inside "$workdir" "$PROJECT_CONFIG_FILE" "Project configuration")"
dockerfile="$(resolve_inside "$workdir" "$DOCKERFILE" "Dockerfile")"
context="$(resolve_inside "$workdir" "$BUILD_CONTEXT" "Docker build context")"
[[ -f "$config_file" ]] || { workflow_error "Project configuration" "Path must be a file."; exit 1; }
[[ -d "$context" ]] || { workflow_error "Docker build context" "Path must be a directory."; exit 1; }
[[ -f "$dockerfile" ]] || { workflow_error "Dockerfile" "Path must be a file."; exit 1; }

if [[ -n "$BUILD_HOOK" ]]; then
  build_hook="$(resolve_inside "$workdir" "$BUILD_HOOK" "Build hook")"
  [[ -f "$build_hook" ]] || { workflow_error "Build hook" "Path must be a file."; exit 1; }
  cd "$workdir"
  run_checked "Project build hook" env -u GHCR_TOKEN bash "$build_hook"
fi

source "$config_file"
DEPLOY_ROOT_VALUE="${DEPLOY_ROOT_OVERRIDE:-${DEPLOY_BASE%/}/$PROJECT_SLUG}"
: "${SERVER_HOST:?Missing production variable SERVER_HOST}"
: "${SERVER_USER:?Missing production variable SERVER_USER}"
[[ "$PROJECT_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { workflow_error "Project configuration" "PROJECT_SLUG must use lowercase letters, digits, and hyphens."; exit 1; }
[[ "${DEPLOY_BASE:-}" =~ ^/[a-zA-Z0-9._/-]+$ ]] || { workflow_error "Project configuration" "DEPLOY_BASE must be an absolute safe path."; exit 1; }
[[ "$SERVER_USER" == "$DEPLOY_USER" ]] || { workflow_error "Deployment user" "SERVER_USER must match DEPLOY_USER in project configuration."; exit 1; }
[[ "$DEPLOY_ROOT_VALUE" =~ ^/[a-zA-Z0-9._/-]+$ ]] || { workflow_error "Deployment root" "DEPLOY_ROOT must be an absolute safe path."; exit 1; }
[[ "$DEPLOY_ROOT_VALUE" != *"/../"* && "$DEPLOY_ROOT_VALUE" != */.. ]] || { workflow_error "Deployment root" "DEPLOY_ROOT must not contain parent-directory components."; exit 1; }
[[ "$APP_PORT" =~ ^[0-9]{2,5}$ ]] && (( APP_PORT >= 1024 && APP_PORT <= 65535 )) || { workflow_error "Application port" "APP_PORT must be between 1024 and 65535."; exit 1; }
[[ "$CONTAINER_PORT" =~ ^[0-9]{1,5}$ ]] && (( CONTAINER_PORT >= 1 && CONTAINER_PORT <= 65535 )) || { workflow_error "Container port" "CONTAINER_PORT must be between 1 and 65535."; exit 1; }
[[ "$HEALTH_PATH" =~ ^/[a-zA-Z0-9._~/%-]*$ ]] || { workflow_error "Health path" "HEALTH_PATH contains unsupported characters."; exit 1; }
[[ "$RELEASE_RETENTION" =~ ^[1-9][0-9]*$ ]] || { workflow_error "Release retention" "RELEASE_RETENTION must be a positive integer."; exit 1; }
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || { workflow_error "Source revision" "GITHUB_SHA must be a full 40-character commit SHA."; exit 1; }
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]] || { workflow_error "Workflow attempt" "Run ID and attempt must be numeric."; exit 1; }

image_repository="ghcr.io/${GITHUB_REPOSITORY,,}"
publication_tag="$image_repository:$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
publish_image "$publication_tag" "$GITHUB_SHA" "$dockerfile" "$context"
image_ref="$image_repository@$IMAGE_DIGEST"

# Each workflow attempt gets a distinct release directory. This prevents a
# rerun for the same source commit from replacing the image behind an older
# release path. The remote activator still reads legacy SHA-named releases.
release_id="$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
archive_path="$RUNNER_TEMP/$PROJECT_SLUG-$release_id.tar.gz"

{
  printf 'image_digest=%s\n' "$IMAGE_DIGEST"
  printf 'image_ref=%s\n' "$image_ref"
  printf 'source_sha=%s\n' "$GITHUB_SHA"
  printf 'project_slug=%s\n' "$PROJECT_SLUG"
  printf 'deploy_root=%s\n' "$DEPLOY_ROOT_VALUE"
  printf 'app_port=%s\n' "$APP_PORT"
  printf 'release_retention=%s\n' "$RELEASE_RETENTION"
  printf 'release_id=%s\n' "$release_id"
  printf 'archive_path=%s\n' "$archive_path"
} >> "$GITHUB_OUTPUT"

echo "Published $image_ref from $GITHUB_SHA using tag $publication_tag"
