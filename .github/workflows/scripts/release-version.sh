#!/usr/bin/env bash
set -euo pipefail

release_version_kind() {
  local version="$1"
  if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc\.(0|[1-9][0-9]*))?$ ]]; then
    echo "::error::Version must be X.Y.Z or X.Y.Z-rc.N without leading zeroes: $version" >&2
    return 1
  fi
  if [[ "$version" == *-rc.* ]]; then
    echo candidate
  else
    echo stable
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  version="${PACKAGE_VERSION_OVERRIDE:-${GITHUB_REF_NAME#v}}"
  release_version_kind "$version" >/dev/null
  if [[ -n "${PACKAGE_VERSION_OVERRIDE:-}" ]]; then
    if [[ "$GITHUB_REF_TYPE" == tag && "$GITHUB_REF_NAME" != "v$version" ]]; then
      echo "::error::Tag $GITHUB_REF_NAME differs from configured version v$version." >&2
      exit 1
    fi
  elif [[ "$GITHUB_REF_NAME" != "v$version" ]]; then
    echo "::error::Expected a vX.Y.Z or vX.Y.Z-rc.N tag: $GITHUB_REF_NAME" >&2
    exit 1
  fi
  printf 'version=%s\nrevision=%s\n' "$version" "$GITHUB_SHA" >> "$GITHUB_OUTPUT"
fi
