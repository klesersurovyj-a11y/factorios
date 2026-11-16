# Development

Read [Architecture](architecture.md) first.

## Tasks

```sh
mise run lint              # SwiftLint, swift-format, clang-tidy, shellcheck, plists
mise run build             # converter + iOS device and simulator compile
mise run format            # swift-format in place
mise run deploy            # prepare, build, sign, install, launch on the device
mise run simulator:build   # the same in the iOS Simulator (Apple silicon), signed ad hoc
mise run simulator:launch  # relaunch the installed simulator app
```

- Run `lint` and `build` before a pull request; CI runs both.
- CI also builds a sideloadable IPA with the game inside it: see [Sideloading](sideloading.md).
- `deploy` and `simulator:build` both run [`prepare`](../mise-tasks/prepare) (import `.dmg`, convert) and regenerate
  `xtool/`.
- The game doesn't start on its own: tap **Main menu**.

## Layout

| Path | Contents |
|---|---|
| `Sources/` | Package modules ([Architecture](architecture.md#modules)) |
| `Resources/` | `Info.plist`, entitlements, icon |
| `mise-tasks/` | `deploy`, `prepare`, `simulator/{build,launch}`, `sdl3` |
| `External/SDL` | SDL submodule |
| `xtool.yml` | App description xtool turns into the Xcode project |
| `artifact/`, `Vendor/`, `xtool/` | Ignored: DerivedData, prepared game, SDL3 framework, generated workspace |

To use Xcode: `mise run sdl3 && mise x -- xtool dev generate-xcode-project`, open `xtool/FactoriOS.xcworkspace`. Edit
`Package.swift`, `xtool.yml` or `Resources/`, not the workspace. An Xcode-run app has no game library and shows the
welcome screen.

## Conventions

- Swift 6 and Objective-C `-Weverything` with warnings as errors; strict SwiftLint and swift-format.
- `FactoriOSCore` only holds what the app and converter share.
- No simulator special cases in app code: the simulator runs the same app and game.
- A Mac API replacement goes into `Sources/FactoriOSCompat`, `GameLibrary.redirectedSymbols` if it fills a slot, and
  the [compatibility map](architecture.md#compatibility-map).

## Debugging

`$DEVICE` and `$BUNDLE` are in the first line `deploy` prints. **Detailed logs** in Settings turn on Metal validation
and verbose SDL logs.

```sh
# Device: FactoriOS logs, Factorio log, crash reports, screenshot
xcrun devicectl device copy from --device $DEVICE --domain-type appDataContainer --domain-identifier $BUNDLE \
  --source "Library/Application Support/FactoriOS/Logs" --destination logs/
xcrun devicectl device copy from --device $DEVICE --domain-type appDataContainer --domain-identifier $BUNDLE \
  --source "Documents/Factorio/factorio-current.log" --destination logs/
xcrun devicectl device copy from --device $DEVICE --domain-type systemCrashLogs --source / --destination crashes/
xcrun devicectl device capture screenshot --device $DEVICE --destination screen.png

# Simulator: logs
open "$(xcrun simctl get_app_container booted $BUNDLE data)/Library/Application Support/FactoriOS/Logs"
```

lldb on a device:

1. `xcrun devicectl device process launch --device $DEVICE --terminate-existing $BUNDLE --json-output launch.json`;
   the PID is `result.process.processIdentifier`.
2. In interactive `xcrun lldb`: `device select <devicectl identifier>`, then `device process attach -p <pid>`
   (~20 s).

In the simulator, `xcrun lldb -p <pid>` works directly. Its GPU is the Mac's, so performance and memory don't predict
a device.

## Updating SDL3

The bundled SDL must be at least as new as the one the game links (2.1.24: 3.4.14), or the dynamic API rejects it.

```sh
git -C External/SDL fetch --depth 1 origin tag release-X.Y.Z
git -C External/SDL checkout release-X.Y.Z
git add External/SDL
```

`mise run sdl3` rebuilds `Vendor/SDL3.xcframework`. Check `src/dynapi/SDL_dynapi.h` still only defines
`SDL_DYNAMIC_API`.
