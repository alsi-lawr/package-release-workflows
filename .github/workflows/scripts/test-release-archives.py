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

    def test_duplicate_or_unsupported_rids_fail_before_archive_work(self):
        for matrix in ([{"rid": "linux-x64"}, {"rid": "linux-x64"}], [{"rid": "osx-x64"}]):
            with self.subTest(matrix=matrix), self.assertRaises(ValueError):
                list(archives.entries(json.dumps(matrix), "sample"))


if __name__ == "__main__":
    unittest.main()
