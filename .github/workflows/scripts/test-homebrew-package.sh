#!/usr/bin/env bash
set -euo pipefail

formula="$GITHUB_WORKSPACE/$FORMULA_PATH"
tap=release-tests/package-smoke
formula_name="$(basename "$formula" .rb)"
brew tap-new "$tap"
tap_directory="$(brew --repository "$tap")"
cp "$formula" "$tap_directory/Formula/$formula_name.rb"

brew install --formula "$tap/$formula_name"
python3 "$SMOKE_SCRIPT" "$(command -v "$COMMAND_NAME")" --version "$VERSION"
