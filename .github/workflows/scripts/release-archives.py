#!/usr/bin/env python3
"""Restore publish modes and verify the caller-selected JReleaser archives."""

import argparse
import hashlib
import json
import re
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
        publish_executable = relative_path(entry.get("publish_executable", package_name))
        additional = entry.get("publish_executables", [])
        if not isinstance(additional, list):
            raise ValueError(f"publish_executables must be a list: {additional!r}")
        additional = tuple(relative_path(path) for path in additional)
        if len(set((publish_executable, *additional))) != 1 + len(additional):
            raise ValueError(f"duplicate published executable for {rid}")
        archive_additional = entry.get("archive_executables", entry.get("publish_executables", []))
        if not isinstance(archive_additional, list):
            raise ValueError(f"archive_executables must be a list: {archive_additional!r}")
        archive_additional = tuple(relative_path(path) for path in archive_additional)
        yield (
            rid,
            publish_executable,
            relative_path(entry.get("archive_executable", default_archive_executable)),
            additional,
            archive_additional,
        )


def restore(root, matrix):
    for rid, publish_executable, _, additional, _ in matrix:
        if rid.startswith("win-"):
            continue
        for path in (publish_executable, *additional):
            executable = root / rid / path
            if not executable.is_file():
                raise ValueError(f"missing published executable: {executable}")
            executable.chmod(executable.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def archive_members(archive, extension):
    if extension == "tar.gz":
        with tarfile.open(archive, "r:gz") as file:
            return [(member.name, member.isfile(), bool(member.mode & 0o111)) for member in file]
    with zipfile.ZipFile(archive) as file:
        return [(member.filename, not member.is_dir(), True) for member in file.infolist()]


def source_archive_name(template, package_name, version):
    name = template.replace("{package_name}", package_name).replace("{version}", version)
    if not version or not re.fullmatch(r"[A-Za-z0-9._-]+\.tar\.gz", name) or "{" in name or "}" in name:
        raise ValueError(f"invalid source archive template: {template!r}")
    return name


def verify_source_archive(root, name, revision):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"expected a 40-character source revision: {revision!r}")
    source = root / name
    if not source.is_file():
        raise ValueError(f"missing source archive: {source}")
    with tarfile.open(source, "r:gz") as file:
        markers = [member for member in file if member.isfile() and PurePosixPath(member.name).name == "SOURCE-REVISION"]
        if len(markers) != 1:
            raise ValueError(f"expected one SOURCE-REVISION in {source}, found {len(markers)}")
        actual_revision = file.extractfile(markers[0]).read().decode("ascii").strip()
        if actual_revision != revision:
            raise ValueError(f"source revision {actual_revision} does not match {revision}")
    checksums = root / "checksums_sha256.txt"
    if not checksums.is_file():
        raise ValueError(f"missing release checksums: {checksums}")
    digest_lines = [line for line in checksums.read_text().splitlines()
                    if re.fullmatch(rf"[0-9a-fA-F]{{64}}  \*?{re.escape(name)}", line)]
    if len(digest_lines) != 1:
        raise ValueError(f"expected one checksum for {name}, found {len(digest_lines)}")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != digest_lines[0][:64].lower():
        raise ValueError(f"source archive checksum does not match: {name}")


def verify(root, matrix, source_name="", revision=""):
    archives = [
        path for path in root.iterdir()
        if path.is_file() and path.name != source_name
        and (path.name.endswith(".tar.gz") or path.suffix == ".zip")
    ]
    if len(archives) != len(matrix):
        raise ValueError(f"expected {len(matrix)} release archives, found {len(archives)}")
    for rid, _, executable, _, additional in matrix:
        extension = FORMATS[rid]
        matches = list(root.glob(f"*-{rid}.{extension}"))
        if len(matches) != 1:
            raise ValueError(f"expected one {rid}.{extension} archive, found {len(matches)}")
        archive = archive_members(matches[0], extension)
        for path in (executable, *additional):
            parts = path.parts
            members = [
                (name, is_file, is_executable)
                for name, is_file, is_executable in archive
                if tuple(PurePosixPath(name).parts[-len(parts):]) == parts and is_file
            ]
            if len(members) != 1:
                raise ValueError(f"expected one {path} in {matches[0]}, found {len(members)}")
            if extension != "zip" and not members[0][2]:
                raise ValueError(f"{members[0][0]} is not executable in {matches[0]}")
    if source_name:
        verify_source_archive(root, source_name, revision)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("restore", "verify"))
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source-archive-template", default="")
    parser.add_argument("--version", default="")
    parser.add_argument("--revision", default="")
    args = parser.parse_args()
    matrix = list(entries(args.matrix, args.package_name))
    if args.phase == "restore":
        restore(args.root, matrix)
    else:
        source_name = (source_archive_name(args.source_archive_template, args.package_name, args.version)
                       if args.source_archive_template else "")
        verify(args.root, matrix, source_name, args.revision)


if __name__ == "__main__":
    main()
