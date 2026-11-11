# Development

Start with [Getting started](getting-started.md). Then read [Architecture](architecture.md).

## Tasks

`mise tasks` lists them.

| Task | Does |
|---|---|
| `mise run deploy` | Builds, prepares the game, installs and launches on the device ([`deploy`](../mise-tasks/deploy)) |
| `mise run simulator:build` | The same in the iOS Simulator on an Apple silicon Mac, ad-hoc signed ([`simulator/build`](../mise-tasks/simulator/build)) |
| `mise run simulator:launch` | Launches the installed app in the simulator again, without building ([`simulator/launch`](../mise-tasks/simulator/launch)) |
| `mise run lint` | SwiftLint, swift-format, clang-tidy, scripts, property lists |
| `mise run build` | `factorios-convert`, and the iOS device and simulator compile |
| `mise run format` | Rewrites Swift sources with swift-format |

Everything runs on macOS with Xcode. Run `lint` and `build` before you open a pull request; CI
(`.github/workflows/ci.yml`) runs both.

## Layout

| Path | Contents |
|---|---|
| `Sources/` | The Swift package's modules ([Architecture](architecture.md#modules)) |
| `Resources/` | `Info.plist`, entitlements, app icon |
| `mise-tasks/` | Shell scripts mise runs as tasks: `deploy`, `simulator/build`, `simulator/launch`, `prepare` (`deploy` and `simulator:build` run it), `sdl3` |
| `External/SDL` | The SDL submodule, which `sdl3` builds with the dynamic API on |
| `xtool.yml` | xtool's app description; `deploy` and `simulator:build` turn the package into an Xcode project |
| `artifact/` | Ignored: DerivedData, the prepared game, local disk images |
| `Vendor/`, `xtool/` | Ignored: the built SDL3 framework and the generated workspace |

## Working in Xcode

Run `mise run sdl3`, then `mise x -- xtool dev generate-xcode-project`, and open `xtool/FactoriOS.xcworkspace`. The
workspace is generated and ignored, so make changes in `Package.swift`, `xtool.yml` or `Resources/`, then regenerate it. An app run from Xcode lacks the embedded
game library, so the launcher shows its welcome screen. Use `mise run deploy` or `mise run simulator:build` to play.

## Conventions

- Swift 6 with warnings as errors. Objective-C with `-Weverything -Werror`. SwiftLint and swift-format are strict.
- `FactoriOSCore` holds only what the app and the converter share. App code, UIKit-free logic included, goes in
  `FactoriOSRuntime`'s folders.
- A Mac API replacement goes into `Sources/FactoriOSCompat`, `GameLibrary.redirectedSymbols` when it fills a slot, and
  a row of the [compatibility map](architecture.md#compatibility-map).

## Simulator

`mise run simulator:build` boots `$FACTORIOS_SIMULATOR_ID`, a booted simulator, or the one the simulator app last used,
and `mise run simulator:launch` starts the installed app again. Both bring up the simulator window: Device Hub since
Xcode 27, Simulator.app before. Tap **Main menu**; the Mac's mouse is a finger, and its keyboard reaches the game while
the simulator window forwards keystrokes. Logs are in the app container:

```sh
open "$(xcrun simctl get_app_container booted $BUNDLE data)/Library/Application Support/FactoriOS/Logs"
```

The game runs unchanged there: the same app, compatibility layer and game data, with the library tagged for the
simulator and signed ad hoc. It renders with the Mac's GPU, so performance and memory don't predict a device.

## On-device debugging

Replace `$DEVICE` and `$BUNDLE` with the device and bundle ID that `mise run deploy` prints in its first line.

```sh
# FactoriOS's logs (factorios.log, game.log)
xcrun devicectl device copy from --device $DEVICE --domain-type appDataContainer --domain-identifier $BUNDLE \
  --source "Library/Application Support/FactoriOS/Logs" --destination logs/
# Factorio's own log
xcrun devicectl device copy from --device $DEVICE --domain-type appDataContainer --domain-identifier $BUNDLE \
  --source "Documents/Factorio/factorio-current.log" --destination logs/
# Crash reports
xcrun devicectl device copy from --device $DEVICE --domain-type systemCrashLogs --source / --destination crashes/
# Screenshot
xcrun devicectl device capture screenshot --device $DEVICE --destination screen.png
```

To attach lldb, launch with `xcrun devicectl device process launch --device $DEVICE --terminate-existing $BUNDLE
--json-output launch.json` and read the PID from `result.process.processIdentifier`. Then in an interactive
`xcrun lldb`, run `device select <devicectl identifier>` and `device process attach -p <pid>`. Attaching takes about
20 seconds.

**Detailed logs** in the launcher's settings turn on Metal validation and verbose SDL logging.

## Updating SDL3

The `External/SDL` submodule pins SDL's release. The bundled SDL must be at least as new as the SDL the game links
statically (Factorio 2.1.24 links 3.4.14), because SDL's dynamic API rejects a caller with a larger function table.

```sh
git -C External/SDL fetch --depth 1 origin tag release-X.Y.Z
git -C External/SDL checkout release-X.Y.Z
git add External/SDL
```

`mise run sdl3` rebuilds `Vendor/SDL3.xcframework` whenever the commit or the script itself changes. Check that
`src/dynapi/SDL_dynapi.h` still only defines `SDL_DYNAMIC_API`, since the script skips it through its include guard.
