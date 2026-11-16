# Troubleshooting

| Symptom | Fix |
|---|---|
| `deploy: select Xcode` | `sudo xcode-select -s /Applications/Xcode.app` |
| `deploy: no device found` | Connect by cable, unlock, tap **Trust**; check `xcrun devicectl list devices` |
| `deploy: no team found` | Sign in under Xcode → Settings → Accounts |
| `deploy: several …s found` | `mise set --file mise.local.toml FACTORIOS_DEVICE_ID=…` (or `FACTORIOS_TEAM_ID`, `FACTORIOS_DMG`) |
| *Failed to register bundle identifier* | `mise set --file mise.local.toml FACTORIOS_BUNDLE_ID=app.factorios.yourname` |
| *Developer Mode disabled* | Settings → Privacy & Security → Developer Mode, restart |
| *maximum number of apps* | A free team allows 3 sideloaded apps per device; delete one |
| *Untrusted Developer* | Settings → General → VPN & Device Management → your account → Trust |
| App stopped opening after a week | Free profile expired: `mise run deploy` |
| Welcome screen instead of home | Game data missing: run `deploy` (or `simulator:build`) again |
| Welcome screen after sideloading | The IPA was built without the game: rerun CI, which embeds the demo |
| CI download fails | The link expired: set `FACTORIO_URL` (secret or workflow input) to a current download |
| Game closes while loading | Out of memory: Sprite quality Medium, Light graphics on |
| No simulator window | `mise run simulator:launch` opens Device Hub (Simulator.app before Xcode 27) |

For bug reports, attach FactoriOS's log, the game's log and `factorio-current.log` (the launcher's **Logs** copies
them, or see [debugging](development.md#debugging)), with device, iOS and Factorio versions.
