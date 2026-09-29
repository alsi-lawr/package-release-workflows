#!/usr/bin/env bash
set -euo pipefail

phase=$1
shift
matrix='' package_name='' root='' source_archive_template='' version='' revision=''
while (($#)); do
  case "$1" in
    --matrix) matrix=$2 ;;
    --package-name) package_name=$2 ;;
    --root) root=$2 ;;
    --source-archive-template) source_archive_template=$2 ;;
    --version) version=$2 ;;
    --revision) revision=$2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
[[ $phase == restore || $phase == verify ]] || { echo "Expected restore or verify" >&2; exit 2; }
[[ -n $matrix && -n $package_name && -d $root ]] || { echo "Missing matrix, package name, or root" >&2; exit 2; }
printf '%s' "$matrix" | jq -e 'type == "array" and length > 0 and (map(.rid) | unique | length) == length and all(.[].rid; . == "linux-x64" or . == "linux-arm64" or . == "osx-arm64" or . == "win-x64" or . == "win-arm64")' >/dev/null

source_name=
if [[ -n $source_archive_template ]]; then
  source_name=${source_archive_template//\{package_name\}/$package_name}
  source_name=${source_name//\{version\}/$version}
  [[ $source_name =~ ^[A-Za-z0-9._-]+\.tar\.gz$ && $source_name != *'{'* ]] || { echo "Invalid source archive template" >&2; exit 1; }
fi

if [[ $phase == verify ]]; then
  expected=$(printf '%s' "$matrix" | jq length)
  actual=0
  while IFS= read -r -d '' archive; do
    [[ ${archive##*/} == "$source_name" ]] || ((actual+=1))
  done < <(find "$root" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.zip' \) -print0)
  [[ $actual -eq $expected ]] || { echo "Expected $expected release archives, found $actual" >&2; exit 1; }
fi

while IFS= read -r entry; do
  rid=$(jq -r .rid <<<"$entry")
  extension=zip
  [[ $rid != linux-* ]] || extension=tar.gz
  if [[ $phase == restore ]]; then
    [[ $rid == win-* ]] && continue
    paths=$(jq -r --arg package "$package_name" '.publish_executable // $package, (.publish_executables[]?)' <<<"$entry")
    while IFS= read -r path; do
      [[ -n $path && $path != /* && /$path/ != */../* && /$path/ != */./* ]] || { echo "Invalid executable path: $path" >&2; exit 1; }
      [[ -f $root/$rid/$path ]] || { echo "Missing published executable: $root/$rid/$path" >&2; exit 1; }
      chmod a+x "$root/$rid/$path"
    done <<<"$paths"
    continue
  fi

  mapfile -t matches < <(find "$root" -maxdepth 1 -type f -name "*-$rid.$extension" -print)
  [[ ${#matches[@]} -eq 1 ]] || { echo "Expected one $rid.$extension archive" >&2; exit 1; }
  archive=${matches[0]}
  default="bin/$package_name"
  [[ $rid != win-* ]] || default+=".exe"
  paths=$(jq -r --arg default "$default" '.archive_executable // $default, ((.archive_executables // .publish_executables // [])[]?)' <<<"$entry")
  if [[ $extension == zip ]]; then
    members=$(unzip -Z1 "$archive")
  else
    members=$(tar -tzf "$archive")
  fi
  while IFS= read -r path; do
    [[ -n $path && $path != /* && /$path/ != */../* && /$path/ != */./* ]] || { echo "Invalid archive executable path: $path" >&2; exit 1; }
    mapfile -t found < <(printf '%s\n' "$members" | awk -v path="$path" '$0 == path || (length($0) > length(path) && substr($0, length($0)-length(path), 1) == "/" && substr($0, length($0)-length(path)+1) == path) {print}')
    [[ ${#found[@]} -eq 1 ]] || { echo "Expected one $path in $archive, found ${#found[@]}" >&2; exit 1; }
    if [[ $extension == tar.gz ]]; then
      mode=$(tar -tvzf "$archive" "${found[0]}" | head -1 | cut -c1-10)
      [[ $mode == *x* ]] || { echo "${found[0]} is not executable in $archive" >&2; exit 1; }
    fi
  done <<<"$paths"
done < <(printf '%s' "$matrix" | jq -c '.[]')

if [[ $phase == verify && -n $source_name ]]; then
  [[ $revision =~ ^[0-9a-f]{40}$ ]] || { echo "Expected 40-character source revision" >&2; exit 1; }
  [[ -f $root/$source_name ]] || { echo "Missing source archive: $source_name" >&2; exit 1; }
  mapfile -t markers < <(tar -tzf "$root/$source_name" | awk '$0 == "SOURCE-REVISION" || $0 ~ /\/SOURCE-REVISION$/')
  [[ ${#markers[@]} -eq 1 ]] || { echo "Expected one SOURCE-REVISION" >&2; exit 1; }
  [[ $(tar -xOzf "$root/$source_name" "${markers[0]}" | tr -d '\r\n') == "$revision" ]] || { echo "Source revision does not match" >&2; exit 1; }
  [[ -f $root/checksums_sha256.txt ]] || { echo "Missing release checksums" >&2; exit 1; }
  checksum_line=$(awk -v name="$source_name" '{file=$2; sub(/^\*/, "", file); if (file == name && $1 ~ /^[0-9a-fA-F]{64}$/) print}' "$root/checksums_sha256.txt")
  [[ $(printf '%s\n' "$checksum_line" | grep -c .) -eq 1 ]] || { echo "Expected one source checksum" >&2; exit 1; }
  (cd "$root" && printf '%s\n' "$checksum_line" | sha256sum --check)
fi
