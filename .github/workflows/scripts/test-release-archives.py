import importlib.util
import io
import json
import stat
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("release-archives.py")
spec = importlib.util.spec_from_file_location("release_archives", MODULE_PATH)
archives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archives)


class ReleaseArchiveTests(unittest.TestCase):
    def test_desktop_children_regain_executable_modes_after_artifact_transfer(self):
        paths = ("bin/modconductor", "app/modconductor/mod_conductor", "app/modconductor/engine/ModConductor.Engine", "app/modconductor/engine/modconductor-loot-helper")
        matrix = list(archives.entries(json.dumps([{
            "rid": "linux-x64", "publish_executable": paths[0],
            "publish_executables": list(paths[1:]),
        }]), "modconductor"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            publish = root / "publish/linux-x64"
            for name in paths:
                path = publish / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
                path.chmod(0o644)

            archives.restore(root / "publish", matrix)
            self.assertTrue(all((publish / name).stat().st_mode & stat.S_IXUSR for name in paths))

            release = root / "release"
            release.mkdir()
            archive = release / "ModConductor-1.0.0-linux-x64.tar.gz"
            with tarfile.open(archive, "w:gz") as file:
                for name in paths:
                    file.add(publish / name, arcname=f"ModConductor/{name}")
            archives.verify(release, matrix)

            (publish / paths[-1]).chmod(0o644)
            with tarfile.open(archive, "w:gz") as file:
                for name in paths:
                    file.add(publish / name, arcname=f"ModConductor/{name}")
            with self.assertRaisesRegex(ValueError, "not executable"):
                archives.verify(release, matrix)

    def test_selected_windows_and_linux_payloads_without_other_architectures(self):
        matrix = list(archives.entries(json.dumps([
            {"rid": "linux-x64", "publish_executable": "bundle/ModConductor"},
            {"rid": "win-x64", "archive_executable": "ModConductor/ModConductor.exe"},
        ]), "modconductor"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            publish = root / "publish"
            executable = publish / "linux-x64/bundle/ModConductor"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b"launcher")
            archives.restore(publish, matrix)
            self.assertTrue(executable.stat().st_mode & stat.S_IXUSR)

            release = root / "release"
            release.mkdir()
            with tarfile.open(release / "modconductor-v1.0.0-linux-x64.tar.gz", "w:gz") as file:
                info = tarfile.TarInfo("modconductor/bin/modconductor")
                info.mode = 0o755
                info.size = len(b"launcher")
                file.addfile(info, io.BytesIO(b"launcher"))
            with zipfile.ZipFile(release / "modconductor-v1.0.0-win-x64.zip", "w") as file:
                file.writestr("ModConductor/ModConductor.exe", b"desktop")
            archives.verify(release, matrix)

            with tarfile.open(release / "modconductor-v1.0.0-linux-x64.tar.gz", "w:gz") as file:
                info = tarfile.TarInfo("modconductor/bin/modconductor")
                info.mode = 0o644
                info.size = len(b"launcher")
                file.addfile(info, io.BytesIO(b"launcher"))
            with self.assertRaisesRegex(ValueError, "not executable"):
                archives.verify(release, matrix)

    def test_windows_archive_children_can_have_different_paths_from_publish_payload(self):
        matrix = list(archives.entries(json.dumps([{
            "rid": "win-x64",
            "publish_executable": "payload/mod_conductor.exe",
            "archive_executable": "mod_conductor.exe",
            "publish_executables": ["payload/engine/ModConductor.Engine.exe"],
            "archive_executables": ["engine/ModConductor.Engine.exe"],
        }]), "modconductor"))
        with tempfile.TemporaryDirectory() as directory:
            release = Path(directory)
            archive = release / "modconductor-v1.0.0-win-x64.zip"
            with zipfile.ZipFile(archive, "w") as file:
                file.writestr("modconductor/mod_conductor.exe", b"desktop")
                file.writestr("modconductor/engine/ModConductor.Engine.exe", b"engine")
            archives.verify(release, matrix)

    def test_duplicate_or_unsupported_rids_fail_before_archive_work(self):
        for matrix in ([{"rid": "linux-x64"}, {"rid": "linux-x64"}], [{"rid": "osx-x64"}]):
            with self.subTest(matrix=matrix), self.assertRaises(ValueError):
                list(archives.entries(json.dumps(matrix), "sample"))


if __name__ == "__main__":
    unittest.main()
