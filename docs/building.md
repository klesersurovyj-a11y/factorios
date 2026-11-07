# Building

FactoriOS is a Swift package that [xtool](https://github.com/xtool-org/xtool) builds into an iOS app, on Linux, WSL
or macOS. Tools are pinned with [mise](https://mise.jdx.dev): `mise.toml` holds what every machine shares,
`mise.local.toml` (not committed) what one machine needs.

## Tools

```sh
mise install          # Swift 6.4.2 (with swift-format), SwiftLint, Python, uv, clang-tidy
mise run setup        # Python packages for scripts/inspect-binary (LIEF, NumPy)
```

A Linux or WSL machine also wants 7-Zip, for reading disk images, and the path of a Factorio disk image. Its
`mise.local.toml`:

```toml
[tools]
7zip = "latest"

[env]
FACTORIOS_DMG = "/path/to/factorio_mac.dmg"
```

## Checks

| Command | What it checks | Where it runs |
|---|---|---|
| `mise run check` | everything below except `tidy` | anywhere |
| `mise run lint` | SwiftLint, every opt-in rule, warnings as errors; cyclomatic complexity ≤ 15, files < 1000 lines | anywhere |
| `mise run format-check` | swift-format, strict | anywhere |
| `mise run build-host` | compiles `FactoriOSCore` (disk image, Mach-O, signing, settings) | anywhere |
| `mise run check-architecture` | every file, API and compatibility entry in `docs/architecture.md` exists | anywhere |
| `mise run check-size` | no implementation file reaches 1000 lines | anywhere |
| `mise run check-markers` | no TODO, FIXME or unimplemented placeholders | anywhere |
| `mise run tidy` | clang-tidy over the Objective-C compatibility layer | macOS (needs the iOS SDK) |

`build-host` sets `FACTORIOS_CORE_ONLY`, which hides the iOS-only targets from the package so the host's own Swift
can compile the core.

## The app

1. **SDL3 for iOS**, once (macOS with Xcode and CMake): `mise run sdl3` builds `Vendor/SDL3.xcframework`.
   `Package.swift` requires it; xtool embeds it in `FactoriOS.app/Frameworks`.
2. **xtool:** install it and its iOS SDK by following
   [xtool's guide](https://xtool.sh/documentation/xtool/installation-linux) (`xtool setup`; on macOS Xcode provides the
   SDK).
3. **Build and install:** `xtool dev` with an iPhone or iPad connected (on WSL, pass USB through with `usbipd`).

`xtool.yml` names the bundle (`app.factorios`), `Resources/Info.plist` adds landscape, Files app sharing and game
controller keys, and `Resources/FactoriOS.entitlements` asks for the increased memory limit and extended virtual
addressing. Apple grants those entitlements per team; xtool reports any the signing team can't have.

`scripts/make-icon` redraws `Resources/AppIcon.png`.

## Inspecting a Factorio build

```sh
mise run inspect                      # uses $FACTORIOS_DMG
mise run inspect -- path/to/factorio  # or an extracted executable
```

The output is the evidence in `docs/feasibility.md`: load commands, the Mac-only APIs the game's own code reaches,
process control, and the Metal selectors that differ on iOS. Run it on each new Factorio version before relying on the
compatibility layer.
