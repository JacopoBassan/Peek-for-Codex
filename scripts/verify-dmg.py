#!/usr/bin/env python3
"""Open the actual disk image in Finder and record its install layout."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
INSPECT = '''on run arguments
    set mountedFolder to POSIX file (item 1 of arguments) as alias
    tell application "Finder"
        ignoring application responses
            open mountedFolder
        end ignoring
        activate
        delay 1
        set imageWindow to front Finder window
        if (POSIX path of (target of imageWindow as alias)) is not ((item 1 of arguments) & "/") then error "Unexpected Finder window target"
        set rootFolder to target of imageWindow
        set index of imageWindow to 1
        set layout to icon view options of imageWindow
        set output to (current view of imageWindow as text) & linefeed
        set output to output & (toolbar visible of imageWindow as text) & linefeed
        set output to output & (statusbar visible of imageWindow as text) & linefeed
        set output to output & (icon size of layout as text) & linefeed
        set output to output & (text size of layout as text) & linefeed
        set windowBounds to get bounds of imageWindow
        repeat with coordinate in windowBounds
            set output to output & (coordinate as text) & linefeed
        end repeat
        set appPosition to get position of item "Peek for Codex.app" of rootFolder
        repeat with coordinate in appPosition
            set output to output & (coordinate as text) & linefeed
        end repeat
        set applicationsPosition to get position of item "Applications" of rootFolder
        repeat with coordinate in applicationsPosition
            set output to output & (coordinate as text) & linefeed
        end repeat
        set output to output & (id of imageWindow as text) & linefeed
        return output
    end tell
end run'''
CLOSE = '''on run arguments
    set mountedFolder to POSIX file (item 1 of arguments) as alias
    tell application "Finder"
        set imageWindows to get Finder windows
        repeat with windowReference in imageWindows
            set imageWindow to contents of windowReference
            try
                if (POSIX path of (target of imageWindow as alias)) is ((item 1 of arguments) & "/") then close imageWindow
            end try
        end repeat
    end tell
end run'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dmg', type=Path, default=ROOT / 'dist/preview/Peek-for-Codex-preview.dmg')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/verification/dmg')
    parser.add_argument('--signed', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    log = args.output / 'commands.log'
    log.write_text('Disk image end-to-end verification\n')

    def run(command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        with log.open('a') as stream:
            stream.write(repr(command) + '\n' + result.stdout + result.stderr + '\n')
        if result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result.stdout

    run(['hdiutil', 'verify', str(args.dmg.resolve())])
    # Cleanup is limited to this run's exact, newly created /tmp mount workspace.
    with tempfile.TemporaryDirectory(prefix='peek-dmg-check-', dir='/tmp') as directory:
        mount = Path(directory).resolve() / 'mounted'
        mount.mkdir()
        run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(args.dmg.resolve())])
        window_open = False
        try:
            app = mount / 'Peek for Codex.app'
            assert app.is_dir(), 'App missing'
            assert (mount / 'Applications').is_symlink() and os.readlink(mount / 'Applications') == '/Applications'
            assert (mount / '.DS_Store').is_file(), 'Finder layout missing'
            assert (mount / '.background/background.tiff').is_file(), 'Installer background missing'
            assert (mount / '.VolumeIcon.icns').is_file(), 'Volume icon missing'
            run(['codesign', '--verify', '--deep', '--strict', str(app)])
            for architecture in ['arm64', 'x86_64']:
                run(['lipo', str(app / 'Contents/MacOS/PeekForCodex'), '-verify_arch', architecture])
            if args.signed:
                run(['xcrun', 'stapler', 'validate', str(args.dmg.resolve())])
                run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', str(args.dmg.resolve())])
                run(['spctl', '--assess', '--type', 'execute', str(app)])
            window_open = True
            values = run(['osascript', '-e', INSPECT, str(mount)]).strip().splitlines()
            assert values[:5] == ['icon view', 'false', 'false', '112', '13'], values
            coordinates = list(map(int, values[5:-1]))
            window_id = int(values[-1])
            assert window_id > 0, 'Installer window ID missing'
            left, top, right, bottom = coordinates[:4]
            assert (right-left, bottom-top) == (640, 422), coordinates
            assert coordinates[4:] == [170, 210, 470, 210], coordinates
            time.sleep(1)
            # Capture this window directly so unrelated windows cannot cover the image.
            run(['screencapture', '-x', '-o', '-l', str(window_id), str(args.output / 'installer.png')])
            (args.output / 'result.json').write_text(json.dumps({'status':'passed', 'signed':args.signed,
                'view':values[0], 'iconSize':112, 'bounds':coordinates[:4], 'iconPositions':coordinates[4:],
                'windowID':window_id, 'screenshot':'installer.png'},indent=2)+'\n')
        finally:
            try:
                if window_open:
                    run(['osascript', '-e', CLOSE, str(mount)])
            finally:
                run(['hdiutil', 'detach', str(mount)])
    print(f'Disk image layout and install contents passed. Report: {args.output / "result.json"}')


if __name__ == '__main__':
    main()
