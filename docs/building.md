# Building

FactoriOS is a Swift package that [xtool](https://github.com/xtool-org/xtool) turns into an Xcode project; building the
app needs macOS with Xcode (SDL3 is built from source). `mise run check` and `mise run inspect` also run on Linux or WSL.
Tools are pinned with [mise](https://mise.jdx.dev): `mise.toml` holds what every machine shares, `mise.local.toml`
(not committed) what one machine needs.

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
| `mise run build-device` | builds and signs for the configured device with Xcode automatic signing | macOS with Xcode |
| `mise run prepare-game` | imports, converts and signs `$FACTORIOS_DMG` into `artifact/game/FactoriOS` | macOS with Xcode |
| `mise run device` | builds the app and the game, installs both on the configured device and launches it | macOS with Xcode |

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

1. **SDL3 for iOS:** the iOS build and development tasks download SDL 3.4.20's release source, verify its pinned
   SHA-256 digest, turn on the dynamic API in `src/dynapi/SDL_dynapi.h` and build `SDL3.xcframework` (iOS device and
   simulator) into the ignored `Vendor` directory with `xcodebuild`, so this step needs macOS with Xcode. SDL's official
   iOS framework can't be used: SDL compiles the dynamic API out on iOS, so it has no `SDL_DYNAPI_entry`, the game's
   static SDL3 ignores `SDL3_DYNAMIC_API` and crashes in its own macOS (Cocoa) video backend. `Package.swift` embeds
   the framework in the app. SDL's [dynamic API contract](https://wiki.libsdl.org/SDL3/README-dynapi) keeps the table
   order stable, appends new entries, and rejects a caller whose table is larger or whose table version differs, so
   the bundled SDL must be at least the game's (Factorio 2.1.24 links SDL 3.4.14). That rejection remains part of the
   SDL device gate.
2. **Generate the workspace:** on macOS, run `mise run xcode-project`, then open
   `xtool/FactoriOS.xcworkspace`. The generated workspace is disposable and ignored; regenerate it after package or
   packaging changes.
3. **Build and install:** add the developer's Apple Account in Xcode → Settings → Accounts, connect and trust the
   iPhone or iPad, and enable Developer Mode. Put the device UDID (`xcrun devicectl list devices`), the Personal Team
   ID and the Factorio macOS disk image in the ignored `mise.local.toml` as `FACTORIOS_DEVICE_ID`, `FACTORIOS_TEAM_ID`
   and `FACTORIOS_DMG`, then run `mise run device`. Xcode's automatic signing creates the development certificate and
   device provisioning profile. On the first install, trust the developer under Settings → General → VPN & Device
   Management before launching. This project targets developer-owned devices; it does not need an exported IPA,
   TestFlight or an App Store workflow.
4. **The game:** `mise run device` also runs `factorios-prepare` on the Mac. It imports the disk image (skipped while
   the image is unchanged), converts the executable with `FactoriOSCore`'s converter, and signs the
   library with `codesign` using the certificate taken from the device build, so the library and the app share one
   identity. The task then copies `factorio.dylib` and `slots.json` into the app's `Frameworks` folder, re-signs the
   app, and installs it. `devicectl` copies the game data into the app's Application Support/FactoriOS, copying only
   changed files on later runs. The app opens on its home screen with the game ready; the device needs neither the
   `.dmg` nor a `.p12`.

iOS 18 and later refuse to `dlopen` code from an app's data container even when that code carries a valid signature,
which is why the library must be embedded in the app bundle. Importing the `.dmg` on the device therefore can't
produce a loadable game, and the launcher has no on-device import or certificate screen.

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
The converted game is separate executable code, so it must carry a signature from the same certificate as the app;
`mise run prepare-game` reads that certificate from the built app, and `mise run device` re-signs the app after
embedding the library.

### Device validation

Factorio 2.1.24 has passed this procedure on an iPhone 14 (A15, iOS 26.6.1) with Medium sprites (High exceeds the
~3.2 GB memory limit). Physical controllers and the restart prompt remain unverified. Results are recorded in
[`feasibility.md`](feasibility.md#device-gates) and [`architecture.md`](architecture.md#device-status); repeat the
procedure for each new device or game version.

#### Prerequisites

- A green CI run for the commit under test.
- An arm64 iPhone or iPad on iOS 17 or later, connected, trusted and selected as Xcode's run destination.
- Full Xcode with the developer's Apple Account and Personal Team configured, plus the pinned tools from
  `mise install`.
- A Factorio macOS `.dmg` configured as `FACTORIOS_DMG`, plus `FACTORIOS_DEVICE_ID` and `FACTORIOS_TEAM_ID`, in
  `mise.local.toml`.

Record the commit, Factorio version, device model, iOS version, signing-team type and entitlement file before testing.

#### Procedure

1. Run `mise run device`. Pass when the app installs, the game is copied and, after the developer is trusted, the
   launcher opens on its home screen showing the imported version.
2. Check the prepared library and its embedded copy: `codesign -dv artifact/game/FactoriOS/Converted/factorio.dylib`
   and `codesign -dv "$FACTORIOS_DERIVED_DATA/Build/Products/Debug-iphoneos/FactoriOS-App.app/Frameworks/factorio.dylib"`
   report identifier `factorio` and the same `TeamIdentifier` as the app. Record how long the Mac's import,
   conversion and copy took.
3. Open the Factorio folder through the Files app. Pass when it is visible and writable.
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
