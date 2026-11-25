#!/usr/bin/env bash

resolve_inside() {
  local base="$1" relative="$2" label="$3" resolved
  if [[ -z "$relative" || "$relative" == /* ]]; then
    workflow_error "$label" "Path must be a non-empty relative path inside the caller checkout."
    return 1
  fi
  if ! resolved="$(realpath -e -- "$base/$relative")"; then
    workflow_error "$label" "Path does not exist inside the caller checkout."
    return 1
  fi
  if [[ "$resolved" != "$base" && "$resolved" != "$base"/* ]]; then
    workflow_error "$label" "Path resolves outside the caller checkout."
    return 1
  fi
  printf '%s\n' "$resolved"
}

resolve_working_directory() {
  local root="$1" relative="$2" resolved
  if [[ -z "$relative" || "$relative" == /* ]]; then
    workflow_error "Caller working directory" "working_directory must be a non-empty relative path."
    return 1
  fi
  if ! resolved="$(realpath -e -- "$root/$relative")"; then
    workflow_error "Caller working directory" "working_directory does not exist."
    return 1
  fi
  if [[ ! -d "$resolved" || ( "$resolved" != "$root" && "$resolved" != "$root"/* ) ]]; then
    workflow_error "Caller working directory" "working_directory must resolve to a directory inside the caller checkout."
    return 1
  fi
  printf '%s\n' "$resolved"
}
