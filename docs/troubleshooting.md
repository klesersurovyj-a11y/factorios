# Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `deploy: select Xcode` | Run `sudo xcode-select -s /Applications/Xcode.app` |
| `deploy: no device found` | Connect with a cable, unlock the device, tap **Trust**. Check `xcrun devicectl list devices` |
| `deploy: no team found` | Sign in under Xcode → Settings → Accounts |
| `deploy: several …s found` | Choose one: `mise set --file mise.local.toml FACTORIOS_DEVICE_ID=UDID` (or `FACTORIOS_TEAM_ID`, `FACTORIOS_DMG`) |
| xcodebuild: *Failed to register bundle identifier* | Another team owns that App ID. Set a different ID: `mise set --file mise.local.toml FACTORIOS_BUNDLE_ID=app.factorios.yourname` |
| xcodebuild: *Developer Mode disabled* | Settings → Privacy & Security → Developer Mode, then restart the device |
| xcodebuild: *maximum number of apps* | A free team allows 3 sideloaded apps per device. Delete one |
| App icon appears, launch says *Untrusted Developer* | Settings → General → VPN & Device Management → your account → Trust |
| App stopped opening after a week | The free provisioning profile expired. Run `mise run deploy` |
| Welcome screen instead of the home screen | The game data didn't reach the device. Run `mise run deploy` again and check the `devicectl device copy` step |
| Game closes while loading | Out of memory. Set Sprite quality to Medium. Light graphics also help |
| `xtool/FactoriOS.xcworkspace` out of date after pulling | `mise run deploy` regenerates it. Run `mise x -- xtool dev generate-xcode-project` to regenerate it on its own |

## Collecting logs

The launcher's **Logs** screen copies both logs. From the Mac, see
[on-device debugging](development.md#on-device-debugging). Attach FactoriOS's log, the game's log, and
`factorio-current.log` to bug reports, with the device model, iOS version and Factorio version.
