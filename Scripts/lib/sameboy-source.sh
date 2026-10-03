#!/usr/bin/env bash

# Resolve the pinned SameBoy submodule, the only source the package and scripts build from.
resolve_sameboy_root() {
  local candidate="$1/Packages/EmulatorKit/Dependencies/SameBoy"
  if [[ -f "$candidate/version.mk" && -d "$candidate/Core" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}
