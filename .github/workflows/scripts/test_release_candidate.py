import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent

GH_STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
state = json.loads(pathlib.Path(os.environ['GH_STATE']).read_text())
with open(os.environ['GH_CALLS'], 'a') as log:
    log.write(json.dumps(args) + '\n')
if args[0] == 'api':
    if '--include' not in args:
        print(state['revision'])
        sys.exit(0)
    endpoint = args[-1]
    latest = endpoint.endswith('/latest')
    status = state['latest_status' if latest else 'tag_status']
    if status == 'network':
        sys.exit(1)
    print(f'HTTP/2.0 {status} Status\r\nContent-Type: application/json\r\n\r\n', end='')
    body = state['latest' if latest else 'metadata']
    print(body if isinstance(body, str) else json.dumps(body))
    sys.exit(0 if status == 200 else 1)
if args[:2] == ['release', 'view']:
    if state['tag_status'] != 200:
        sys.exit(1)
    print(json.dumps({'isDraft': state['metadata']['draft'], 'assets': state['metadata']['assets']}))
elif args[:2] == ['release', 'download']:
    destination = pathlib.Path(args[args.index('--dir') + 1])
    destination.mkdir(parents=True, exist_ok=True)
    for path in pathlib.Path(os.environ['GH_ASSETS']).iterdir():
        shutil.copyfile(path, destination / path.name)
elif args[:2] != ['release', 'create']:
    sys.exit('Unexpected gh call: ' + repr(args))
'''


class CandidateReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        stub = self.bin / 'gh'
        stub.write_text(GH_STUB)
        stub.chmod(0o755)
        self.assets = self.root / 'existing'
        self.assets.mkdir()
        self.assembled = self.root / 'artifacts/release'
        self.assembled.mkdir(parents=True)
        self.archive = self.root / 'out/jreleaser/assemble/sample/archive'
        self.archive.mkdir(parents=True)
        self.version = '0.18.0-rc.1'
        self.state = {
            'tag_status': 200,
            'latest_status': 200,
            'revision': '1234567890abcdef',
            'metadata': {'tag_name': 'v' + self.version, 'draft': False, 'prerelease': True, 'assets': [{'name': 'archive'}]},
            'latest': {'tag_name': 'v0.17.0'},
        }
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        GH_STATE=str(self.root / 'state.json'), GH_CALLS=str(self.root / 'calls.jsonl'),
                        GH_ASSETS=str(self.assets), GH_TOKEN='fixture', GITHUB_REPOSITORY='owner/sample',
                        RUNNER_TEMP=str(self.root), VERSION=self.version, PUBLISH_GITHUB_RELEASE='true',
                        RELEASE_TITLE_PREFIX='Sample', GITHUB_SHA=self.state['revision'],
                        GITHUB_OUTPUT=str(self.root / 'output'), PACKAGE_NAME='sample',
                        PACKAGE_PUBLISH_MATRIX='[{"rid":"linux-x64"}]')
        self.seed_assets(self.version)

    def seed_assets(self, version):
        for directory in (self.assets, self.assembled, self.archive):
            for path in directory.iterdir():
                path.unlink()
        name = f'sample-v{version}-linux-x64.tar.gz'
        for directory in (self.assets, self.assembled, self.archive):
            (directory / name).write_bytes(b'immutable archive fixture')
        checksum = subprocess.check_output(['sha256sum', name], cwd=self.assets)
        for directory in (self.assets, self.assembled):
            (directory / 'checksums_sha256.txt').write_bytes(checksum)

    def run_script(self, name):
        (self.root / 'state.json').write_text(json.dumps(self.state))
        return subprocess.run(['bash', str(SCRIPTS / name)], cwd=self.root, env=self.env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def calls(self):
        path = self.root / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_no_mutation(self):
        self.assertFalse(any(call[:2] in (['release', 'create'], ['release', 'edit'], ['release', 'upload']) for call in self.calls()))

    def test_new_candidate_creation_is_prerelease_and_nonlatest(self):
        self.state['tag_status'] = 404
        result = self.run_script('verify-or-create-release.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(call for call in self.calls() if call[:2] == ['release', 'create'])
        self.assertIn('--prerelease', create)
        self.assertIn('--latest=false', create)
        self.assertIn('v' + self.version, create)

    def test_matching_candidate_is_reused_at_both_boundaries_without_publication(self):
        for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
            with self.subTest(script=script):
                result = self.run_script(script)
                self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_no_mutation()

    def test_metadata_mismatches_fail_before_download_or_publication_at_both_boundaries(self):
        for field, value in (('prerelease', False), ('draft', True), ('tag_name', 'v0.17.0')):
            for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
                with self.subTest(field=field, script=script):
                    old = self.state['metadata'][field]
                    self.state['metadata'][field] = value
                    result = self.run_script(script)
                    self.state['metadata'][field] = old
                    self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:2] == ['release', 'download'] for call in self.calls()))
        self.assert_no_mutation()

    def test_latest_candidate_is_rejected_even_with_identical_assets(self):
        self.state['latest']['tag_name'] = 'v' + self.version
        for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
            result = self.run_script(script)
            self.assertNotEqual(result.returncode, 0)
        self.assert_no_mutation()

    def test_api_errors_never_mean_absence_or_nonlatest(self):
        for field in ('tag_status', 'latest_status'):
            for status in (401, 403, 500, 'network'):
                for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
                    with self.subTest(field=field, status=status, script=script):
                        self.state[field] = status
                        result = self.run_script(script)
                        self.assertNotEqual(result.returncode, 0)
                self.state[field] = 200
        self.assert_no_mutation()

    def test_invalid_api_bodies_fail_closed(self):
        for key in ('metadata', 'latest'):
            original = self.state[key]
            for body in ('not json', '', {}, {'tag_name': None}):
                self.state[key] = body
                for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
                    result = self.run_script(script)
                    self.assertNotEqual(result.returncode, 0)
            self.state[key] = original
        self.assert_no_mutation()

    def test_no_latest_release_is_distinct_from_an_api_failure(self):
        self.state['latest_status'] = 404
        for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
            result = self.run_script(script)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_no_mutation()

    def test_late_asset_mismatch_and_early_revision_or_checksum_mismatch_are_rejected(self):
        (self.assembled / 'unexpected').write_bytes(b'not published')
        self.assertNotEqual(self.run_script('verify-or-create-release.sh').returncode, 0)
        self.state['revision'] = 'wrong-revision'
        self.assertNotEqual(self.run_script('reuse-existing-release-assets.sh').returncode, 0)
        self.state['revision'] = self.env['GITHUB_SHA']
        next(self.assets.glob('*.tar.gz')).write_bytes(b'wrong bytes')
        self.assertNotEqual(self.run_script('reuse-existing-release-assets.sh').returncode, 0)
        self.assert_no_mutation()

    def test_stable_creation_and_reuse_keep_existing_semantics(self):
        self.env['VERSION'] = '0.18.0'
        self.seed_assets('0.18.0')
        self.state['metadata'].update(tag_name='v0.18.0', prerelease=False)
        self.state['latest_status'] = 'network'
        for script in ('reuse-existing-release-assets.sh', 'verify-or-create-release.sh'):
            result = self.run_script(script)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_no_mutation()
        self.state['tag_status'] = 404
        result = self.run_script('verify-or-create-release.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(call for call in self.calls() if call[:2] == ['release', 'create'])
        self.assertNotIn('--prerelease', create)
        self.assertIn('--latest=false', create)

    def test_authoritative_tag_derivation_keeps_version_and_revision_together(self):
        self.env.update(GITHUB_REF_TYPE='tag', PACKAGE_VERSION_OVERRIDE='')
        for version in ('0.18.0', '0.18.0-rc.1'):
            self.env['GITHUB_REF_NAME'] = 'v' + version
            result = self.run_script('release-version.sh')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f'version={version}\nrevision={self.env["GITHUB_SHA"]}\n', (self.root / 'output').read_text())
        (self.root / 'output').unlink()
        self.env['PACKAGE_VERSION_OVERRIDE'] = '0.18.0'
        self.assertNotEqual(self.run_script('release-version.sh').returncode, 0)
        self.assertFalse((self.root / 'output').exists())

    def test_candidate_policy_drops_stable_credentials_but_not_docker_credentials(self):
        flags = ('PUBLISH_HOMEBREW', 'PUBLISH_SCOOP', 'PUBLISH_WINGET', 'PUBLISH_NIXPKGS', 'PUBLISH_CHOCOLATEY', 'PUBLISH_AUR')
        self.env.update({flag: 'true' for flag in flags})
        self.env.update({key: '' for key in ('PACKAGE_REPOSITORY_TOKEN', 'CHOCOLATEY_API_KEY', 'AUR_SSH_PRIVATE_KEY', 'BREW_CASK_PATH', 'BREW_CASK_TAP_REPO', 'SCOOP_BUCKET_REPO', 'AUR_PACKAGE_BASE', 'AUR_PKGBUILD_PATH', 'AUR_SRCINFO_PATH', 'DOCKERHUB_USERNAME', 'DOCKERHUB_TOKEN')})
        self.env['PUBLISH_DOCKER_HUB'] = 'false'
        result = self.run_script('release-publication-policy.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'output').read_text(), 'stable_channels=false\n')
        self.env['PUBLISH_DOCKER_HUB'] = 'true'
        self.assertNotEqual(self.run_script('release-publication-policy.sh').returncode, 0)
        self.env.update(DOCKERHUB_USERNAME='fixture', DOCKERHUB_TOKEN='fixture')
        self.assertEqual(self.run_script('release-publication-policy.sh').returncode, 0)
        self.env['VERSION'] = '0.18.0'
        self.assertNotEqual(self.run_script('release-publication-policy.sh').returncode, 0)
        self.env.update(PACKAGE_REPOSITORY_TOKEN='fixture', CHOCOLATEY_API_KEY='fixture', AUR_SSH_PRIVATE_KEY='fixture', SCOOP_BUCKET_REPO='owner/bucket', AUR_PACKAGE_BASE='sample-bin', AUR_PKGBUILD_PATH='PKGBUILD', AUR_SRCINFO_PATH='.SRCINFO')
        result = self.run_script('release-publication-policy.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'output').read_text().endswith('stable_channels=true\n'))


if __name__ == '__main__':
    unittest.main()
