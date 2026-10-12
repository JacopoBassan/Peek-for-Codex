# Mac installer

The download is a universal app for Apple Silicon and Intel, inside a drag-to-install disk image. Users open the DMG, drag Peek for Codex to Applications, and launch it. They need macOS 14 or later and an existing signed-in Codex setup. Developer tools are needed only to build the app.

![Peek for Codex installer with the white cloud app icon, an Applications shortcut and a drag arrow](installer.png)

## Local preview

```sh
./scripts/package-dmg.sh --preview
```

This creates `dist/preview/Peek-for-Codex-preview.dmg`. It is ad-hoc signed and **not notarized**. Use it to verify packaging locally, not as a public download. The installed app and its preferences are not replaced by packaging.

The disk image opens in a compact Finder icon view. It uses a neutral background, large app and Applications icons, and a drag arrow. `Support/DiskImageBackground.swift` generates the background at standard and Retina resolutions. `Support/DiskImageLayout.applescript` saves the window layout on the generated volume. Packaging needs permission to control Finder; it does not change Finder's global preferences.

Verify the compressed preview and save a screenshot of its actual Finder window:

```sh
python3 scripts/verify-dmg.py
```

The check mounts its own image read-only, checks the saved layout and install contents, captures the window, then closes and unmounts it. Results are written to `.build/verification/dmg/`.

## Signing setup

Create a **Developer ID Application** certificate in Xcode's Accounts settings and install it on the build Mac. An Apple Development certificate is insufficient for distribution. See [Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

You can reuse an existing notarization profile for the same developer team. The profile name below is only an example; it does not make the credentials app-specific. If needed, save credentials yourself using the interactive command. Enter Apple credentials directly in the prompt; do not put passwords or private keys in this repository, scripts, or logs.

```sh
xcrun notarytool store-credentials Notarization \
  --apple-id "YOUR_APPLE_ACCOUNT_EMAIL" \
  --team-id YOUR_TEAM_ID
```

Replace the email and team placeholders. The command securely prompts for an app-specific password. Create that password at [Apple Account](https://account.apple.com/) under Sign-In and Security, then App-Specific Passwords. Specifying the email and team selects password authentication and avoids the API private-key prompt.

If validation returns HTTP 403 with a missing or expired agreement, open the [Apple Developer account](https://developer.apple.com/account/). The Account Holder must review pending legal agreements and check the membership status. After resolving the account issue, run the credential command again. See [Apple's roles and agreement guidance](https://developer.apple.com/help/account/access/roles). If no agreement is pending and the membership is active, contact Apple Developer Support with the error.

## App icon

`PeekForCodex.icon` is the editable Icon Composer source. Its cloud layer preserves the exact contour used in the menu bar, with a white-to-gray gradient and native glass over the dark background. After changing it, regenerate the bundled macOS resources with full Xcode installed:

```sh
./scripts/generate-icon.sh
```

Keep both `Resources/PeekForCodex.icns` and `Resources/Assets.car` with the source. The build copies both into the app, using the named asset for modern macOS rendering and the ICNS fallback where needed. Ordinary source builds use these generated resources and do not require Icon Composer.

## Build the public installer

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE=Notarization \
./scripts/package-dmg.sh
```

This signs the universal app with hardened runtime and a secure timestamp, creates and signs the DMG, submits it to Apple's notarization service, staples the accepted ticket, and checks Gatekeeper. Missing credentials, rejection, or failed checks stop the release workflow. The new app, image, checksum and notarization result are staged separately until all image checks pass. A failed build preserves the previous verified outputs. It does not publish a GitHub release or commit changes.

The release also generates and verifies a signed Sparkle update feed. Both feed and DMG signatures must match the public key in the app. The build number, archive size and versioned URL are checked before replacing previous outputs. The outputs are `dist/release/Peek-for-Codex.dmg`, its `.sha256` checksum and `appcast.xml`. A feed signing failure preserves the previous outputs. The stable filenames support latest-release download links.

Check the signed installer, including its ticket and Gatekeeper assessments:

```sh
python3 scripts/verify-dmg.py --dmg dist/release/Peek-for-Codex.dmg --signed
```

Before publication, verify the actual downloaded installer on a separate Mac without the development environment: Gatekeeper should allow the normal open flow, the Applications shortcut should support dragging the app, and Peek should read usage from the existing Codex sign-in. Apple Silicon and Intel execution must be verified on their respective hardware; a universal binary alone does not establish both runtime checks.

For local read-only verification, `--diagnose-usage` can be run from the packaged app or a disposable copy. It does not rewrite the user's launch-at-login path. Ordinary app launches still synchronize that path when launch at login is enabled, so complete the drag to Applications before launching normally.

## Publication

Publish only when explicitly approved. Attach the DMG, checksum and signed `appcast.xml` to the same GitHub release, preserving the stable filenames. The README is prepared with this download link:

```text
https://github.com/JacopoBassan/Peek-for-Codex/releases/latest/download/Peek-for-Codex.dmg
```

Publish the installer and matching source update together so the README download link resolves to the released DMG.

The default tag is `v` followed by the app version, such as `v0.2.0`. Set `VERSION` and increase `BUILD_NUMBER` for each update. If using another tag, set `RELEASE_TAG` during packaging. The feed must point to that exact release tag, never a moving `latest` URL for its DMG. Publish all assets before the release becomes public. Do not replace an already published DMG with different bytes.

## Updates

Peek uses [Sparkle 2](https://sparkle-project.org/documentation/) for daily update checks and automatic downloads and installation. The menu has **Check for Updates…** and **Automatic Updates** with a native checkmark. Sparkle owns the schedule and saved preferences; Peek adds no polling loop. System profiling is disabled.

The feed is hosted at:

```text
https://github.com/JacopoBassan/Peek-for-Codex/releases/latest/download/appcast.xml
```

The app requires signed feeds and checks the archive signature before extraction. It rejects invalid feed signatures without an expiration fallback. Sparkle's standard UI handles manual checks, errors, installation and restart. An app running from a disk image must first be copied to Applications.

The public Ed25519 key is in `Support/Info.plist`. The private key stays in the build Mac's login Keychain under the Sparkle account `me.jacopobassan.peekforcodex`. It is separate from Apple signing and notarization credentials. Never export it into the repository or release assets. To set up the key on the original build Mac, run the official tool once after resolving the package:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account me.jacopobassan.peekforcodex
```

If setting up a different key, change the public key in the app before its first release. For an already released app, follow [Sparkle's key rotation guidance](https://sparkle-project.org/documentation/#rotating-signing-keys). Keep a secure backup through a user-managed process. Losing the key or changing both signing identities at once can prevent updates.

`scripts/build.sh` embeds Sparkle, preserves framework symlinks, includes its license, and signs its nested helpers before signing the framework and app. SwiftPM pins the framework version and verifies its download checksum. Commit `Package.resolved` with the source.

Verify full updates and rejected invalid downloads without touching the installed Peek app or its production signing key:

```sh
./scripts/build.sh
python3 scripts/verify-updates.py
```

This uses disposable apps, an ephemeral file-based test key and a local HTTP server. It checks installation and restart, preference preservation, changed feed and archive rejection, an unavailable feed, an already current version and skipping an update. Local HTTP is allowed only in the disposable fixture app. Production uses HTTPS. Results and commands are saved under `.build/verification/updates/`.

Check the actual native menu actions and simultaneous launches:

```sh
python3 scripts/verify-update-menu.py
python3 scripts/verify-single-instance.py
```

To test a complete install between signed, notarized disposable fixtures, start from the signed release app:

```sh
python3 scripts/verify-updates.py \
  --app "dist/release/Peek for Codex.app" \
  --signed-install \
  --signing-identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile Notarization \
  --output .build/verification/signed-update
```

This submits only the two disposable test apps to Apple's notarization service. It uses a temporary test update key, leaves the installed app untouched and preserves a receipt and command log. Completed fixture preferences are removed, and fixture caches are moved to Trash.

Before publishing, also verify an update between Developer ID signed, notarized builds through the release feed on a separate Mac. The local fixture does not establish that production download path. Older Peek builds without Sparkle need one manual replacement to gain the updater.
