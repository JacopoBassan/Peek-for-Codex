#!/usr/bin/env python3
"""Verify the packaged app through its real CLI reader and native menu diagnostics."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = '''#!/usr/bin/env python3
import json, os, sys, time
if sys.argv[1:] != ["app-server"]: sys.exit(2)
for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    if method == "initialized": continue
    if method == "initialize":
        result = {"userAgent": "peek-public-fixture"}
    elif method == "account/rateLimits/read":
        case = os.environ["PEEK_VERIFY_CASE"]
        if case == "timeout": time.sleep(30)
        if case == "overflow":
            sys.stdout.write("x" * 300000); sys.stdout.flush(); time.sleep(30)
        if case == "auth-error":
            print(json.dumps({"id":request["id"],"error":{"code":401,"message":"Sign in again"}}),flush=True)
            continue
        if case == "malformed":
            result = {"rateLimits":{"secondary":{"usedPercent":"invalid","windowDurationMins":10080}}}
        elif case == "missing-quota":
            result = {"rateLimits":{"secondary":{"windowDurationMins":10080}}}
        elif case == "null-quota":
            result = {"rateLimits":{"secondary":{"usedPercent":None,"windowDurationMins":10080}}}
        elif case == "empty":
            result = {"rateLimits":{}}
        else:
            window = {"usedPercent":31,"windowDurationMins":10080}
            offset = os.environ["PEEK_VERIFY_OFFSET"]
            if offset != "missing": window["resetsAt"] = time.time() + int(offset)
            bucket = {"secondary":window,"planType":"pro","credits":{"balance":"0"}}
            if case == "raw": result = bucket
            elif case == "legacy": result = {"rate_limits":bucket}
            else:
                result = {"rateLimits":{"secondary":{"usedPercent":95,"windowDurationMins":10080}},
                    "rateLimitsByLimitId":{"codex":bucket,"codex_bengalfox":{"primary":{"usedPercent":5,"windowDurationMins":10080}}}}
    else: sys.exit("Unexpected method in read-only fixture")
    print(json.dumps({"id":request["id"],"result":result}),flush=True)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/Peek for Codex.app')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/menu')
    args = parser.parse_args()
    executable = args.app / 'Contents/MacOS/PeekForCodex'
    if not executable.is_file():
        parser.error('Build the app first with ./scripts/build.sh')
    args.output.mkdir(parents=True, exist_ok=True)
    cases = [
        ('days', 273630, 'Resets in 3 days, 4 hours'),
        ('singular', 90030, 'Resets in 1 day, 1 hour'),
        ('hours', 15630, 'Resets in 4 hours, 20 minutes'),
        ('minutes', 1230, 'Resets in 20 minutes'),
        ('soon', 30, 'Resets in less than a minute'),
        ('overdue', -120, 'Reset pending'),
        ('missing', 'missing', None),
        ('raw', 1230, 'Resets in 20 minutes'),
        ('legacy', 1230, 'Resets in 20 minutes'),
        ('empty', 'missing', None),
        ('malformed', 'missing', 'failure'),
        ('missing-quota', 'missing', 'failure'),
        ('null-quota', 'missing', 'failure'),
        ('auth-error', 'missing', 'failure'),
        ('overflow', 'missing', 'failure'),
        ('timeout', 'missing', 'failure'),
    ]
    report = {}
    # TemporaryDirectory removes only this run's exact disposable /tmp fixture workspace.
    with tempfile.TemporaryDirectory(prefix='peek-menu-e2e-', dir='/tmp') as temporary:
        fixture = Path(temporary) / 'codex-fixture'
        fixture.write_text(FIXTURE)
        fixture.chmod(0o755)
        for name, offset, expected in cases:
            env = dict(os.environ, CODEX_CLI=str(fixture), PEEK_VERIFY_CASE=name, PEEK_VERIFY_OFFSET=str(offset))
            started = time.monotonic()
            run = subprocess.run([str(executable), '--diagnose-usage', '-showCreditsInPopup', 'YES',
                '-refreshIntervalSeconds', '180'], env=env, text=True, capture_output=True, timeout=40)
            elapsed = time.monotonic() - started
            if expected == 'failure':
                assert run.returncode != 0, (name, 'Invalid response was accepted')
                assert not run.stdout.strip(), (name, 'Failure printed successful menu data')
            else:
                assert run.returncode == 0, (name, run.stderr)
                rows = json.loads(run.stdout)
                (args.output / (name + '.json')).write_text(run.stdout)
                if name == 'empty':
                    assert 'No current limits' in rows
                else:
                    assert rows[0] == '69%' and 'Plan: Pro' in rows
                    assert not any('5H' in row or 'SPARK' in row for row in rows)
                    assert '✓ Show Credits' in rows and 'Settings' not in rows
                    index = rows.index('7D · 69% remaining')
                    if expected is None:
                        assert not any(row.startswith(('Resets ', 'On ')) for row in rows)
                    else:
                        assert rows[index+1] == expected, (name, rows)
                        assert rows[index+2].startswith('On '), (name, rows)
            report[name] = {'status':'passed','elapsedSeconds':round(elapsed,3)}
    (args.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'{len(cases)} menu workflows passed. Report: {args.output / "result.json"}')


if __name__ == '__main__':
    main()
