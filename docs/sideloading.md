# Sideloading

Play FactoriOS on an iPhone or iPad without a Mac: GitHub Actions builds the app with the game inside it, and a
sideloading tool signs that IPA with your Apple Account and installs it.

The [CI workflow](../.github/workflows/ci.yml) does in one app what `deploy` does on a Mac: it imports the Factorio disk
image, converts the game's executable, embeds the library and the game data in the bundle, and uploads the IPA as a
build artifact. `GamePaths.gameRoot` uses the game in the bundle when Application Support holds no imported one, so a
fresh install goes straight to Home.

## Build it

1. Push a branch (any branch builds one), or **Actions** → **CI** → **Run workflow**.
2. Leave `factorio_url` empty for the free demo, or give a Factorio for macOS `.dmg` link.
3. Download `FactoriOS-ipa-<run number>` from the run's **Artifacts**.

Your own copy's download link comes from your account at [factorio.com/download](https://factorio.com/download). Keep it
in the repository as the Actions secret `FACTORIO_URL`, which the workflow prefers over the input.

## Install it

The IPA is unsigned: iOS installs only code signed with your Apple Account, so a signing tool signs it while installing.

[Feather](https://github.com/claration/feather) does that on the phone itself, but it signs only with a certificate you
import: a `.p12` and its `.mobileprovision`, listing your device and matching the bundle ID `app.factorios` (a wildcard
profile works). Feather can't create them from an Apple ID.

1. Download the run's artifact zip in Safari and unzip it in Files; it holds `FactoriOS-sideload.ipa`.
2. Open that IPA in Feather, or **Library** → **+** → **Import from Files**.
3. Import the `.p12` and `.mobileprovision` under **Certificates**, then **Sign** and **Install**.
4. Turn on Settings → Privacy & Security → **Developer Mode**, and trust the certificate under Settings → General →
   VPN & Device Management.

Feather unpacks and re-signs the app on the phone and hashes the game data, so it wants about three times the IPA's
size free. If installing from its local server stays on *Ready*, pick **Settings** → **Installation** → **Server** →
**Semi Local**.

Otherwise [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) on a computer, with a free Apple
Account.

A free account's signature lasts 7 days; install again after that. Saves stay.

## Limits

- **The demo** is what the default build carries. The full game needs its own `.dmg` link, which only your account has.
- **Don't share the IPA.** Factorio's [terms of service](https://factorio.com/terms-of-service) allow personal use and
  forbid passing the game, an altered copy, or a build that contains it to anyone else.
- **No computer?** TestFlight installs from the device itself, but it needs a paid Apple Developer account and a build
  uploaded to App Store Connect, which this workflow does not do.
