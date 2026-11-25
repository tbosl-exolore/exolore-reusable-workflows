#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/ghcr.sh"
source "$script_dir/lib/paths.sh"
trap ghcr_cleanup EXIT

[[ "$PRODUCTION_SHA" =~ ^[0-9a-f]{40}$ ]] || { workflow_error "Production SHA" "production_sha must be a full 40-character lowercase commit SHA."; exit 1; }
checkout_sha="$(git -C "$GITHUB_WORKSPACE/caller" rev-parse HEAD)"
[[ "$checkout_sha" == "$PRODUCTION_SHA" ]] || { workflow_error "Production checkout" "Checked out commit does not match production_sha."; exit 1; }
root="$(realpath -e -- "$GITHUB_WORKSPACE/caller")"
workdir="$(resolve_working_directory "$root" "$WORKING_DIRECTORY")"
dockerfile="$(resolve_inside "$workdir" "$DOCKERFILE" "Dockerfile")"
context="$(resolve_inside "$workdir" "$BUILD_CONTEXT" "Docker build context")"
[[ -f "$dockerfile" && -d "$context" ]] || { workflow_error "Docker build contract" "Dockerfile and build context must be valid."; exit 1; }

image_repository="ghcr.io/${GITHUB_REPOSITORY,,}"
tag="$image_repository:$PRODUCTION_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
publish_image "$tag" "$PRODUCTION_SHA" "$dockerfile" "$context"
image_ref="$image_repository@$IMAGE_DIGEST"
{
  printf 'image_ref=%s\n' "$image_ref"
  printf 'image_digest=%s\n' "$IMAGE_DIGEST"
} >> "$GITHUB_OUTPUT"
printf 'Baseline image: `%s`\n\nBuilt from production commit `%s`. This rebuild does not prove byte-for-byte identity with the image originally deployed.\n' "$image_ref" "$PRODUCTION_SHA" >> "$GITHUB_STEP_SUMMARY"
echo "Published baseline $image_ref from $PRODUCTION_SHA using tag $tag"
