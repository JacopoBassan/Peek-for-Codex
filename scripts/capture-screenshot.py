#!/usr/bin/env python3
"""Capture the production native menu with 69% demo data on a plain dark background."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/screenshot/demo.png')
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Cleanup is limited to this run's exact disposable /tmp workspace and helper process.
    with tempfile.TemporaryDirectory(prefix='peek-screenshot-', dir='/tmp') as temporary:
        work = Path(temporary)
        app = work / 'Screenshot.app/Contents'
        (app / 'MacOS').mkdir(parents=True)
        executable = app / 'MacOS/Screenshot'
        sources = sorted((ROOT / 'Sources/PeekForCodex').glob('*.swift'))
        sources = [str(source) for source in sources if source.name != 'App.swift']
        sdk = ROOT / '.build/artifacts/sparkle/Sparkle'
        framework = sdk / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
        if not framework.is_dir():
            parser.error('Build the app first with ./scripts/build.sh to resolve Sparkle')
        (app / 'Frameworks').mkdir()
        subprocess.run(['ditto', str(framework), str(app / 'Frameworks/Sparkle.framework')], check=True)
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-O', '-parse-as-library', *sources,
            '-F', str(framework.parent), '-framework', 'Sparkle',
            '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
            str(ROOT / 'Support/Screenshot.swift'), '-o', str(executable)], check=True)
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'me.peek.screenshot',
            'CFBundleExecutable':'Screenshot','CFBundleName':'Peek screenshot','CFBundlePackageType':'APPL',
            'CFBundleDevelopmentRegion':'en','LSUIElement':True}))
        helper = subprocess.Popen([str(executable), str(work), '-AppleLocale', 'en_GB', '-AppleLanguages', '(en)'],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not (work / 'screenshot-ready').exists():
                if helper.poll() is not None:
                    raise RuntimeError(helper.stderr.read().decode())
                if time.monotonic() > deadline:
                    raise TimeoutError('The screenshot helper did not start')
                time.sleep(.1)
            time.sleep(1)
            layout = json.loads((work / 'screenshot-layout.json').read_text())
            menu = layout['menuBounds']
            canvas = layout['captureBounds']
            offset = menu[0] + menu[2] / 2 - canvas[0] - canvas[2] / 2
            if abs(offset) > .5:
                raise RuntimeError(f'Native menu is {offset:g} points off-center')
            report = ROOT / '.build/verification/screenshot'
            report.mkdir(parents=True, exist_ok=True)
            (report / 'layout.json').write_text(json.dumps(dict(layout, centerOffsetPoints=offset), indent=2) + '\n')
            rect = (work / 'capture-rect.txt').read_text()
            subprocess.run(['/usr/sbin/screencapture', '-x', '-R' + rect, str(output)], check=True)
        finally:
            if helper.poll() is None:
                helper.terminate()
                helper.wait(timeout=5)
    print(f'Captured native menu with demo data: {output}')


if __name__ == '__main__':
    main()
