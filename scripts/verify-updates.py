#!/usr/bin/env python3
"""Verify real Sparkle updates in disposable apps with a disposable signing key.

Failure cases: invalid feed signature, changed archive, unavailable feed,
current version, skipped update, lost preferences, failed replacement/relaunch.
No production Keychain key, app, account, or launch agent is used.
"""
import argparse
import functools
import http.server
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/Peek for Codex.app')
    parser.add_argument('--sdk', type=Path, default=ROOT / '.build/artifacts/sparkle/Sparkle')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/updates')
    parser.add_argument('--signed-install', action='store_true', help='Test one install between Developer ID signed, notarized fixtures')
    parser.add_argument('--signing-identity')
    parser.add_argument('--notary-profile')
    args = parser.parse_args()
    if args.signed_install and not (args.signing_identity and args.notary_profile):
        parser.error('--signed-install requires --signing-identity and --notary-profile, and a signed --app')
    args.output.mkdir(parents=True, exist_ok=True)
    sdk = args.sdk.resolve()
    framework_parent = sdk / 'Sparkle.xcframework/macos-arm64_x86_64'
    result = {}

    def run(command, **kwargs):
        completed = subprocess.run([str(arg) for arg in command], capture_output=True, text=True, timeout=120, **kwargs)
        with (args.output / 'commands.log').open('a') as log:
            log.write(json.dumps([str(arg) for arg in command]) + '\n' + completed.stdout + completed.stderr)
        completed.check_returncode()
        return completed.stdout

    # TemporaryDirectory deletes only this run's exact task-created /tmp tree.
    with tempfile.TemporaryDirectory(prefix='peek-update-e2e-', dir='/tmp') as directory:
        work = Path(directory)
        key = work / 'fixture-key'
        key.touch(mode=0o600)
        # This creates an ephemeral test seed in a file, never in the user's Keychain.
        public = run(['xcrun', 'swift', '-e', 'import CryptoKit; import Foundation; let k = Curve25519.Signing.PrivateKey(); try k.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: false, encoding: .utf8); print(k.publicKey.rawRepresentation.base64EncodedString())', key]).strip()
        binary = work / 'UpdateVerification'
        run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Sparkle', '-F', framework_parent,
             '-Wl,-rpath,@executable_path/../Frameworks', ROOT / 'Support/UpdateVerification.m', '-o', binary])

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *unused): pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(work)))
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            cases = ['install'] if args.signed_install else ['install', 'tampered-feed', 'tampered-archive', 'unavailable', 'current', 'skip']
            for case in cases:
                case_dir = work / case
                case_dir.mkdir()
                report = case_dir / 'events.jsonl'
                report.touch()
                bundle_id = 'me.peek.verification.' + uuid.uuid4().hex
                url = f'http://127.0.0.1:{server.server_port}/{case}/'
                app = case_dir / 'installed/Peek for Codex.app'
                shutil.copytree(args.app, app, symlinks=True)
                executable = app / 'Contents/MacOS/PeekForCodex'
                shutil.copy2(binary, executable)
                plist_path = app / 'Contents/Info.plist'
                plist = plistlib.loads(plist_path.read_bytes())
                plist.update(CFBundleIdentifier=bundle_id, CFBundleVersion='1', SUPublicEDKey=public,
                    SUFeedURL=url + ('missing.xml' if case == 'unavailable' else 'appcast.xml'),
                    SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
                    SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                    SUSignedFeedFailureExpirationInterval=0,
                    NSAppTransportSecurity={'NSAllowsLocalNetworking': True},
                    PeekVerificationReport=str(report), PeekVerificationCase=case)
                plist_path.write_bytes(plistlib.dumps(plist))
                signing = ['--sign', args.signing_identity, '--options', 'runtime', '--timestamp'] if args.signed_install else ['--sign', '-']
                run(['codesign', '--force', *signing, app])
                newer = case_dir / 'new/Peek for Codex.app'
                shutil.copytree(app, newer, symlinks=True)
                plist['CFBundleVersion'] = '1' if case == 'current' else '2'
                (newer / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
                run(['codesign', '--force', *signing, newer])
                if args.signed_install:
                    notarization = work / 'fixtures-for-notarization.zip'
                    run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', case_dir, notarization])
                    response = run(['xcrun', 'notarytool', 'submit', notarization, '--keychain-profile',
                                    args.notary_profile, '--wait', '--output-format', 'json'])
                    receipt = json.loads(response)
                    (args.output / 'notarization-result.json').write_text(json.dumps(receipt, indent=2) + '\n')
                    assert receipt['status'] == 'Accepted', receipt
                    for bundle in [app, newer]:
                        run(['xcrun', 'stapler', 'staple', bundle])
                        run(['xcrun', 'stapler', 'validate', bundle])
                        run(['spctl', '--assess', '--type', 'execute', bundle])
                archive = case_dir / 'Peek-update.zip'
                run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', newer, archive])
                run([sdk / 'bin/generate_appcast', '--ed-key-file', key,
                     '--download-url-prefix', url, '--maximum-deltas', '0', '-o', case_dir / 'appcast.xml', case_dir])
                feed = case_dir / 'appcast.xml'
                root = ET.fromstring(feed.read_bytes())
                enclosure = root.find('./channel/item/enclosure')
                assert enclosure is not None and enclosure.attrib[NS + 'edSignature']
                verify_command = ['xcrun', 'swift', ROOT / 'Support/VerifyUpdateSignatures.swift', newer, feed, archive, url + archive.name]
                run(verify_command)
                if case == 'tampered-feed':
                    feed.write_bytes(feed.read_bytes().replace(b'<title>', b'<title>Changed '))
                if case == 'tampered-archive':
                    data = bytearray(archive.read_bytes()); data[len(data)//2] ^= 1; archive.write_bytes(data)
                if case in ['tampered-feed', 'tampered-archive']:
                    rejected = subprocess.run([str(arg) for arg in verify_command], capture_output=True, text=True, timeout=30)
                    assert rejected.returncode != 0, 'Release signature check accepted altered bytes'
                    with (args.output / 'commands.log').open('a') as log: log.write(rejected.stderr)
                if case == 'unavailable':
                    feed.rename(case_dir / 'hidden-feed.xml')
                helper = subprocess.Popen([str(executable)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                try:
                    deadline = time.monotonic() + 45
                    while time.monotonic() < deadline:
                        events = [json.loads(line) for line in report.read_text().splitlines()]
                        names = [event['event'] for event in events]
                        if 'relaunched' in names or helper.poll() is not None:
                            if case != 'install' or 'relaunched' in names: break
                        time.sleep(.1)
                    events = [json.loads(line) for line in report.read_text().splitlines()]
                    names = [event['event'] for event in events]
                    installed_version = plistlib.loads(plist_path.read_bytes())['CFBundleVersion']
                    if case == 'install':
                        assert installed_version == '2' and 'relaunched' in names, (case, events)
                        assert next(event['detail'] for event in events if event['event']=='relaunched') == 'preserved'
                    else:
                        assert installed_version == '1' and 'installing' not in names, (case, events)
                        expected = 'skipped' if case == 'skip' else 'no-update' if case == 'current' else 'error'
                        assert expected in names, (case, events)
                    result[case] = {'status': 'passed', 'installedVersion': installed_version,
                                    'developerIDSignedAndNotarized': args.signed_install, 'events': events}
                finally:
                    if helper.poll() is None: helper.terminate()
                    helper.wait(timeout=5)
                    run(['defaults', 'delete', bundle_id])
                    cache = Path.home() / 'Library/Caches' / bundle_id
                    if cache.exists():
                        trash = Path.home() / '.Trash'
                        trash.mkdir(exist_ok=True)
                        shutil.move(str(cache), str(trash / bundle_id))
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=5)
    (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'{len(result)} Sparkle update workflows passed. Report: {args.output / "result.json"}')


if __name__ == '__main__':
    main()
