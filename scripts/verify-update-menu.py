#!/usr/bin/env python3
"""Dispatch native updater menu actions in a disposable copy of the real app."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/Peek for Codex.app')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/update-menu')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = args.output.resolve() / 'result.json'
    with tempfile.TemporaryDirectory(prefix='peek-update-menu-', dir='/tmp') as temporary:
        app = Path(temporary) / 'Peek for Codex.app'
        shutil.copytree(args.app, app, symlinks=True)
        bundle_id = 'me.peek.verification.' + uuid.uuid4().hex
        plist_path = app / 'Contents/Info.plist'
        plist = plistlib.loads(plist_path.read_bytes())
        plist['CFBundleIdentifier'] = bundle_id
        plist_path.write_bytes(plistlib.dumps(plist))
        sources = [str(path) for path in sorted((ROOT / 'Sources/PeekForCodex').glob('*.swift')) if path.name != 'App.swift']
        framework_parent = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64'
        executable = app / 'Contents/MacOS/PeekForCodex'
        command = ['xcrun', 'swiftc', '-swift-version', '6', '-O', '-parse-as-library', *sources,
            '-F', str(framework_parent), '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker',
            '@executable_path/../Frameworks', str(ROOT / 'Support/MenuUpdateVerification.swift'), '-o', str(executable)]
        try:
            compile = subprocess.run(command, capture_output=True, text=True)
            (args.output / 'commands.log').write_text(json.dumps(command) + '\n' + compile.stdout + compile.stderr)
            compile.check_returncode()
            subprocess.run(['codesign', '--force', '--sign', '-', app], check=True, capture_output=True)
            run = subprocess.run([str(executable), str(report)], capture_output=True, text=True, timeout=20)
            with (args.output / 'commands.log').open('a') as log: log.write(run.stdout + run.stderr)
            run.check_returncode()
        finally:
            subprocess.run(['defaults', 'delete', bundle_id], capture_output=True)
            cache = Path.home() / 'Library/Caches' / bundle_id
            if cache.exists():
                trash = Path.home() / '.Trash'
                trash.mkdir(exist_ok=True)
                shutil.move(str(cache), str(trash / bundle_id))
    print(f'Native updater menu actions passed. Report: {report}')


if __name__ == '__main__':
    main()
