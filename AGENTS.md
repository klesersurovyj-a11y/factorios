# AGENTS.md

FactoriOS runs Factorio's macOS binary on iOS. It converts the binary into a signed dylib on the Mac, embeds it in an
xtool-generated app, and loads it next to SDL3 for iOS and an Objective-C compatibility layer. Read
[docs/architecture.md](docs/architecture.md) before changing code.

## Map

| Path | What |
|---|---|
| `Sources/FactoriOSCore` | Only what the app and the converter share: paths, redirected symbols, slot manifest, JSON files |
| `Sources/FactoriOSRuntime` | The iOS app: `Game` (`@main`, `dlopen`, slot patching, session, SDL input), `Controls`, `Overlay`, `Settings`, `Launcher` |
| `Sources/FactoriOSCompat` | Objective-C: Mac API replacements, Metal fixes, BC decode, SDL bridge |
| `Sources/FactoriOSConvert` | Mac CLI `factorios-convert`: the Mach-O converter `prepare` runs; not in the app |
| `mise-tasks/` | `prepare` (import `.dmg`, convert), `deploy`, `simulator/build`, `simulator/launch`, `sdl3` |
| `External/SDL` | SDL submodule |
| `mise.toml` | Toolchain and the inline tasks (`mise tasks` lists all) |

## Commands

```sh
mise run lint              # SwiftLint, swift-format, clang-tidy, scripts, property lists
mise run build             # converter, iOS device + simulator compile
mise run format            # apply swift-format
mise run deploy            # build, prepare, install, launch on the connected device
mise run simulator:build   # the same in the iOS Simulator (Apple silicon), ad-hoc signed
mise run simulator:launch  # launch the installed app again, without building
```

Run `lint` and `build` after every change. The game doesn't start on its own: someone taps **Main menu**.

## Rules

- The repository never contains Factorio files, converted libraries, or personal values (UDIDs, team IDs, paths).
  Per-machine values live in the ignored `mise.local.toml`. Build output goes to the ignored `artifact/`, `Vendor/`,
  `xtool/` and `.build/`.
- Warnings are errors: Swift 6 strict settings, Objective-C `-Weverything -Werror`, strict SwiftLint and
  swift-format. Don't suppress them; fix the cause.
- `FactoriOSCore` holds only what both the app and `FactoriOSConvert` use. App code goes in `FactoriOSRuntime`, Mac-only
  converter code in `FactoriOSConvert`.
- A new Mac API replacement updates `Sources/FactoriOSCompat`, `GameLibrary.redirectedSymbols` when it fills a slot,
  and the compatibility map in `docs/architecture.md`.
- `xtool/` is generated; edit `Package.swift`, `xtool.yml` or `Resources/` instead.
- No simulator special cases in app code: the simulator runs the same app and game data as a device.
- The bundle ID comes from `FACTORIOS_BUNDLE_ID` through `PRODUCT_BUNDLE_IDENTIFIER`. Don't hardcode it.
- Docs are short: commands and bullets. Update the page that owns the topic instead of adding one.

Logs, crash reports and lldb: [docs/development.md](docs/development.md#debugging).
