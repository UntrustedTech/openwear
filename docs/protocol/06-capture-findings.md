# Capture findings: Smart Band 9 (Samsung Galaxy, Android 17)

## Scenario A: fresh pair (2026-10-30, Mi Fitness 3.59.2, logged in to a Xiaomi account)
Source: `re/captures/A-pair/logcat.txt`. Bug report and HCI log are being collected.

Confirmed:
- Model ID **`miwear.watch.n66gl`**, BLE name `Xiaomi Smart Band 9 XXXX`.
- `DeviceInfo.convert(): bindWithUserId=true`. Band 9 binds **with a userId** in Mi Fitness. Still open: does it accept an empty or arbitrary userId in a local bind? (affects no-account mode)
- Logged in, Mi Fitness used **`WearBinderV2`** (account/cloud bind), not `LocalWearBinderV2`. Scenario A therefore tests path **B** in 02-pairing-and-auth.
- Mi Fitness calls `BluetoothAdapter.createBond(mac, transport=AUTO)` (OS-level bonding) **before** the protocol bind, then `openUnauthConnection()`.
- Session auth order matches static analysis exactly: `sendAppVerify` (≈30–70 ms), then `verify sign success`, then `sendAppConfirm` (≈20 ms), then `deviceConfirm.deviceCapability = 334495549`, `capabilityV2 = 79`/`0`.
- App capability sent: `25188066`, region `US`.
- Debug-level key logs (`_AppKey`, `_DeviceKey`…) are **not** printed in release builds, so logcat can't give us session keys.

## Smart Band 9 live session from the PC prototype (2026-10-30)

- No SAR GATT (0x5E/0x5F absent). Transport is **Bluetooth Classic SPP, RFCOMM channel 5**
  (SDP also lists HID, PnP, FDAB, FE95, vendor cc353442-be58-4ea2-876e-11d8d6976366).
- An SPP-v1 version probe comes first: TX `badcfe 00c0 0300 00 01 00 ef` → RX payload `02 00 61` = 2.0.97;
  major ≥ 2 means V2 A5A5 L1 frames on the same stream.
- L1 START_RSP: VERSION 2.0.97, MPS 32768, TX_WIN 3, SEND_TIMEOUT 16000 (identical to Mi Fitness's reconnect log).
- A Classic bond (BlueZ `pair` with an agent; the band asks for confirmation) is made before binding, matching Mi Fitness's createBond.
- 1/17 reply: verifyMode 1 (PSK), oobMode 3 (button). 1/18 sent without the PSK challenge is ACKed at L1 and never answered.
- 2026-10-31: the PC client ran a full PSK bind (`bind-account`) with no Mi Fitness. Then session auth (1/26–27, capability
  334495549), 2/1 battery (`{1: {1: 96%, 2: state, 3: {…}}}`), 2/3 set time and 7/0 notification all worked encrypted.
  2/3 and 7/0 get no same-subtype reply. The band sends 2/42, 18/0 and 10/3 on its own after auth.
- A band paired with a phone is non-discoverable and refuses ACL/SDP from other hosts, so the bond must be made in pairing mode.
- Confirmed on the band (2026-10-31): 2/3 set time and 7/0 notification both work. Two gotchas:
  - 2/3 needs an IANA zone id plus a standard/DST split. With "EST" the band fell back to UTC+8 and showed local time +12h.
  - pti field 6 (time) must be `yyyyMMdd'T'HHmmss`. With "HH:MM" the band silently dropped the notification.
  - After a notification arrives, the band requests its app icon with 7/16.
