#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?Missing GH_TOKEN}"
: "${GITHUB_WORKSPACE:?Missing GITHUB_WORKSPACE}"
: "${MANIFEST_PATH:?Missing MANIFEST_PATH}"
: "${BUCKET_REPO:?Missing BUCKET_REPO}"
: "${PACKAGE_NAME:?Missing PACKAGE_NAME}"
: "${VERSION:?Missing VERSION}"

if [[ ! "$BUCKET_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo '::error::Scoop bucket repository must be owner/repository.' >&2
  exit 1
fi

case "$MANIFEST_PATH" in
  artifacts/package-metadata/*) ;;
  *) echo '::error::Supplied Scoop manifest must be package metadata.' >&2; exit 1 ;;
esac

manifest="$(realpath --canonicalize-existing -- "$GITHUB_WORKSPACE/$MANIFEST_PATH")"
if [[ "$manifest" != "$GITHUB_WORKSPACE/artifacts/package-metadata/"* || "$(basename "$manifest")" != "$PACKAGE_NAME.json" ]]; then
  echo '::error::Supplied Scoop manifest path does not match the selected package.' >&2
  exit 1
fi
if [ "$(jq -r .version "$manifest")" != "$VERSION" ]; then
  echo '::error::Supplied Scoop manifest version does not match the selected release.' >&2
  exit 1
fi

branch="$(gh api "repos/$BUCKET_REPO" --jq .default_branch)"
if [ -z "$branch" ]; then
  echo "::error::Could not read the default branch of $BUCKET_REPO." >&2
  exit 1
fi

mkdir -p "$GITHUB_WORKSPACE/.agent-workspace"
work_directory="$(mktemp -d "$GITHUB_WORKSPACE/.agent-workspace/scoop-publish.XXXXXXXX")"
trap 'rm -rf "$work_directory"' EXIT
git clone --depth 1 --single-branch --branch "$branch" \
  "https://x-access-token:${GH_TOKEN}@github.com/${BUCKET_REPO}.git" \
  "$work_directory/bucket"
cd "$work_directory/bucket"
mkdir -p bucket
cp -- "$manifest" "bucket/$PACKAGE_NAME.json"
git add -- "bucket/$PACKAGE_NAME.json"
if git diff --cached --quiet; then
  echo "$PACKAGE_NAME $VERSION is already current in $BUCKET_REPO."
  exit 0
fi

git -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -m "chore: publish $PACKAGE_NAME $VERSION"
git push origin "$branch"
echo "$PACKAGE_NAME $VERSION was pushed to $BUCKET_REPO:$branch."
