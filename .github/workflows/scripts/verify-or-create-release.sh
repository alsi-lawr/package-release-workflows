#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?Missing GH_TOKEN}"
: "${GITHUB_REPOSITORY:?Missing GITHUB_REPOSITORY}"
: "${RUNNER_TEMP:?Missing RUNNER_TEMP}"
: "${VERSION:?Missing VERSION}"
: "${RELEASE_TITLE_PREFIX:?Missing RELEASE_TITLE_PREFIX}"
: "${PUBLISH_GITHUB_RELEASE:?Missing PUBLISH_GITHUB_RELEASE}"

assets_directory="${RELEASE_ASSETS_DIRECTORY:-artifacts/release}"
mapfile -d '' assembled_assets < <(find "$assets_directory" -maxdepth 1 -type f -print0 | sort -z)
if [ "${#assembled_assets[@]}" -eq 0 ]; then
  echo '::error::No assembled release assets were downloaded.' >&2
  exit 1
fi

asset_manifest() {
  local directory="$1"
  local output="$2"
  (
    cd "$directory"
    while IFS= read -r -d '' asset; do
      printf '%s  %s\n' "$(sha256sum -- "$asset" | cut -d ' ' -f 1)" "$asset"
    done < <(find . -maxdepth 1 -type f -printf '%P\0' | sort -z)
  ) >"$output"
}

tag="v$VERSION"
release_metadata="$RUNNER_TEMP/release-metadata.json"
if gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json assets,isDraft >"$release_metadata" 2>/dev/null; then
  if [ "$(jq -r '.isDraft' "$release_metadata")" != false ]; then
    echo "::error::Release $tag exists as a draft; refusing to replace or publish it." >&2
    exit 1
  fi

  existing_directory="$RUNNER_TEMP/existing-release-assets"
  mkdir -p "$existing_directory"
  if [ "$(jq '.assets | length' "$release_metadata")" -gt 0 ]; then
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --dir "$existing_directory"
  fi

  assembled_manifest="$RUNNER_TEMP/assembled-release-assets.sha256"
  existing_manifest="$RUNNER_TEMP/existing-release-assets.sha256"
  asset_manifest "$assets_directory" "$assembled_manifest"
  asset_manifest "$existing_directory" "$existing_manifest"
  if ! diff -u "$existing_manifest" "$assembled_manifest"; then
    echo "::error::Release $tag exists, but its final assets do not exactly match the assembled assets." >&2
    exit 1
  fi

  echo "Release $tag already exists with exactly matching final assets; leaving it unchanged."
  exit 0
fi

if [ "$PUBLISH_GITHUB_RELEASE" != true ]; then
  echo "::error::Release $tag does not exist and publish_github_release is disabled." >&2
  exit 1
fi

gh release create "$tag" "${assembled_assets[@]}" \
  --repo "$GITHUB_REPOSITORY" \
  --verify-tag \
  --title "${RELEASE_TITLE_PREFIX} v${VERSION}" \
  --generate-notes \
  --latest=false
