#!/usr/bin/env bash
set -euo pipefail

: "${AUR_PACKAGE_BASE:?Missing AUR_PACKAGE_BASE}"
: "${AUR_PKGBUILD:?Missing AUR_PKGBUILD}"
: "${AUR_SRCINFO:?Missing AUR_SRCINFO}"
: "${AUR_REMOTE:?Missing AUR_REMOTE}"
: "${GITHUB_WORKSPACE:?Missing GITHUB_WORKSPACE}"
: "${VERSION:?Missing VERSION}"

[[ $AUR_PACKAGE_BASE =~ ^[a-z0-9@._+-]+$ ]] || {
  echo "Invalid AUR package base: $AUR_PACKAGE_BASE" >&2
  exit 2
}
[[ -f $AUR_PKGBUILD ]] || { echo "Missing PKGBUILD: $AUR_PKGBUILD" >&2; exit 2; }
[[ -f $AUR_SRCINFO ]] || { echo "Missing .SRCINFO: $AUR_SRCINFO" >&2; exit 2; }

mapfile -t declared_bases < <(awk '$1 == "pkgbase" && $2 == "=" { print $3 }' "$AUR_SRCINFO")
[[ ${#declared_bases[@]} -eq 1 && ${declared_bases[0]} == "$AUR_PACKAGE_BASE" ]] || {
  echo ".SRCINFO must declare pkgbase = $AUR_PACKAGE_BASE" >&2
  exit 2
}

mkdir -p "$GITHUB_WORKSPACE/.agent-workspace"
work=$(mktemp -d "$GITHUB_WORKSPACE/.agent-workspace/aur-publish.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

git -c init.defaultBranch=master clone "$AUR_REMOTE" "$work/package"
cp "$AUR_PKGBUILD" "$work/package/PKGBUILD"
cp "$AUR_SRCINFO" "$work/package/.SRCINFO"

cd "$work/package"
git add PKGBUILD .SRCINFO
if git diff --cached --quiet; then
  echo "$AUR_PACKAGE_BASE already contains version $VERSION."
  exit 0
fi

git -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -m "chore: publish $AUR_PACKAGE_BASE $VERSION"
git push origin HEAD:master
