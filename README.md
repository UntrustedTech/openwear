<p align="center"><img src="brand/openwear-icon-512.png" width="112" alt="OpenWear logo"></p>

<h1 align="center">OpenWear</h1>

<p align="center">An open-source Android companion app for Xiaomi Smart Band 9 and other Xiaomi Wear devices. It runs without the Mi Fitness app and without sending your health data to the cloud.</p>

<p align="center"><b>Version 1.0.0</b> · Android 8.0+ · Licensed under GPL-3.0 with attribution terms (see <a href="#license">License</a>)</p>

---

## What it does

OpenWear talks to the band directly over Bluetooth, using the band's own protocol. Your heart rate, steps, sleep and other readings stay on your phone. They leave it only when you choose to share them with Health Connect or export them.

**Health**
- Today at a glance: steps, calories, standing hours, heart rate, SpO₂, stress, sleep and battery
- Heart-rate history and sleep stages (deep, light, REM, awake)
- Writes heart rate, steps, calories, SpO₂, resting heart rate and sleep to **Health Connect**
- Export everything as CSV files in a ZIP, optionally encrypted with AES-256

**Band**
- Phone notifications on the band, with quick replies
- Incoming calls: see who's calling, and reject or end the call from the band
- Music controls, weather, Do Not Disturb, raise-to-wake and other band settings
- **Find phone**: the phone rings and shows a flashing screen, even over the lock screen
- **Find band** from the phone
- More than 60 built-in watch faces, including faces scripted in Lua
- Install band apps (`.rpk`) and firmware updates
- The **OpenWear band app**, which shows today's stats, phone controls, notifications and tools on the band

**Privacy and security**
- No analytics, ads or trackers
- Band keys and account tokens are kept in Android's Keystore-backed storage
- Health files and band screenshots are encrypted on the phone (AES-256-GCM)
- HTTPS only. User-installed certificates aren't trusted, and nothing is included in phone backups.
- A Xiaomi account is needed only once, to pair. Your password goes only to Xiaomi and is never stored.

## Supported devices

| Device | Status |
|---|---|
| Xiaomi Smart Band 9 | Tested; works |
| Smart Band 9 Pro, 10, 10 Pro, 8 Pro; Redmi Watch 4 and 5 series; Xiaomi Watch S3 and S4 | Recognized; not tested yet |
| Smart Band 8, 7 Pro; Redmi Watch 2 | Bluetooth LE only; not supported yet |

The full table is in [docs/devices.md](docs/devices.md).

## Repository layout

| Folder | What's in it |
|---|---|
| `app/` | The Android app (Flutter and Kotlin) |
| `band-app/` | The OpenWear app that runs on the band (Xiaomi Vela quick app) |
| `docs/` | Protocol notes: transport, pairing, commands and capture findings |
| `brand/` | The logo and the script that generates every icon size |

## Building

```bash
cd app
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/debug-info
```

Release signing reads `app/android/key.properties`, which is never committed. Without it, the build is signed with the debug key.

To build the band app: `cd band-app && npm install && npx aiot build`.

## Contributing

Bug reports and pull requests are welcome. Please run `flutter analyze` and `flutter test` before opening a pull request. For security issues, see [SECURITY.md](SECURITY.md).

## License

OpenWear is **open source** under the **GNU General Public License v3.0** ([LICENSE](LICENSE)), with additional terms under GPL section 7 ([NOTICE.md](NOTICE.md)). In short:

- ✅ You may use, study, modify and share OpenWear.
- ✅ Anything you share that is based on it must stay under the same license, with its source code available.
- ❌ **You may not present OpenWear, or a version of it, as your own work.** Keep the copyright notices and credit to the OpenWear project.
- ❌ **Modified versions must not use the OpenWear name or logo.** They must be clearly marked as changed from the original.

## Credits

- Watch-face formats and per-model screen data come from [m0tral](https://github.com/m0tral)'s work on Xiaomi watch faces.
- Device names and connection details were checked against [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge), used as a reference.
- Fonts: Space Grotesk, JetBrains Mono and Noto Serif (SIL OFL 1.1), and DejaVu. Their licenses are in `app/assets/fonts/`.

OpenWear is an independent project. It isn't affiliated with, endorsed by or sponsored by Xiaomi. "Xiaomi", "Mi", "Redmi" and the device names are trademarks of their owners, used here only to say which devices OpenWear works with.
