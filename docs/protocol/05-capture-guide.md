# Phase 2: capturing Smart Band 9 traffic

Goal: record real Bluetooth traffic between Mi Fitness and the Band 9, then check docs 01–03 against it (framing, auth handshake, nonce/IV use, command payloads, mass transfer).

## One-time phone setup (Android)
1. Settings → About phone → tap **Build number** 7×, which enables Developer options.
2. Developer options → enable **USB debugging**.
3. Developer options → **Enable Bluetooth HCI snoop log** → choose "Enabled" (not "Filtered").
4. Toggle Bluetooth **off and on** so logging starts.
5. Connect the phone by USB, run `adb devices` on the PC, and accept the prompt on the phone.

## Scenarios to record (one bug report per scenario keeps captures small)
Do each one, then tell Claude which scenario it was so it can collect the capture with REA (`collect_adb_bugreport` → `inspect_packet_capture`).

| # | Scenario | What it validates |
|---|---|---|
| A | Unpair the band, then **pair fresh in Mi Fitness** | local/account bind (1/18, 1/19, 1/25), ECDH, HKDF "miwear-bind" |
| B | Force-close Mi Fitness, reopen it (the band reconnects) | session auth (1/26, 1/27), L1START TLVs, MTU |
| C | Pull-to-refresh sync on the home screen | fitness ID lists (8/1, 8/2), channel-5 files, 8/5 acks |
| D | Send yourself a test notification, then call the phone and reject it on the band | 7/0 payload, 7/2 end call |
| E | Install a small watch face from the gallery | 4/4 then the mass transfer on channel 2 |
| F | Change one setting (e.g. raise-to-wake) | 2/24, 2/25 |

## About the keys
Traffic after auth is encrypted. To decrypt captures we need the **auth key** (`appToken`/`authKey`, 16 bytes).
- For our own app (no-account mode), we create it ourselves during bind, so it's known.
- For Mi Fitness captures: Mi Fitness logs `_AppKey`, `_DeviceKey` and the session randoms at debug level ("WearAuth"). These logs may appear in its log files or in logcat. Collect them with `read_adb_logcat` during scenario B.
  If they aren't there, scenario A plus our own bind implementation (Phase 3) is the cleaner route.

## Privacy
Bug reports contain your phone's logs. They stay local under `re/captures/`, and that folder should be git-ignored.
