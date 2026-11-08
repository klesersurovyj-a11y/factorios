# Getting started

Build FactoriOS on a Mac and install it with your copy of Factorio on your iPhone or iPad. Other host platforms
aren't supported yet.

```mermaid
flowchart LR
    A[1. Mac tools] --> B[2. Apple Account<br/>in Xcode] --> C[3. Prepare device] --> D[4. Download<br/>Factorio .dmg] --> E[5. mise run setup] --> F[6. mise run device] --> G[7. Trust developer<br/>on device]
```

## Requirements

| What | Notes |
|---|---|
| Mac | A macOS version that runs the current Xcode |
| [Xcode](https://apps.apple.com/app/xcode/id497799835) | The full app, not only the Command Line Tools, with the iOS platform installed |
| [mise](https://mise.jdx.dev/getting-started.html) | Installs the pinned Swift, xtool and linters |
| iPhone or iPad | arm64, iOS 17 or later, connected with a cable. Tested on an iPhone 14 |
| Apple Account | A free account works (Personal Team) |
| Factorio for macOS | The `.dmg` from [`factorio.com/download`](https://factorio.com/download); the demo works |

## 1. Mac tools

```sh
xcode-select -p                 # should print /Applications/Xcode.app/Contents/Developer
sudo xcode-select -s /Applications/Xcode.app   # if it printed CommandLineTools
git clone https://github.com/kmnft/factorios.git && cd factorios
mise trust && mise install
```

Open Xcode once so it finishes installing its components and the iOS platform.

## 2. Apple Account in Xcode

In Xcode, open **Settings → Accounts**, click **+** and sign in. A free account creates a *Personal Team*. Xcode creates
the signing certificate and provisioning profile on the first build.

## 3. Prepare the device

1. Connect the iPhone or iPad with a cable, unlock it and tap **Trust** for this Mac.
2. Turn on **Settings → Privacy & Security → Developer Mode** and restart when asked. The option appears after the
   device has been connected to Xcode once.

## 4. Download Factorio

Download Factorio for macOS from [`factorio.com/download`](https://factorio.com/download) into `~/Downloads` (or into
`artifact/` in the repository). `mise run setup` picks the newest `factorio*mac*.dmg` from either place.

## 5. Configure

```sh
mise run setup
```

`setup` checks Xcode and writes the values below to `mise.local.toml`, which stays on your Mac. When there are several
candidates it lists them, and you choose with a flag: `mise run setup -- --device UDID --team TEAMID --dmg PATH`.

| Variable | Detected from |
|---|---|
| `FACTORIOS_DEVICE_ID` | the connected device (`xcrun devicectl list devices`) |
| `FACTORIOS_TEAM_ID` | the teams of the accounts signed in to Xcode |
| `FACTORIOS_DMG` | the newest Factorio disk image |
| `FACTORIOS_BUNDLE_ID` | `app.factorios.<team>`: a free team's App ID must be unique across Apple |

## 6. Build and install

```sh
mise run device
```

The first run takes a while: it builds SDL3 from source, the app, and the Mac prepare tool, imports the disk image and
converts the game. Later runs reuse all of that and copy only changed game files.

```mermaid
sequenceDiagram
    participant X as Xcode
    participant P as factorios-prepare
    participant D as Device
    X->>X: build and sign FactoriOS (automatic signing)
    P->>P: import .dmg, convert factorio to factorio.dylib
    P->>P: codesign it with the app's certificate
    X->>X: embed the dylib, re-sign the app
    X->>D: install the app
    X->>D: copy the game data into the app's container
    X->>D: launch
```

## 7. First launch

iOS blocks apps from a new developer until you trust it: **Settings → General → VPN & Device Management**, select your
Apple Account, tap **Trust**, and open FactoriOS. The launcher opens on its home screen. Tap **Main menu** to start
Factorio. [Playing](playing.md) covers the controls.

## Keeping it running

- **Free accounts:** the provisioning profile expires after 7 days, and the app then stops launching. Run
  `mise run device` again; your saves stay. A free account allows 3 devices and 3 sideloaded apps per device.
- **New Factorio version:** download the new `.dmg`, run `mise run setup` (it picks the newest image when the
  configured one is gone, or pass `--dmg`), then `mise run device`. Run `mise run inspect` first if the game's
  Mac-only API use might have changed ([Development](development.md#new-factorio-versions)).

Something failed? See [Troubleshooting](troubleshooting.md).
