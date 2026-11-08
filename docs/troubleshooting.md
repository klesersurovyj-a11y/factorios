# Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `setup: Command Line Tools are selected` | Run `sudo xcode-select -s /Applications/Xcode.app` |
| `setup: no device found` | Connect with a cable, unlock the device, tap **Trust**. Check `xcrun devicectl list devices` |
| `setup: no team found` | Sign in under Xcode → Settings → Accounts |
| `setup: several …s found` | Choose one: `mise run setup -- --device UDID`, `--team TEAMID` or `--dmg PATH` |
| `… is not set; run 'mise run setup'` | `mise.local.toml` is missing a value. Run `mise run setup` |
| xcodebuild: *Failed to register bundle identifier* | Another team owns that App ID. Set a different ID: `mise run setup -- --bundle-id app.factorios.yourname` |
| xcodebuild: *Developer Mode disabled* | Settings → Privacy & Security → Developer Mode, then restart the device |
| xcodebuild: *maximum number of apps* | A free team allows 3 sideloaded apps per device. Delete one |
| App icon appears, launch says *Untrusted Developer* | Settings → General → VPN & Device Management → your account → Trust |
| App stopped opening after a week | The free provisioning profile expired. Run `mise run deploy` |
| Welcome screen instead of the home screen | The game data didn't reach the device. Run `mise run deploy` again and check the `devicectl device copy` step |
| Game closes while loading | Out of memory. Set Sprite quality to Medium. Light graphics also help |
| `SDL archive checksum mismatch` | The SDL download is corrupt or changed upstream. Delete `Vendor/` and retry |
| `xtool/FactoriOS.xcworkspace` out of date after pulling | `mise run deploy` regenerates it. Run `mise run xcode-project` to regenerate it on its own |

## Collecting logs

The launcher's **Logs** screen copies both logs. From the Mac, see
[on-device debugging](development.md#on-device-debugging). Attach FactoriOS's log, the game's log, and
`factorio-current.log` to bug reports, with the device model, iOS version and Factorio version.
