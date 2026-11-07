# Building

FactoriOS is a Swift package that [xtool](https://github.com/xtool-org/xtool) builds into an iOS app, on Linux, WSL
or macOS. Tools are pinned with [mise](https://mise.jdx.dev): `mise.toml` holds what every machine shares,
`mise.local.toml` (not committed) what one machine needs.

## Tools

```sh
mise install  # Swift, SwiftLint, Python, uv, 7-Zip, clang-tidy, xtool and repository linters
```

On macOS, a device build also needs the full Xcode application, launched once to finish installing the iOS SDK.
Selecting Command Line Tools alone is not sufficient. `xcrun --sdk iphoneos --show-sdk-path` verifies the active SDK.

`mise run inspect` installs its pinned Python packages when needed. A Linux or WSL machine can put the Factorio disk
image path in its uncommitted `mise.local.toml`:

```toml
[env]
FACTORIOS_DMG = "/path/to/factorio_mac.dmg"
```

## Checks

| Command | What it does | Where it runs |
|---|---|---|
| `mise run check` | SwiftLint, swift-format, repository/documentation checks and the `FactoriOSCore` build | anywhere |
| `mise run check-ios` | obtains pinned SDL3, runs clang-tidy and compiles every iOS target | macOS with Xcode |
| `mise run format` | rewrites Swift sources with swift-format | anywhere |
| `mise run inspect` | analyzes the configured Factorio build, installing its Python dependencies first | Linux, WSL or macOS |
| `mise run xcode-project` | generates `xtool/FactoriOS.xcworkspace` for Xcode-managed signing and installation | macOS with Xcode |
| `mise run build-simulator` | writes a simulator app to the configured DerivedData directory | macOS with Xcode |
| `mise run simulator` | builds, installs and launches the app in the configured iOS Simulator | macOS with Xcode |
| `mise run dev` | builds, signs and installs directly through xtool | an xtool development machine |

`check` sets `FACTORIOS_CORE_ONLY` for its host build, which hides the iOS-only targets. `check-ios` needs Xcode's iOS
SDK because clang-tidy and the cross-compile resolve UIKit, Metal and the Objective-C runtime through that SDK.

## Continuous integration

`.github/workflows/ci.yml` runs on every push and pull request:

- Ubuntu installs the pinned mise toolchain and runs `mise run check`.
- macOS runs `mise run check-ios`, which obtains SDL3, analyzes Objective-C against the iOS SDK and compiles
  `FactoriOSApp` for both `arm64-apple-ios17.0` and `arm64-apple-ios17.0-simulator`.

Actions are pinned by commit SHA, workflow permissions are read-only, duplicate runs are cancelled, and both jobs
have timeouts. Binary feasibility inspection is not a CI step because the proprietary Factorio disk image is
deliberately absent from the repository; `mise run inspect` remains the explicit local check for each game release.

## The app

1. **SDL3 for iOS:** the iOS build and development tasks download SDL 3.4.20's official release DMG, verify its pinned
   SHA-256 digest and extract `SDL3.xcframework` into the ignored `Vendor` directory. This works on Linux, WSL and
   macOS; it does not require a local SDL source build. `Package.swift` embeds that framework in the app. SDL's
   [dynamic API contract](https://wiki.libsdl.org/SDL3/README-dynapi) keeps the table order stable, appends new entries,
   and rejects a caller whose table is larger or whose table version differs. That rejection remains part of the SDL
   device gate.
2. **Generate the workspace:** on macOS, run `mise run xcode-project`, then open
   `xtool/FactoriOS.xcworkspace`. The generated workspace is disposable and ignored; regenerate it after package or
   packaging changes.
3. **Build and install:** in Xcode, add the developer's Apple Account, select the Personal Team for the
   `FactoriOSApp` target, select the connected and trusted iPhone or iPad, and press Run. Xcode creates the development
   certificate and device provisioning profile and installs the app directly. This project targets developer-owned
   devices; it does not need an exported IPA, TestFlight or an App Store workflow.
4. **Export the matching identity:** in Keychain Access, export the `Apple Development` identity Xcode used—certificate
   and private key—as a password-protected `.p12`. Transfer that file to the device and import it in FactoriOS. The
   converted game is separate executable code and must be signed with the same identity as the host app.

Linux and WSL developers can instead use `mise run dev` after completing
[xtool's setup](https://xtool.sh/documentation/xtool/installation-linux), but must obtain the exact identity xtool used
for signing; the Xcode workflow is the supported macOS path because its identity is exportable through Keychain
Access.

For a launcher-only smoke test, set `FACTORIOS_SIMULATOR_ID` and optionally `FACTORIOS_DERIVED_DATA` in the ignored
`mise.local.toml`, then run `mise run simulator`. The imported game is device code and its signing and loading gates
still require a physical iPhone or iPad; simulator success does not establish that Factorio runs.

`xtool.yml` names the bundle (`app.factorios`), `Resources/Info.plist` adds landscape, Files app sharing and game
controller keys, and the default `Resources/FactoriOS.entitlements` is empty so an Apple Account's Personal Team can
provision it. If device testing proves the normal memory allowance insufficient and the signing team has the
capabilities, point `entitlementsPath` at `Resources/FactoriOS.memory.entitlements` to request increased memory and
extended addressing.

### Personal Team provisioning

This project targets Apple's free, own-device development workflow—not App Store submission. xtool generates the Xcode
workspace from the Swift package; Xcode performs its standard automatic signing and connected-device installation.

1. Run `mise run xcode-project`, open `xtool/FactoriOS.xcworkspace`, select the Personal Team and run on the device.
2. In Keychain Access, find the `Apple Development` certificate whose private key is nested beneath it and whose team
   matches Xcode's signing setting. Export both together as a password-protected `.p12`.
3. Import that `.p12` in FactoriOS before importing Factorio. A different development certificate—even for the same
   account—will not satisfy library validation.

### Device validation

The source and iOS targets compile in CI, but no device run has happened. Do not report the demo as playable until
this procedure passes. The four decisive runtime gates and the full verification matrix remain in
[`feasibility.md`](feasibility.md#gates-only-a-device-can-close) and
[`architecture.md`](architecture.md#deferred-verified-only-on-a-device).

#### Prerequisites

- A green CI run for the commit under test.
- An arm64 iPhone or iPad on iOS 17 or later, connected, trusted and selected as Xcode's run destination.
- Full Xcode with the developer's Apple Account and Personal Team configured, plus the pinned tools from
  `mise install`.
- The demo `.dmg` and the password-protected `.p12` exported from the exact Xcode identity that signed FactoriOS.

Record the commit, Factorio version, device model, iOS version, signing-team type and entitlement file before testing.

#### Procedure

1. Run FactoriOS from `xtool/FactoriOS.xcworkspace` on the connected device. Pass when Xcode installs it and the
   launcher opens without terminating.
2. Import the matching `.p12`. Pass when FactoriOS accepts its password and reports that the signing identity is
   available.
3. Import the demo `.dmg`. Record the duration and final installation stage. Pass when extraction, conversion and
   signing reach Ready, and the Factorio folder is visible through the Files app.
4. Start **Main menu**. Pass the sign/load gate when the converted library passes validation, `dlopen` succeeds and
   Factorio reaches its main function. Preserve both FactoriOS and game logs even on success.
5. Reach the Factorio menu and start a new demo game. Pass the SDL and Metal gates when the window renders correctly,
   audio plays and the session remains responsive without shader, dynamic-API or compatibility errors.
6. Exercise touch mouse gestures, every on-screen control, keyboard input, haptics where supported and a physical
   controller where available. Background and foreground the app, then verify rendering resumes and the configured
   frame-rate cap still applies.
7. Save, exit, relaunch and use **Continue**. Import and export a save, open the Factorio folder and copy both logs.
   Exercise a game action that requests restart when one is available; pass when FactoriOS asks the player to reopen
   it rather than attempting `execv`.
8. Run a new demo game for at least 15 minutes. Record memory-pressure or jetsam diagnostics, sustained responsiveness
   and the FPS display. Pass the resource gate when the session remains alive and usable on the recorded device.

For every failure, retain the two application logs, the visible error and relevant device diagnostics before
reinstalling. A screenshot or short recording should accompany rendering, input or lifecycle results. The demo is
**playable on the tested device** only after steps 1–6 and the resource gate in step 8 pass; the implementation is
device-verified only after every applicable row in the architecture verification matrix has evidence.

Apple's [developer account documentation](https://developer.apple.com/help/account/basics/about-your-developer-account/)
states the free Personal Team limits: App IDs, registered devices, and provisioning profiles expire after seven days;
the app must then be rebuilt and reinstalled. A free account allows up to three devices and three installed apps per
device.

The free path provides no App Store Connect or TestFlight access. Paid Developer Program membership enables those
distribution services, but the current imported-code runtime remains ineligible under App Review guideline 2.5.2.


## Inspecting a Factorio build

```sh
mise run inspect                      # uses $FACTORIOS_DMG
mise run inspect -- path/to/factorio  # or an extracted executable
```

The output is the evidence in `docs/feasibility.md`: load commands, the Mac-only APIs the game's own code reaches,
process control, and the Metal selectors that differ on iOS. Run it on each new Factorio version before relying on the
compatibility layer.
