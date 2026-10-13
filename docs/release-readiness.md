# Release checks

## 0.2.2 refresh recovery

The 0.2.2 build 10 fix was verified on 13 October 2026. The exact cause of the earlier temporary failure could not be recovered because that build did not retain error diagnostics. Fresh live usage reads succeeded.

Peek now retries a temporary service, transport or timeout failure once before clearing the last quota. Service errors reuse the healthy reader. A timeout closes the failed reader, so the retry starts a fresh one. Authentication errors still restart the reader once to load the existing sign-in. Rate limiting does not trigger an immediate retry. Repeated failures clear the old quota and update time. Normal successful reads add no requests or delay.

Error diagnostics use the macOS log subsystem `me.jacopobassan.peekforcodex`, category `usage`. They contain fixed error categories, numeric error codes and recovery results. They do not contain raw errors, account data, quota responses or credentials. This permits direct investigation without asking users to read a tooltip.

Run from the repository root:

```sh
python3 scripts/verify-refresh.py --app "dist/release/Peek for Codex.app" --output .build/verification/refresh
python3 scripts/verify-menu.py --app "dist/release/Peek for Codex.app" --output .build/verification/menu
python3 scripts/verify-dmg.py --dmg dist/release/Peek-for-Codex.dmg --signed
```

All 11 native refresh workflows passed. They cover warm and cold authentication recovery, a status-only 401, an expired-sign-in JSON-RPC error, a real request timeout, persistent authentication failure, repeated service errors, healthy reuse, single service and transport failures, and rate limiting. The checks assert reader-start and request counts as well as menu content. The macOS log check confirms safe error categories and excludes raw fixture errors.

All 16 packaged-app menu workflows passed. The universal installer passed Apple notarization, ticket, Gatekeeper, checksum, architecture and Finder layout checks. Feed and archive signatures match the embedded public key and build 10. The same signed app is installed locally. The previous app and installer are retained as backups. The manual README screenshot is unchanged. Commands, reports and receipts are retained under `.build/verification/retry-fix/`. These checks establish behavior and retry bounds, not a measured speed gain.

## 0.2.1 reader sign-in recovery

The local 0.2.1 build 9 fix was verified on 13 October 2026. Its source tag is retained as a checkpoint; its prepared GitHub release was superseded by 0.2.2 before publication. A long-lived reader could report an expired sign-in while a newly started reader still read usage through the existing Codex account. Peek previously kept the last successful quota visible after that error.

Authentication failures now trigger one retry with a fresh reader. The JSON-RPC error code is retained so an HTTP 401 is recognized even when its message only says "Unauthorized". Other failures do not restart a healthy reader. If refreshing still fails, the model clears the old snapshot and successful update time, and the menu shows usage as unavailable. No credentials are copied or exported.

Run from the repository root after building:

```sh
python3 scripts/verify-refresh.py
python3 scripts/verify-menu.py
```

The seven refresh workflows use a disposable CLI, the real reader and model, and the native Refresh menu action. They cover warm expired sign-in, a status-only 401, an expired-sign-in JSON-RPC error, persistent authentication failure, an unrelated service failure, cold recovery and healthy reader reuse. Authentication recovery starts exactly two readers across the workflow; healthy reuse and service-error recovery use one. Persistent failure clears the old percentage, snapshot and update time. This verifies retry bounds and lifecycle behavior, not a measured speed gain.

All seven refresh workflows and the 16 existing menu workflows passed. The universal 0.2.1 installer passed signing, Apple notarization, ticket, Gatekeeper, checksum, feed-signature and Finder layout checks. The fix is installed locally, with the previous app and release artifacts retained as backups. The manual README screenshot is preserved. Reports, commands and receipts are retained under `.build/verification/reset-fix/`. Release assets are the DMG, checksum and signed `appcast.xml`.

## 0.2.0 publication

Release verification for 0.2.0 build 8. Local menu, update and single-instance checks pass. Apple accepted the signed universal installer for notarization. Its ticket is stapled, and the DMG passed Gatekeeper and checksum checks. The app installed for that check was the same signed build. Signatures, notarization, Gatekeeper, the DMG checksum and the signed update feed were checked again on 12 October 2026. Installation on a separate Mac, Intel execution and macOS 14 runtime behavior remain unverified. These limits are disclosed in the release notes.

[Version 0.2.0](https://github.com/JacopoBassan/Peek-for-Codex/releases/tag/v0.2.0) was published on 12 October 2026. Its source tag points to commit `8a60838`. The DMG, checksum and signed `appcast.xml` were uploaded and checked in a draft before the release became public.

## Source and menu

- The native menu shows the Codex quota, reported plan, optional credits, reset countdown and exact date.
- Settings use native menu checkmarks. The old unused popup views have been removed.
- Invalid quota responses fail instead of showing an empty successful result.
- The README describes the current menu and is prepared with the GitHub release download link, installer screenshot, Sparkle updates and manual replacement steps.
- The README uses the manual capture of the native menu, with 62% remaining. The visible credits balance was retained by request.
- Icon resources include the original cloud contour and its provenance notice.
- Update controls use native menu actions and a checkmark. No settings window was added.
- A process lock prevents concurrent app copies from creating duplicate menu bar icons or readers. A registered-app check also detects older running copies.

The app icon uses a white-to-gray gradient, native glass and a light shadow on the exact cloud contour. Default and dark macOS Icon Composer exports were reviewed before regenerating the ICNS and asset catalog. The contour, scale, background and menu-bar icon are unchanged. The installer screenshot shows the updated app icon; the manual menu screenshot is preserved.

Run from the repository root:

```sh
./scripts/build.sh
python3 scripts/verify-menu.py
```

All 16 bundled-app workflows passed on Apple Silicon with macOS 26.6.2 and Swift 6.4. They cover day, hour and minute countdowns; singular wording; imminent, overdue and missing reset dates; plan and quota selection; raw and legacy responses; empty limits; malformed, missing and null quota values; authentication errors; oversized output; and timeouts. Missing quota values fail instead of showing 100% remaining.

The verification script runs the actual app and local reader with disposable CLI fixtures. It permits only initialization and account usage requests. Results are written to `.build/verification/menu/result.json`. Each successful case also saves the native menu diagnostic output. Failures must exit unsuccessfully without printing successful menu data. This checks menu content, not mouse interaction, VoiceOver or every system appearance.

The source-build app and universal preview were refreshed to build 8 with Sparkle and the current icon resources. The signed release and installed app use the same resources and build number. Both executable slices report macOS 14.0 as their minimum version. The current toolchain emits an Intel deprecation warning mentioning macOS 27.0 during the build. Runtime compatibility on the minimum OS remains unverified. The preview is ad-hoc signed and is not a public installer. Current build and verification logs are retained under `.build/verification/sparkle/`; the earlier build 6 icon checks remain under `.build/verification/icon-sync/`.

Generate a separate demo preview from the real menu code:

```sh
python3 scripts/capture-screenshot.py
```

This opens a temporary demo menu, captures only its window area, and closes the helper. The default output is `.build/verification/screenshot/demo.png`. It preserves the manual README screenshot and the installed app's preferences. Use `--output` to select a different file.

The demo capture checks the menu window's horizontal alignment and records its geometry in `.build/verification/screenshot/layout.json`. This measurement applies to the demo preview, not the manual README capture.

## Performance observations

Local measurements are a baseline, not a measured improvement or a long-term resource guarantee.

| Workload | Observation |
| --- | --- |
| Installed app plus its reader, eight idle samples | About 35 MiB summed RSS; one reader; no increase in the app's sampled CPU time |
| Three fresh diagnostic launches with live usage | Median 770 ms from process start to usage output |
| Four live requests through one reused reader | First request 799 ms; median of the next three 498 ms |
| 100 synthetic requests through one reused reader | First request 25 ms; later median 0.16 ms; one reader; no child process after shutdown |

The installed-app measurements used an earlier local build. The reader harness used the audited source. Live timings include local CLI startup and service response time. The synthetic case excludes network work. Reader reuse and shutdown passed in the measured runs.

The separate AppKit harness with a live reader sampled 176 MiB peak and 166 MiB retained summed RSS. With a synthetic reader it sampled about 45 MiB. These totals include the harness and child process; shared pages can be counted more than once. They must not be treated as the installed app's memory footprint.

Local commands, harness source, inputs and JSON results are retained under `.build/verification/public-release/`. Long-running growth, energy use, menu interaction latency and resource use on macOS 14 or Intel hardware have not been measured. No speed gain is claimed.

Four one-second idle samples of installed build 8 showed about 60 MiB app RSS and 48 MiB reader RSS, with no sampled CPU-time increase. This is a short local baseline. It is not a controlled comparison with the earlier measurements or a long-running memory check. The raw samples are retained in `.build/verification/sparkle/idle-samples.json`.

## Installer verification

The [distribution workflow](distribution.md) created `dist/release/Peek-for-Codex.dmg`, its SHA-256 checksum and signed `appcast.xml`. The app, Sparkle's nested helpers and disk image have Developer ID Application signatures. The accepted notarization result is retained in `dist/release/notarization-result.plist`; the current build and verification logs are under `.build/verification/sparkle/`.

The build 8 signed disk image was mounted read-only. Its Applications shortcut points to `/Applications`. The contained app passed deep, strict signature verification and Gatekeeper execution assessment. All 16 menu workflows passed against build 8. The image was then unmounted. The build 8 preview layout also passed. These are local checks, not a downloaded-installer test on another Mac.

The installer now has a saved Finder layout with a neutral Retina background, a drag arrow, 112-point icons, and a custom disk icon. Verify each styled build with:

```sh
python3 scripts/verify-dmg.py --dmg dist/release/Peek-for-Codex.dmg --signed
```

This checks the compressed image, app signatures, both binary slices, the Applications shortcut, the saved window bounds and icon positions, the notarization ticket, and Gatekeeper. It records the installer window directly by its window ID, so other windows cannot cover the screenshot. Toolbar and status bar visibility are set per window; global Finder preferences remain unchanged.

The build 5 review results are retained under `.build/verification/final-review/`. Build 6 icon exports, source checks, installer and menu results, and signing logs are under `.build/verification/icon-glass/`. The signed app identifier is `me.jacopobassan.peekforcodex`, with lowercase `me`. Both binary slices report macOS 14.0 as their minimum version. The bundled icons and provenance notice match the source resources. The manual README screenshot is unchanged.

Packaging stages new outputs until all image checks pass. Verify failure recovery with:

```sh
python3 scripts/verify-package-failures.py
```

This runs the packaging script in a disposable tree with simulated notarization rejection, image verification failure and appcast generation failure. All three cases must fail and preserve the previous app, DMG, checksum, receipt and feed. External tools are simulated to trigger failures without credentials or submissions; real signing and notarization are checked separately above. A Finder timeout during the earlier review also left the previous outputs intact. Finder opening uses an asynchronous request, followed by a window-path check before layout changes.

## Sparkle and duplicate-instance verification

Sparkle 2.10.0 is pinned in SwiftPM. The app requires signed feeds, verifies update archives before extraction, and has no signed-feed expiration fallback. System profiling is disabled. The release script verifies both signatures using the public key embedded in the app, checks the archive length, matches the build number and requires the exact versioned release URL. Private-key mismatch or unsigned output stops release packaging.

Run from the repository root after building:

```sh
python3 scripts/verify-updates.py
python3 scripts/verify-update-menu.py
python3 scripts/verify-single-instance.py
```

All six Sparkle workflows passed with disposable app copies and an ephemeral test key: update and restart with a saved preference, modified feed rejection, modified archive rejection, unavailable feed handling, an already current app and skipping an update. The release verifier also rejected modified feed and archive bytes. These checks use a local server, not GitHub delivery.

A separate install between two Developer ID signed, Apple-notarized fixture apps also passed. Both app tickets and Gatekeeper were verified before testing replacement and restart. The fixture uses the bundled Sparkle framework and a test driver that accepts the update. It does not establish the production GitHub download path or every standard updater dialog interaction.

The native menu harness dispatches the actual NSMenuItem actions. It verifies turning automatic checks and downloads off and on, the checkmark, the manual-check enabled state and saved preference reuse. Sparkle accepts download setting changes only while automatic checks are enabled. The app enables checks first when turning updates on and disables downloads first when turning them off. Mouse interaction and VoiceOver remain outside this harness.

Eight simultaneous launches from two app paths left one running Peek process and one CLI reader. A subsequent restart passed after the lock was released. The installed build also rejected launches from the current source, preview and release app copies. The launch-at-login path stayed on the installed app. The older verification copy was closed, and one installed Peek process remains.

Current receipts, reports and reproducible command logs are under `.build/verification/sparkle/`, including `updates/`, `signed-update/`, `update-menu/`, `single-instance/`, `live-single-instance.json`, `menu-build8/`, `installer-build8/` and `preview-build8/`. The previous installed app and release artifacts are retained in `before/`. The manual README screenshot is preserved; it predates the two update menu controls.

## Public release delivery

All three latest-release download links were fetched without authentication after publication. Their bytes match the verified local assets. The downloaded DMG passed deep signature verification, both architecture checks, notarization ticket validation, Gatekeeper, its SHA-256 checksum and the saved Finder layout check. This was checked on the development Mac; installation on a separate Mac remains unverified.

The bundled Sparkle framework also checked the production GitHub feed in an isolated current-version host. It accepted the required signed feed and reported build 8 as up to date. The fixture disabled automatic updates and skipped any update offer. The installed app, its preferences and its launch-at-login path were not changed. This verifies the production feed check, not installation of a future release.

Publication metadata, downloaded assets, installer results, a screenshot, and repeatable verification scripts are retained under `.build/verification/publication/`.

## Distribution checks still required

1. Download the actual release artifact on a separate Mac. Verify normal opening, dragging to Applications, reading existing Codex usage, preferences, and quitting.
2. Verify execution on Intel hardware and on the minimum supported macOS version. A universal build or Rosetta run does not establish those checks.
3. Verify a complete Sparkle update through GitHub on a separate Mac when a newer signed release is available.

Older builds without Sparkle need one manual replacement to gain automatic updates.
