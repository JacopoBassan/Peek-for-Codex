#!/usr/bin/env python3
"""Launch real Peek copies together; require one live app and a clean restart.

Failure cases: simultaneous launches, launches from another app path,
duplicate readers, retained lock after exit. All bundle IDs and usage are fixtures.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import runpy
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/Peek for Codex.app')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/single-instance')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {}
    with tempfile.TemporaryDirectory(prefix='peek-instance-e2e-', dir='/tmp') as temporary:
        work = Path(temporary)
        bundle_id = 'me.peek.verification.' + uuid.uuid4().hex
        app = work / 'first/Peek for Codex.app'
        shutil.copytree(args.app, app, symlinks=True)
        plist_path = app / 'Contents/Info.plist'
        plist = plistlib.loads(plist_path.read_bytes())
        plist.update(CFBundleIdentifier=bundle_id, SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
        plist_path.write_bytes(plistlib.dumps(plist))
        subprocess.run(['codesign', '--force', '--sign', '-', app], check=True, capture_output=True)
        other = work / 'other/Peek for Codex.app'
        shutil.copytree(app, other, symlinks=True)
        fixture = work / 'codex-fixture'
        fixture.write_text(runpy.run_path(str(ROOT / 'scripts/verify-menu.py'))['FIXTURE'])
        fixture.chmod(0o755)
        env = dict(os.environ, CODEX_CLI=str(fixture), PEEK_VERIFY_CASE='days', PEEK_VERIFY_OFFSET='273630')
        processes = []
        try:
            for index in range(8):
                copy = app if index % 2 == 0 else other
                processes.append(subprocess.Popen([str(copy / 'Contents/MacOS/PeekForCodex')], env=env,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(3)
            live = [process for process in processes if process.poll() is None]
            assert len(live) == 1, f'{len(live)} app copies are still running'
            assert all(process.returncode == 0 for process in processes if process not in live)
            children = subprocess.check_output(['pgrep', '-P', str(live[0].pid)], text=True).splitlines()
            assert len(children) == 1, f'{len(children)} CLI readers for one app'
            report['simultaneousLaunches'] = {'launched': 8, 'liveApps': 1, 'readers': 1, 'status': 'passed'}
            live[0].terminate(); live[0].wait(timeout=5)
            restarted = subprocess.Popen([str(app / 'Contents/MacOS/PeekForCodex')], env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(restarted)
            time.sleep(2)
            assert restarted.poll() is None, 'App did not restart after releasing the process lock'
            report['restart'] = {'status': 'passed'}
        finally:
            for process in processes:
                if process.poll() is None: process.terminate()
                process.wait(timeout=5)
            subprocess.run(['defaults', 'delete', bundle_id], capture_output=True)
            cache = Path.home() / 'Library/Caches' / bundle_id
            if cache.exists():
                trash = Path.home() / '.Trash'
                trash.mkdir(exist_ok=True)
                shutil.move(str(cache), str(trash / bundle_id))
    (args.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Single-instance workflows passed. Report: {args.output / "result.json"}')


if __name__ == '__main__':
    main()
