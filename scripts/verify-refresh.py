#!/usr/bin/env python3
"""Verify expired-reader recovery and stale quota removal through native Refresh.

Failure cases: expired cached sign-in after a successful read; status-only 401;
expired sign-in inside a JSON-RPC error; persistent auth failure; a non-auth
failure; cold auth failure; healthy reader reuse; a temporary service failure;
a temporary transport failure; rate limiting without an immediate retry. Retries
must be bounded. Test data never uses an account or production credentials.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = '''#!/usr/bin/env python3
import json, os, pathlib, sys, time
if sys.argv[1:] != ["app-server"]: sys.exit(2)
root = pathlib.Path(os.environ["PEEK_REFRESH_FIXTURE"])
count = root / "starts.json"
ordinal = (json.loads(count.read_text()) if count.exists() else 0) + 1
count.write_text(json.dumps(ordinal))
case = os.environ["PEEK_REFRESH_CASE"]
reads = 0
for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    if method == "initialized": continue
    if method == "initialize": result = {"userAgent":"peek-refresh-fixture"}
    elif method == "account/rateLimits/read":
        reads += 1
        calls = root / "calls.json"
        history = json.loads(calls.read_text()) if calls.exists() else []
        history.append({"reader":ordinal,"read":reads})
        calls.write_text(json.dumps(history))
        if case == "warm-timeout" and ordinal == 1 and reads >= 2: time.sleep(30)
        auth = (case == "cold-auth" and ordinal == 1) or (case.startswith("warm-") and ordinal == 1 and reads >= 2) or (case == "persistent-auth" and (ordinal > 1 or reads >= 2))
        network = (case == "network-failure" and reads in [2,3]) or (case in ["transient-service","transient-rpc","rate-limit"] and reads == 2)
        if auth or network:
            message = "Provided authentication token is expired. Sign in again." if auth else "Service unavailable"
            if case == "warm-code401": message = "Unauthorized"
            code = -32603 if case == "warm-rpc" else 401 if auth else 503
            if case == "transient-rpc":
                code, message = -32603, "error sending request: connection reset"
            if case == "rate-limit":
                code, message = 429, "Too many requests"
            print(json.dumps({"id":request["id"],"error":{"code":code,"message":message}}),flush=True)
            continue
        remaining = 15 if ordinal == 1 and reads == 1 and case != "cold-auth" else 100
        result = {"rateLimits":{"secondary":{"usedPercent":100-remaining,"windowDurationMins":10080,"resetsAt":time.time()+604800},"planType":"pro"}}
    else: sys.exit("Unexpected method")
    print(json.dumps({"id":request["id"],"result":result}),flush=True)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/Peek for Codex.app')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/refresh')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = {}
    # Cleanup is limited to this exact newly created /tmp tree and fixture ID.
    with tempfile.TemporaryDirectory(prefix='peek-refresh-e2e-', dir='/tmp') as temporary:
        work = Path(temporary)
        app = work / 'Peek Refresh Verification.app'
        shutil.copytree(args.app, app, symlinks=True)
        identifier = 'me.peek.refresh.' + uuid.uuid4().hex
        info = app / 'Contents/Info.plist'
        plist = plistlib.loads(info.read_bytes())
        plist['CFBundleIdentifier'] = identifier
        info.write_bytes(plistlib.dumps(plist))
        binary = app / 'Contents/MacOS/PeekForCodex'
        sources = [str(p) for p in sorted((ROOT / 'Sources/PeekForCodex').glob('*.swift')) if p.name != 'App.swift']
        framework = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64'
        command = ['xcrun', 'swiftc', '-swift-version', '6', '-O', '-parse-as-library', *sources,
            '-F', str(framework), '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker',
            '@executable_path/../Frameworks', str(ROOT / 'Support/RefreshVerification.swift'), '-o', str(binary)]
        compile = subprocess.run(command, capture_output=True, text=True, timeout=120)
        log = args.output / 'commands.log'
        log.write_text(json.dumps(command) + '\n' + compile.stdout + compile.stderr)
        compile.check_returncode()
        subprocess.run(['codesign', '--force', '--sign', '-', app], capture_output=True, check=True)
        fixture = work / 'codex'
        fixture.write_text(FIXTURE)
        fixture.chmod(0o755)
        try:
            expected_reads = {'warm-auth':4, 'warm-code401':4, 'warm-rpc':4, 'warm-timeout':4,
                'persistent-auth':3, 'network-failure':4, 'cold-auth':2,
                'healthy-reuse':3, 'transient-service':4, 'transient-rpc':4, 'rate-limit':3}
            for case in expected_reads:
                case_dir = work / case
                case_dir.mkdir()
                report = args.output.resolve() / (case + '.json')
                env = dict(os.environ, CODEX_CLI=str(fixture), PEEK_REFRESH_CASE=case, PEEK_REFRESH_FIXTURE=str(case_dir))
                run = subprocess.run([str(binary), case, str(report)], env=env, capture_output=True, text=True, timeout=25)
                starts = json.loads((case_dir / 'starts.json').read_text())
                reads = len(json.loads((case_dir / 'calls.json').read_text()))
                expected = 2 if case.startswith('warm-') or case in ['persistent-auth', 'cold-auth'] else 1
                results[case] = {'status':'passed' if run.returncode == 0 and starts == expected and reads == expected_reads[case] else 'failed',
                    'readerStarts':starts, 'expectedReaderStarts':expected, 'reads':reads,
                    'expectedReads':expected_reads[case], 'diagnostic':run.stderr.strip()}
                with log.open('a') as stream: stream.write(json.dumps([str(binary), case, str(report)]) + '\n' + run.stdout + run.stderr)
            predicate = f'subsystem == "{identifier}" AND category == "usage"'
            logged = subprocess.run(['log', 'show', '--last', '5m', '--predicate', predicate,
                '--style', 'json', '--info'], capture_output=True, text=True, timeout=20)
            with log.open('a') as stream: stream.write('log show: ' + predicate + '\n' + logged.stderr)
            logged.check_returncode()
            entries = json.loads(logged.stdout)
            messages = [entry.get('eventMessage', '') for entry in entries]
            assert any('authentication_401' in message for message in messages), 'Authentication log missing'
            assert any('temporary_request_503' in message for message in messages), 'Service log missing'
            assert any('request_timeout' in message for message in messages), 'Timeout log missing'
            assert not any('Provided authentication token' in message or 'Too many requests' in message for message in messages), 'Raw error message was logged'
            (args.output / 'logging.json').write_text(json.dumps({'status':'passed',
                'subsystem':identifier,'errorMessages':messages,'logsRawErrors':False},indent=2)+'\n')
        finally:
            subprocess.run(['defaults', 'delete', identifier], capture_output=True)
    (args.output / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
    assert all(case['status'] == 'passed' for case in results.values()), results
    print(f'{len(results)} refresh workflows passed. Report: {args.output / "result.json"}')


if __name__ == '__main__':
    main()
