# Devices

`app/lib/protocol/models.dart` lists every Xiaomi Wear model OpenWear knows, and Settings → Supported devices shows it in the app.

Sources (facts only; no code copied):
- **Screens and face type ids:** m0tral's XiaomiWatch.Common (the `WatchScreen` and `WatchDetector` tables in github.com/m0tral/UnpackMiColorFace `lib/`), and the `DeviceType` of the face projects in github.com/m0tral/MiWatchLuaWatchfaces.
- **Models that run Lua faces:** the MiWatchLuaWatchfaces README.
- **Bluetooth names and Classic/BLE support:** Gadgetbridge's Xiaomi device coordinators.

| Value | Model | Screen | Watch-face preview sizes |
|---|---|---|---|
| 1 | Gen 1 (round) | 454×454 | |
| 3 | Gen 2 (round) | 466×466 | 246×246 |
| 4 | Gen 3 (round) | 480×480 | 280×280 |
| 5 | Redmi Watch 2 | 320×360 | 178×178 |
| 6 | Smart Band 7 Pro | 280×456 | 220×358 |
| 7 | Redmi Watch 3 | 390×450 | 234×270 |
| 8 | (Redmi Band Pro?) | 368×456 | 110×208 |
| 9 | Smart Band 8 | 192×490 | 122×310 |
| 10 | Redmi Watch 2 Lite | 320×360 | 178×178 |
| 11 | Smart Band 8 Pro | 336×480 | 230×328, 336×480 |
| 12 | Redmi Watch 3 Active | 240×280 | 156×182 |
| 362 | Watch S3 | 466×466 | 326×326, 464×464 |
| 365 | Redmi Watch 4 | 390×450 | 234×270, 390×450 |
| 366 | Smart Band 9 | 192×490 | 122×310, 192×490 |
| 367 | Smart Band 9 Pro (face projects) | 336×480 | |
| 567 | Smart Band 10 Pro (face projects) | 336×480 | |
| 3651 | Redmi Watch 5 Active (face projects) | 320×385 | |
| 3652 | Redmi Watch 5 Lite (face projects) | 410×502 | |

The detector picks the model from the face's preview size. Band 8 and Band 9 share one face format and are told apart by the face id prefix (`366` or `1209` means Band 9; `365` turns a type-7 face into Redmi Watch 4).

What works where:
- **OpenWear's image faces** are drawn for 192×490, so they're offered on Band 9 (tested) and Band 8. They're hidden on other screens.
- **Lua faces** fit any screen and are offered on Lua models.
- **Bluetooth LE-only models** (Band 8, Band 7 Pro, Redmi Watch 2 …) can't connect yet.
