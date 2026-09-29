#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?Missing GITHUB_WORKSPACE}"
: "${VERSION:?Missing VERSION}"
: "${CASK_PATH:?Missing CASK_PATH}"
: "${SMOKE_SCRIPT:?Missing SMOKE_SCRIPT}"

cask="$GITHUB_WORKSPACE/$CASK_PATH"
smoke="$GITHUB_WORKSPACE/$SMOKE_SCRIPT.sh"
test -f "$cask" || { echo "::error::Linux cask not found: $CASK_PATH" >&2; exit 1; }
test -f "$smoke" || { echo "::error::AppImage smoke script not found: $SMOKE_SCRIPT" >&2; exit 1; }
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
bash "$smoke" "$installed" --version "$VERSION" --appimage --close-window
brew uninstall --cask --appimagedir="$appdir" "$tap/$name"
test ! -e "$installed"
