#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?Missing GH_TOKEN}"
: "${GITHUB_WORKSPACE:?Missing GITHUB_WORKSPACE}"
: "${CASK_PATH:?Missing CASK_PATH}"
: "${TAP_REPO:?Missing TAP_REPO}"
: "${PACKAGE_NAME:?Missing PACKAGE_NAME}"
: "${VERSION:?Missing VERSION}"

if [[ ! "$TAP_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo '::error::Tap repository must be owner/repository.' >&2
  exit 1
fi
case "$CASK_PATH" in
  artifacts/release/*) ;;
  *) echo '::error::Supplied cask must be a release asset.' >&2; exit 1 ;;
esac
cask="$(realpath --canonicalize-existing -- "$GITHUB_WORKSPACE/$CASK_PATH")"
if [[ "$cask" != "$GITHUB_WORKSPACE/artifacts/release/"* || "$(basename "$cask")" != "$PACKAGE_NAME.rb" ]]; then
  echo '::error::Supplied cask path does not match the selected package.' >&2
  exit 1
fi
(
  cd "$GITHUB_WORKSPACE/artifacts/release"
  sha256sum --check checksums_sha256.txt
)

branch="$(gh api "repos/$TAP_REPO" --jq .default_branch)"
if [ -z "$branch" ]; then
  echo "::error::Could not read the default branch of $TAP_REPO." >&2
  exit 1
fi

mkdir -p "$GITHUB_WORKSPACE/.agent-workspace"
work_directory="$(mktemp -d "$GITHUB_WORKSPACE/.agent-workspace/cask-publish.XXXXXXXX")"
trap 'rm -rf "$work_directory"' EXIT
git clone --depth 1 --single-branch --branch "$branch" \
  "https://x-access-token:${GH_TOKEN}@github.com/${TAP_REPO}.git" \
  "$work_directory/tap"
cd "$work_directory/tap"
mkdir -p Casks
cp -- "$cask" "Casks/$PACKAGE_NAME.rb"
git add -- "Casks/$PACKAGE_NAME.rb"
if git diff --cached --quiet; then
  echo "Linux cask v$VERSION is already current in $TAP_REPO."
  exit 0
fi
git -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -m "Update $PACKAGE_NAME Linux cask to v$VERSION"
git push origin "$branch"
echo "Linux cask v$VERSION was pushed to $TAP_REPO:$branch."
