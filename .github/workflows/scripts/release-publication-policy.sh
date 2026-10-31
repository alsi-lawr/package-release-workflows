#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?Missing VERSION}"

# shellcheck source=.github/workflows/scripts/release-version.sh
source "$(dirname "${BASH_SOURCE[0]}")/release-version.sh"
kind="$(release_version_kind "$VERSION")"
stable_channels=false
if [[ "$kind" == stable ]]; then
  stable_channels=true
fi
printf 'stable_channels=%s\n' "$stable_channels" >> "$GITHUB_OUTPUT"

require_secret() {
  local value="$1"
  local name="$2"
  if test -z "$value"; then
    echo "::error::${name} is required by an enabled publication channel." >&2
    return 1
  fi
}

if [[ "$stable_channels" == true ]]; then
  if [[ "$PUBLISH_HOMEBREW" == true || "$PUBLISH_SCOOP" == true || "$PUBLISH_WINGET" == true || "$PUBLISH_NIXPKGS" == true ]]; then
    require_secret "$PACKAGE_REPOSITORY_TOKEN" PACKAGE_REPOSITORY_TOKEN
  fi
  if [[ "$PUBLISH_HOMEBREW" == true && -n "$BREW_CASK_PATH" && -z "$BREW_CASK_TAP_REPO" ]]; then
    echo '::error::brew_cask_tap_repo is required to publish a supplied cask.' >&2
    exit 1
  fi
  if [[ "$PUBLISH_SCOOP" == true && -z "$SCOOP_BUCKET_REPO" ]]; then
    echo '::error::scoop_bucket_repo is required to publish a supplied manifest.' >&2
    exit 1
  fi
  if [[ "$PUBLISH_CHOCOLATEY" == true ]]; then
    require_secret "$CHOCOLATEY_API_KEY" CHOCOLATEY_API_KEY
  fi
  if [[ "$PUBLISH_AUR" == true ]]; then
    require_secret "$AUR_SSH_PRIVATE_KEY" AUR_SSH_PRIVATE_KEY
    if [[ -z "$AUR_PACKAGE_BASE" || -z "$AUR_PKGBUILD_PATH" || -z "$AUR_SRCINFO_PATH" ]]; then
      echo '::error::AUR publication needs a package base, PKGBUILD path, and .SRCINFO path.' >&2
      exit 1
    fi
  fi
fi

if [[ "$PUBLISH_DOCKER_HUB" == true ]]; then
  require_secret "$DOCKERHUB_USERNAME" DOCKERHUB_USERNAME
  require_secret "$DOCKERHUB_TOKEN" DOCKERHUB_TOKEN
fi
