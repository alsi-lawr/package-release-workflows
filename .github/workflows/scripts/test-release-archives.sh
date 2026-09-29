#!/usr/bin/env bash
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/release-archives.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/publish/linux-x64/bin" "$work/release/sample/bin"
matrix='[{"rid":"linux-x64","publish_executable":"bin/sample","archive_executable":"bin/sample"}]'
printf 'binary' > "$work/publish/linux-x64/bin/sample"
chmod 644 "$work/publish/linux-x64/bin/sample"
bash "$script" restore --matrix "$matrix" --package-name sample --root "$work/publish"
[[ -x $work/publish/linux-x64/bin/sample ]]
cp "$work/publish/linux-x64/bin/sample" "$work/release/sample/bin/sample"
(cd "$work/release" && tar -czf sample-v1.0.0-linux-x64.tar.gz sample && rm -rf sample)
bash "$script" verify --matrix "$matrix" --package-name sample --root "$work/release"
mkdir -p "$work/release/sample/bin"
printf binary > "$work/release/sample/bin/sample"
chmod 644 "$work/release/sample/bin/sample"
(cd "$work/release" && tar -czf sample-v1.0.0-linux-x64.tar.gz sample && rm -rf sample)
if bash "$script" verify --matrix "$matrix" --package-name sample --root "$work/release"; then
  echo "Archive without executable mode passed" >&2
  exit 1
fi
revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$work/release/source"
printf '%s\n' "$revision" > "$work/release/source/SOURCE-REVISION"
(cd "$work/release" && tar -czf sample-v1.0.0-source.tar.gz source && rm -rf source)
(cd "$work/release" && sha256sum sample-v1.0.0-source.tar.gz > checksums_sha256.txt)
chmod 755 "$work/publish/linux-x64/bin/sample"
mkdir -p "$work/release/sample/bin"
cp "$work/publish/linux-x64/bin/sample" "$work/release/sample/bin/sample"
(cd "$work/release" && tar -czf sample-v1.0.0-linux-x64.tar.gz sample && rm -rf sample)
bash "$script" verify --matrix "$matrix" --package-name sample --root "$work/release" \
  --source-archive-template '{package_name}-v{version}-source.tar.gz' --version 1.0.0 --revision "$revision"
if bash "$script" verify --matrix "$matrix" --package-name sample --root "$work/release" \
  --source-archive-template '{package_name}-v{version}-source.tar.gz' --version 1.0.0 --revision bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; then
  echo "Wrong source revision passed" >&2
  exit 1
fi
