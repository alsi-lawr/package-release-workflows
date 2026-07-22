#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?Missing GH_TOKEN}"
: "${GITHUB_WORKSPACE:?Missing GITHUB_WORKSPACE}"
: "${WINGET_FORK_OWNER:?Missing WINGET_FORK_OWNER}"
: "${WINGET_FORK_REPO:?Missing WINGET_FORK_REPO}"
: "${WINGET_BRANCH:?Missing WINGET_BRANCH}"
: "${WINGET_MANIFEST_DIRECTORY:?Missing WINGET_MANIFEST_DIRECTORY}"

source_directory="$GITHUB_WORKSPACE/$WINGET_MANIFEST_DIRECTORY"
test -d "$source_directory" || {
  echo "::error::Prepared WinGet manifest directory does not exist: $WINGET_MANIFEST_DIRECTORY" >&2
  exit 1
}

manifest_suffix="${WINGET_MANIFEST_DIRECTORY#*manifests/}"
if [ "$manifest_suffix" = "$WINGET_MANIFEST_DIRECTORY" ]; then
  echo '::error::WinGet manifest directory must contain a manifests/ path segment.' >&2
  exit 1
fi
case "$manifest_suffix" in
  '' | /* | ../* | */../* | */..)
    echo '::error::WinGet manifest destination is unsafe.' >&2
    exit 1
    ;;
esac
destination_directory="manifests/$manifest_suffix"

mapfile -d '' manifest_files < <(
  find "$source_directory" -maxdepth 1 -type f -name '*.yaml' -print0
)
if [ "${#manifest_files[@]}" -ne 3 ]; then
  echo '::error::Expected exactly three prepared WinGet YAML manifests.' >&2
  exit 1
fi

work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

git clone --depth 1 --filter=blob:none --no-checkout --single-branch \
  --branch "$WINGET_BRANCH" \
  "https://x-access-token:${GH_TOKEN}@github.com/${WINGET_FORK_OWNER}/${WINGET_FORK_REPO}.git" \
  "$work_directory/winget-pkgs"
cd "$work_directory/winget-pkgs"
git sparse-checkout init --no-cone
git sparse-checkout set "/$destination_directory/"
git checkout "$WINGET_BRANCH"

mkdir -p "$destination_directory"
find "$destination_directory" -maxdepth 1 -type f -name '*.yaml' -delete
cp -- "${manifest_files[@]}" "$destination_directory/"
chmod 0644 "$destination_directory"/*.yaml
git add -- "$destination_directory"

if git diff --cached --quiet; then
  echo "WinGet manifests are already current on ${WINGET_FORK_OWNER}:${WINGET_BRANCH}."
  exit 0
fi

git -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -m "New version: ${WINGET_BRANCH}"
git push origin "$WINGET_BRANCH"

local_head="$(git rev-parse HEAD)"
remote_head="$(git ls-remote origin "refs/heads/$WINGET_BRANCH" | cut -f 1)"
if [ "$local_head" != "$remote_head" ]; then
  echo '::error::WinGet fork branch did not reach the published commit.' >&2
  exit 1
fi

echo "WinGet manifests are ready on ${WINGET_FORK_OWNER}:${WINGET_BRANCH}."
