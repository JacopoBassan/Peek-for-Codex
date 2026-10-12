#!/usr/bin/env python3
"""Run packaging with simulated Apple-tool failures in a disposable tree."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['TOOL_LOG'],'a') as log: log.write(json.dumps([name,*args])+'\n')
if name == 'codesign':
    if '--display' in args: print('Authority=Developer ID Application: Fixture',file=sys.stderr)
elif name == 'hdiutil':
    if args[0] == 'create': pathlib.Path(args[-1]).write_bytes(b'new disk image')
    elif args[0] == 'attach':
        mount=pathlib.Path(args[args.index('-mountpoint')+1]); (mount/'.DS_Store').write_bytes(b'layout')
    elif args[0] == 'convert': pathlib.Path(args[-1]).write_bytes(b'new disk image')
    elif args[0] == 'verify' and os.environ['FAILURE'] == 'verify': sys.exit(1)
elif name == 'xcrun':
    if args[0] == 'swift': pathlib.Path(args[-1]).write_bytes(b'background')
    elif args[:2] == ['notarytool','submit']:
        sys.stdout.buffer.write(plistlib.dumps({'status':'Rejected' if os.environ['FAILURE']=='notary' else 'Accepted'}))
elif name == 'generate_appcast':
    sys.exit(1)
'''

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=ROOT/'.build/verification/package-failures')
arguments=parser.parse_args()
arguments.output.mkdir(parents=True,exist_ok=True)
report={}
for failure in ['notary','verify','appcast']:
    with tempfile.TemporaryDirectory(prefix='peek-package-failure-',dir='/tmp') as directory:
        root=Path(directory)
        (root/'scripts').mkdir(); (root/'Resources').mkdir(); (root/'Support').mkdir(); (root/'tools').mkdir()
        shutil.copy2(ROOT/'scripts/package-dmg.sh',root/'scripts/package-dmg.sh')
        (root/'scripts/build.sh').write_text('#!/bin/zsh\nmkdir -p "$APP_OUTPUT_DIR/Peek for Codex.app"\nprintf new > "$APP_OUTPUT_DIR/Peek for Codex.app/build-marker"\n')
        (root/'scripts/build.sh').chmod(0o755)
        (root/'Resources/PeekForCodex.icns').write_bytes(b'icon')
        for name in ['xcrun','codesign','lipo','hdiutil','osascript','spctl']:
            tool=root/'tools'/name; tool.write_text(TOOL); tool.chmod(0o755)
        sparkle_tools=root/'.build/distribution/artifacts/sparkle/Sparkle/bin'
        sparkle_tools.mkdir(parents=True)
        tool=sparkle_tools/'generate_appcast'; tool.write_text(TOOL); tool.chmod(0o755)
        output=root/'dist/release'; app=output/'Peek for Codex.app'; app.mkdir(parents=True)
        files=[app/'build-marker',output/'Peek-for-Codex.dmg',output/'Peek-for-Codex.dmg.sha256',output/'notarization-result.plist',output/'appcast.xml']
        for file in files: file.write_bytes(b'previous verified artifact')
        before={str(file.relative_to(root)):hashlib.sha256(file.read_bytes()).hexdigest() for file in files}
        env=dict(os.environ,PATH=str(root/'tools')+':'+os.environ['PATH'],FAILURE=failure,TOOL_LOG=str(root/'tool-calls.jsonl'),
                 SIGNING_IDENTITY='Developer ID Application: Fixture',NOTARY_KEYCHAIN_PROFILE='fixture')
        run=subprocess.run(['/bin/zsh',str(root/'scripts/package-dmg.sh')],env=env,capture_output=True,text=True)
        calls=[json.loads(line) for line in (root/'tool-calls.jsonl').read_text().splitlines()]
        expected=['xcrun','notarytool','submit'] if failure=='notary' else ['hdiutil','verify'] if failure=='verify' else ['generate_appcast']
        assert calls[-1][:len(expected)]==expected, 'Workflow stopped before the simulated failure'
        after={str(file.relative_to(root)):hashlib.sha256(file.read_bytes()).hexdigest() for file in files}
        report[failure]={'exitCode':run.returncode,'previousOutputsPreserved':before==after,'simulatedExternalTools':True}
        print(failure,report[failure])
        assert run.returncode != 0, run.stdout
        assert before == after, 'Failed packaging replaced a previous verified output'
(arguments.output/'result.json').write_text(json.dumps(report,indent=2)+'\n')
