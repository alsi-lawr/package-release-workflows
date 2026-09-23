#!/usr/bin/env python3
"""Restore publish modes and verify the caller-selected JReleaser archives."""

import argparse
import json
import stat
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


FORMATS = {
    "linux-x64": "tar.gz",
    "linux-arm64": "tar.gz",
    "osx-arm64": "zip",
    "win-x64": "zip",
    "win-arm64": "zip",
}


def relative_path(value):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or any(part in (".", "..") for part in value.split("/")):
        raise ValueError(f"expected a relative executable path: {value!r}")
    return path


def entries(raw_matrix, package_name):
    matrix = json.loads(raw_matrix)
    if not isinstance(matrix, list) or not matrix:
        raise ValueError("package_publish_matrix must be a nonempty JSON list")
    seen = set()
    for entry in matrix:
        if not isinstance(entry, dict) or entry.get("rid") not in FORMATS:
            raise ValueError(f"unsupported release RID: {entry!r}")
        rid = entry["rid"]
        if rid in seen:
            raise ValueError(f"duplicate release RID: {rid}")
        seen.add(rid)
        default_archive_executable = f"bin/{package_name}{'.exe' if rid.startswith('win-') else ''}"
        yield (
            rid,
            relative_path(entry.get("publish_executable", package_name)),
            relative_path(entry.get("archive_executable", default_archive_executable)),
        )


def restore(root, matrix):
    for rid, publish_executable, _ in matrix:
        if rid.startswith("win-"):
            continue
        executable = root / rid / publish_executable
        if not executable.is_file():
            raise ValueError(f"missing published executable: {executable}")
        executable.chmod(executable.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def archive_members(archive, extension):
    if extension == "tar.gz":
        with tarfile.open(archive, "r:gz") as file:
            return [(member.name, member.isfile(), bool(member.mode & 0o111)) for member in file]
    with zipfile.ZipFile(archive) as file:
        return [(member.filename, not member.is_dir(), True) for member in file.infolist()]


def verify(root, matrix):
    archives = [
        path for path in root.iterdir()
        if path.is_file() and (path.name.endswith(".tar.gz") or path.suffix == ".zip")
    ]
    if len(archives) != len(matrix):
        raise ValueError(f"expected {len(matrix)} release archives, found {len(archives)}")
    for rid, _, executable in matrix:
        extension = FORMATS[rid]
        matches = list(root.glob(f"*-{rid}.{extension}"))
        if len(matches) != 1:
            raise ValueError(f"expected one {rid}.{extension} archive, found {len(matches)}")
        executable_parts = executable.parts
        members = [
            (name, is_file, is_executable)
            for name, is_file, is_executable in archive_members(matches[0], extension)
            if tuple(PurePosixPath(name).parts[-len(executable_parts):]) == executable_parts and is_file
        ]
        if len(members) != 1:
            raise ValueError(f"expected one {executable} in {matches[0]}, found {len(members)}")
        if extension != "zip" and not members[0][2]:
            raise ValueError(f"{members[0][0]} is not executable in {matches[0]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("restore", "verify"))
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    matrix = list(entries(args.matrix, args.package_name))
    if args.phase == "restore":
        restore(args.root, matrix)
    else:
        verify(args.root, matrix)


if __name__ == "__main__":
    main()
