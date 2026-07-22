#!/usr/bin/env bash
set -euo pipefail

if test -z "$GH_TOKEN"; then
  echo '::error::PACKAGE_REPOSITORY_TOKEN is required for nixpkgs publication.' >&2
  exit 1
fi
if test -z "$NIX_BRANCH"; then
  echo '::error::Nix branch was not prepared; cannot push metadata.' >&2
  exit 1
fi

git clone --depth 1 --filter=blob:none --single-branch --branch "$NIX_BRANCH" \
  "https://x-access-token:${GH_TOKEN}@github.com/${NIX_FORK_OWNER}/${NIX_FORK_REPO}.git" nixpkgs
cd nixpkgs
git checkout "$NIX_BRANCH"

if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "https://github.com/$NIX_UPSTREAM.git"
else
  git remote add upstream "https://github.com/$NIX_UPSTREAM.git"
fi

if [[ ! "$NIX_PACKAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]+$ ]]; then
  echo "::error::Nix package name '$NIX_PACKAGE' cannot be mapped safely into pkgs/by-name." >&2
  exit 1
fi

package_exists="$(nix eval --impure --json --expr "builtins.hasAttr \"$NIX_PACKAGE\" (import ./. {})")"
change_kind=update
if [ "$package_exists" = true ]; then
  if ! current_version="$(nix eval --impure --raw ".#legacyPackages.x86_64-linux.${NIX_PACKAGE}.version")"; then
    echo "::error::${NIX_PACKAGE} exists, but its version cannot be evaluated." >&2
    exit 1
  fi

  if [ "$current_version" = "$VERSION" ]; then
    echo "Nix package is already at v${VERSION}; verifying the existing package."
  else
    nix run github:nix-community/nixpkgs-update -- \
      update "${NIX_PACKAGE} ${current_version} ${VERSION}"
  fi
else
  change_kind=add

  resolve_caller_file() {
    local relative_path="$1"
    local description="$2"
    local resolved_path

    if [[ -z "$relative_path" || "$relative_path" = /* ]]; then
      echo "::error::${description} must be a non-empty caller-relative path." >&2
      return 1
    fi

    if ! resolved_path="$(realpath --canonicalize-existing -- "$GITHUB_WORKSPACE/$relative_path")"; then
      echo "::error::${description} does not exist: $relative_path" >&2
      return 1
    fi
    if [[ "$resolved_path" != "$GITHUB_WORKSPACE/"* || ! -f "$resolved_path" ]]; then
      echo "::error::${description} must resolve to a file in the caller checkout: $relative_path" >&2
      return 1
    fi

    printf '%s\n' "$resolved_path"
  }

  template_path="$(resolve_caller_file "$NIX_PACKAGE_TEMPLATE_PATH" nix_package_template_path)"
  dependencies_path="$(resolve_caller_file "$NIX_PACKAGE_DEPENDENCIES_PATH" nix_package_dependencies_path)"
  dependencies_name="$(basename -- "$dependencies_path")"
  if [ "$dependencies_name" = package.nix ]; then
    echo '::error::nix_package_dependencies_path must not be named package.nix.' >&2
    exit 1
  fi

  source_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/archive/refs/tags/v${VERSION}.tar.gz"
  source_hash="$(nix store prefetch-file --json --unpack "$source_url" | jq -er '.hash')"
  if test -z "$source_hash"; then
    echo "::error::Unable to compute the source hash for $source_url." >&2
    exit 1
  fi

  package_prefix="$(printf '%.2s' "$NIX_PACKAGE" | tr '[:upper:]' '[:lower:]')"
  package_directory="pkgs/by-name/${package_prefix}/${NIX_PACKAGE}"
  if [ -e "$package_directory" ]; then
    echo "::error::${NIX_PACKAGE} is absent from the package set, but $package_directory already exists." >&2
    exit 1
  fi
  mkdir -p "$package_directory"

  python3 - "$template_path" "$package_directory/package.nix" "$VERSION" "$source_hash" <<'PY'
from pathlib import Path
import sys

template_path, output_path, version, source_hash = sys.argv[1:]
template = Path(template_path).read_text()
required_placeholders = ("@PACKAGE_VERSION@", "@SOURCE_HASH@")
missing = [placeholder for placeholder in required_placeholders if placeholder not in template]
if missing:
    raise SystemExit(f"template is missing required placeholders: {', '.join(missing)}")

rendered = template.replace("@PACKAGE_VERSION@", version).replace("@SOURCE_HASH@", source_hash)
remaining = [placeholder for placeholder in required_placeholders if placeholder in rendered]
if remaining:
    raise SystemExit(f"template still contains placeholders after rendering: {', '.join(remaining)}")
Path(output_path).write_text(rendered)
PY
  cp -- "$dependencies_path" "$package_directory/$dependencies_name"
  git add -- "$package_directory"
fi

resulting_version="$(nix eval --impure --raw ".#legacyPackages.x86_64-linux.${NIX_PACKAGE}.version")"
if [ "$resulting_version" != "$VERSION" ]; then
  echo "::error::Resulting ${NIX_PACKAGE} version is '$resulting_version', expected '$VERSION'." >&2
  exit 1
fi

nix build --no-link ".#${NIX_PACKAGE}"

if git status --porcelain | grep -q .; then
  git add -A
  if ! git diff --cached --quiet; then
    git -c user.name='github-actions[bot]' \
      -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      commit -m "nixpkgs: ${change_kind} ${NIX_PACKAGE} to v${VERSION}"
  fi
fi

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse "origin/${NIX_BRANCH}")"
if [ "$local_head" = "$remote_head" ]; then
  echo "Nixpkgs already contains a buildable ${NIX_PACKAGE} v${VERSION}; no branch update is required."
  exit 0
fi

git push origin "$NIX_BRANCH"

echo "Nixpkgs metadata is ready for manual upstream PR submission from ${NIX_FORK_OWNER}:${NIX_BRANCH}."
