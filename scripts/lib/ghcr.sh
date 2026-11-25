#!/usr/bin/env bash

workflow_error() {
  local title="$1" message="$2"
  message="${message//%/%25}"
  message="${message//$'\r'/%0D}"
  message="${message//$'\n'/%0A}"
  printf '::error title=%s::%s\n' "$title" "$message" >&2
}

run_checked() {
  local label="$1" status
  shift
  if "$@"; then
    return 0
  else
    status=$?
    workflow_error "$label" "Command failed with exit code $status."
    return "$status"
  fi
}

run_checked_quiet() {
  local label="$1" status
  shift
  if "$@" >/dev/null; then
    return 0
  else
    status=$?
    workflow_error "$label" "Command failed with exit code $status."
    return "$status"
  fi
}

ghcr_login() {
  local status
  : "${GHCR_TOKEN:?Missing GITHUB_TOKEN for GHCR write access}"
  : "${GITHUB_ACTOR:?Missing GITHUB_ACTOR}"
  if printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin; then
    GHCR_LOGGED_IN=1
  else
    status=$?
    workflow_error "GHCR login" "Registry login failed with exit code $status."
    return "$status"
  fi
}

ghcr_logout() {
  local status
  (( ${GHCR_LOGGED_IN:-0} == 1 )) || return 0
  if docker logout ghcr.io; then
    GHCR_LOGGED_IN=0
  else
    status=$?
    workflow_error "GHCR logout" "Registry logout failed with exit code $status."
    return "$status"
  fi
}

ghcr_cleanup() {
  if (( ${GHCR_LOGGED_IN:-0} == 1 )); then
    docker logout ghcr.io >/dev/null 2>&1 || true
    GHCR_LOGGED_IN=0
  fi
}

resolve_image_digest() {
  local tag="$1" inspect_output status digest
  if inspect_output="$(docker buildx imagetools inspect "$tag")"; then
    :
  else
    status=$?
    workflow_error "GHCR digest inspection" "Buildx inspect failed with exit code $status for $tag."
    return "$status"
  fi

  # Parse only after command substitution has consumed all output. This avoids
  # an early-exiting awk process closing Buildx's pipe under Bash pipefail.
  digest="$(awk '$1 == "Digest:" && !found {print $2; found=1}' <<< "$inspect_output")"
  if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    workflow_error "GHCR digest validation" "Inspect returned no valid SHA-256 digest for $tag."
    return 1
  fi
  IMAGE_DIGEST="$digest"
}

publish_image() {
  local tag="$1" revision="$2" dockerfile="$3" context="$4"
  ghcr_login || return $?
  unset GHCR_TOKEN
  run_checked "Docker build" docker build \
    --label "org.opencontainers.image.revision=$revision" \
    --file "$dockerfile" \
    --tag "$tag" \
    "$context" || return $?
  run_checked "GHCR image push" docker push "$tag" || return $?
  resolve_image_digest "$tag" || return $?
  ghcr_logout || return $?
}
