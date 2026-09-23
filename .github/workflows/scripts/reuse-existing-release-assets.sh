#!/usr/bin/env bash
set -euo pipefail

tag="v$VERSION"
if ! gh release view "$tag" >/dev/null 2>&1; then
  exit 0
fi

release_revision="$(gh api "repos/$GITHUB_REPOSITORY/commits/$tag" --jq .sha)"
if [ "$release_revision" != "$GITHUB_SHA" ]; then
  echo "::error::Release $tag resolves to $release_revision, not $GITHUB_SHA." >&2
  exit 1
fi

release_directory="$(mktemp -d)"
trap 'rm -rf "$release_directory"' EXIT
gh release download "$tag" \
  --dir "$release_directory" \
  --pattern "$PACKAGE_NAME-v$VERSION-*.tar.gz" \
  --pattern "$PACKAGE_NAME-v$VERSION-*.zip" \
  --pattern checksums_sha256.txt
(
  cd "$release_directory"
  sha256sum --check checksums_sha256.txt
)

mapfile -t existing_archives < <(
  find "$release_directory" -maxdepth 1 -type f \
    \( -name '*.tar.gz' -o -name '*.zip' \) -print
)
mapfile -t assembled_archives < <(
  find out/jreleaser/assemble -maxdepth 4 -type f \
    \( -name '*.tar.gz' -o -name '*.zip' \) -print
)
expected_archive_count="$(python3 - <<'PY'
import json
import os
print(len(json.loads(os.environ["PACKAGE_PUBLISH_MATRIX"])))
PY
)"
if [ "${#existing_archives[@]}" -ne "$expected_archive_count" ] || [ "${#assembled_archives[@]}" -ne "$expected_archive_count" ]; then
  echo "::error::Expected ${expected_archive_count} existing and assembled release archives." >&2
  exit 1
fi

for existing_archive in "${existing_archives[@]}"; do
  archive_name="$(basename "$existing_archive")"
  mapfile -t matches < <(
    find out/jreleaser/assemble -maxdepth 4 -type f -name "$archive_name" -print
  )
  if [ "${#matches[@]}" -ne 1 ]; then
    echo "::error::Expected one assembled $archive_name, found ${#matches[@]}." >&2
    exit 1
  fi
  cp "$existing_archive" "${matches[0]}"
done
