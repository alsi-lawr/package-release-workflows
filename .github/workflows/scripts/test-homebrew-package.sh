#!/usr/bin/env bash
set -euo pipefail

state_directory="$HOME/Library/Application Support/$STATE_DIR_NAME"
mkdir -p "$state_directory"
printf 'preserve\n' > "$state_directory/marker"

formula="$GITHUB_WORKSPACE/$FORMULA_PATH"
tap=release-tests/package-lifecycle
formula_name="$(basename "$formula" .rb)"
brew tap-new "$tap"
tap_directory="$(brew --repository "$tap")"
cp "$formula" "$tap_directory/Formula/$formula_name.rb"

brew install --formula "$tap/$formula_name"
python3 "$SMOKE_SCRIPT" "$(command -v "$COMMAND_NAME")" --version "$VERSION"
brew reinstall --formula "$tap/$formula_name"
test "$(cat "$state_directory/marker")" = preserve
brew uninstall "$tap/$formula_name"
if command -v "$COMMAND_NAME"; then
  exit 1
fi
test "$(cat "$state_directory/marker")" = preserve
brew untap "$tap"
