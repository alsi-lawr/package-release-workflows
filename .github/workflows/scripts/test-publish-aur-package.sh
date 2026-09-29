#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "$root/.agent-workspace"
work=$(mktemp -d "$root/.agent-workspace/aur-publish-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
remote="$work/remote.git"
workspace="$work/workspace"
mkdir -p "$workspace"
git init --bare --initial-branch=master "$remote" >/dev/null

cat > "$work/PKGBUILD" <<'EOF'
pkgname=sample-bin
pkgver=1.2.3
pkgrel=1
EOF
cat > "$work/.SRCINFO" <<'EOF'
pkgbase = sample-bin
	pkgver = 1.2.3
	pkgname = sample-bin
EOF

run_publish() {
  AUR_PACKAGE_BASE=sample-bin \
  AUR_PKGBUILD="$work/PKGBUILD" \
  AUR_SRCINFO="$work/.SRCINFO" \
  AUR_REMOTE="$remote" \
  GITHUB_WORKSPACE="$workspace" \
  VERSION=1.2.3 \
    bash "$root/.github/workflows/scripts/publish-aur-package.sh"
}

run_publish
[[ $(git --git-dir="$remote" show master:PKGBUILD) == "$(cat "$work/PKGBUILD")" ]]
[[ $(git --git-dir="$remote" show master:.SRCINFO) == "$(cat "$work/.SRCINFO")" ]]
[[ $(git --git-dir="$remote" log -1 --format=%s) == 'chore: publish sample-bin 1.2.3' ]]
first=$(git --git-dir="$remote" rev-parse master)
run_publish
[[ $(git --git-dir="$remote" rev-parse master) == "$first" ]]

sed -i 's/pkgbase = sample-bin/pkgbase = another-package/' "$work/.SRCINFO"
if run_publish >/dev/null 2>&1; then
  echo 'Mismatched pkgbase was accepted.' >&2
  exit 1
fi
[[ $(git --git-dir="$remote" rev-parse master) == "$first" ]]
