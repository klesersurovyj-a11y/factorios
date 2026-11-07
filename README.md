# FactoriOS

Play your own copy of Factorio on an iPhone or iPad. FactoriOS imports the **macOS** build you download from
factorio.com, turns it into a library iOS can load, signs it with the same Apple Development identity used to provision
FactoriOS, and runs it natively. SDL3 for iOS and a small compatibility layer replace the few Mac-only APIs the game
uses. No emulation, no streaming, and none of the game's files in the app.

**Status: written, not yet run.** Nothing here has run on a device. `docs/architecture.md` lists exactly what remains
to be verified there.

## How it works

```mermaid
flowchart LR
    dmg[factorio .dmg] --> importer[Importer<br/>UDIF, bzip2, HFS+]
    importer --> app[factorio.app]
    app --> converter[Converter<br/>Mach-O to iOS dylib]
    converter --> signer[Signer<br/>CodeDirectory + CMS]
    signer --> loader[Loader<br/>dlopen, compat slots]
    loader --> game[Factorio's main]
    game -- SDL3_DYNAMIC_API --> sdl[SDL3 for iOS]
    game -- AppKit, OpenCL, Metal quirks --> compat[Compatibility layer]
```

- [Feasibility](docs/feasibility.md): what the macOS binary needs, from its own load commands and code.
- [Architecture](docs/architecture.md): modules, public APIs, the compatibility map, and what's deferred to a device.
- [Building](docs/building.md): tools, checks, and building the app with xtool.

## Requirements

- An arm64 iPhone or iPad on iOS 17 or later, installed to your own device with xtool using a free Apple developer
  account (Personal Team). Which device generations can run the game within their CPU and memory limits remains a
  device-test gate.
- Factorio for macOS from [factorio.com/download](https://factorio.com/download) (the demo works too).
- The exact Apple Development identity xtool uses to provision FactoriOS, exported as a password-protected `.p12`.
  The identity handoff from xtool is still a setup gate; do not substitute a second certificate.

This is Apple's personal development provisioning path, not App Store or TestFlight distribution. The repository
currently packages the app with xtool; it does not contain an Xcode app project or installable Xcode scheme. Public
distribution requires paid Developer Program membership, and the imported-code runtime is not App Store eligible.

## Factorio

Factorio is © Wube Software. FactoriOS isn't affiliated with Wube and includes none of its files.
