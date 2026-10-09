#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?Missing GITHUB_WORKSPACE}"
: "${VERSION:?Missing VERSION}"
: "${CASK_PATH:?Missing CASK_PATH}"

cask="$GITHUB_WORKSPACE/$CASK_PATH"
test -f "$cask" || { echo "::error::Linux cask not found: $CASK_PATH" >&2; exit 1; }
if [[ "${RUN_RELEASE_SMOKES:-true}" != false ]]; then
  : "${SMOKE_SCRIPT:?Missing SMOKE_SCRIPT}"
  smoke="$GITHUB_WORKSPACE/$SMOKE_SCRIPT.sh"
  test -f "$smoke" || { echo "::error::AppImage smoke script not found: $SMOKE_SCRIPT" >&2; exit 1; }
fi
(
  cd "$GITHUB_WORKSPACE/artifacts/release"
  sha256sum --check checksums_sha256.txt
)

mapfile -t images < <(find "$GITHUB_WORKSPACE/artifacts/release" -maxdepth 1 -type f -name '*.AppImage' -print)
if [ "${#images[@]}" -ne 1 ]; then
  echo '::error::Expected one Linux AppImage release asset.' >&2
  exit 1
fi

name="$(basename "$cask" .rb)"
tap=release-tests/package-smoke
appdir="$GITHUB_WORKSPACE/.agent-workspace/linux-cask-applications"
mkdir -p "$appdir"
brew tap-new "$tap"
tap_directory="$(brew --repository "$tap")"
mkdir -p "$tap_directory/Casks"
cp "$cask" "$tap_directory/Casks/$name.rb"

brew install --cask --appimagedir="$appdir" "$tap/$name"
installed="$appdir/$(basename "${images[0]}")"
test -x "$installed" || { echo '::error::Homebrew did not install the AppImage.' >&2; exit 1; }
if [[ "${RUN_RELEASE_SMOKES:-true}" != false ]]; then
  bash "$smoke" "$installed" --version "$VERSION" --appimage --close-window
else
  echo '::notice::Caller Linux cask installed-package smoke skipped: RUN_RELEASE_SMOKES=false.'
fi
brew uninstall --cask "$tap/$name"
test ! -e "$installed"
