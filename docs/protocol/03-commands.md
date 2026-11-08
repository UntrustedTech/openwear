# Commands and features — Xiaomi Wear protocol

All commands are `Command{type, subtype, payload}` protobufs on L2 channel 1 (see 01-transport).

**Schema files**
- `re/recovered.proto`: 855 messages recovered automatically from the protobuf-nano classes. Names are obfuscated Java names; field names `fN_x` show only the field number.
- `re/commands.tsv`: every (type, subtype) pair found, with the Mi Fitness method that sends it (301 pairs).
- Treat both as **reference only**. Our app defines its own `.proto` with meaningful names and the same field numbers.

## Command families (`type` → payload oneof field → message)
| type | field | msg | family |
|---|---|---|---|
| 1 | 3 | ab0 | Auth / bind (see 02) |
| 2 | 4 | mer | System: battery, info, time, settings, find, widgets, DND |
| 4 | 6 | dtt | Watch faces |
| 5 | 7 | sni | NFC |
| 7 | 9 | oti | Notifications and calls |
| 8 | 10 | xva | Fitness / health |
| 9 | 11 | — | eSIM (LPA) |
| 10 | 12 | a3u | Weather |
| 11 | 13 | zuq | Stocks |
| 13 | 15 | d6a | Factory / self-check |
| 15 | 17 | pyg | Third-party apps (XMS) |
| 16 | 18 | vbc | Sync misc |
| 17 | 19 | yj4 | Alarms, world clock, reminders, to-dos |
| 18 | 20 | seh | Music / media / audio |
| 20 | 22 | rvr | Smart-home / third-party |
| 21 | 23 | v25 | Emergency contacts, fall detection, contacts |
| 22 | 24 | f0h | Mass (bulk file) transfer control |
| 23 | 25 | p0f | Game mode / misc |

## System (type 2), selected
| sub | action |
|---|---|
| 0 | unbind |
| 1 | battery |
| 2 | device info |
| 3 | **set time** |
| 6 | language |
| 9 | password status |
| 10/11 | night mode get/set |
| 17 | find-phone stop |
| 18 | find device — `mer.5` int: 0 start ringing, 1 stop |
| 21 | unwear lock |
| 23/64 | DND — 2/23 carries `mer.11` `{1: mode}`; the phone sends 0 when its DND is on, else 2; the band reports its state the same way |
| 24/25 | raise-to-wake get/set — `mer.7` `{1 mode (0 all day, 1 scheduled, 2 off), 2 start {1 h, 2 min}, 3 end {h, min}, 4 sensitivity}`; defaults 08:00–22:00 |
| 29/30 | app list / app sort |
| 31/41 | app layout |
| 32/35/38 | shortcut/button |
| 39/40 | sport sort |
| 51/52, 83–85 | widgets |
| 65/66 | AOD |
| 90 | OTA status |
| 108 | watch screenshot |
| 109/110 | focus/zen rules |
| 42 | wear/accessory mode — `mer.35` `{3: {1: mode}}` (both directions; Band 9 reports mode 0 on connect) |

## Notifications and calls (type 7, payload `oti`)
Phone → watch:
| sub | action | payload |
|---|---|---|
| 0 | **add notification(s)** | `oti.f3 = NotificationList{ repeated Notification f1 }` |
| 1 | remove notification / missed call | |
| 6/7 | auto-screen get/set | |
| 14 | quick-reply (SMS) result | `status` |
| 15 | prepare app icon | |

`Notification` (`pti`):
| field | meaning |
|---|---|
| 1 | package (`"phone"` for calls) |
| 2 | app name |
| 3 | title / caller name |
| 4 | "" |
| 5 | text / number |
| 6 | time `"HH:mm"`-style string |
| 7 | id (`sbn.id`) |
| 8 | **callType** (calls only) |
| 9 | "" |
| 11 | call-reply supported |
| 12 | key (`sbn.key`) |
| 16 | flag |
| 14/15/17/18 | sub-messages (actions etc.), TODO |

Watch → phone (handle these):
| sub | action |
|---|---|
| **2** | **reject / end call** (`TelecomManager.endCall`) |
| **5** | **silence ringer** |
| 13 | quick-reply request (`uti`: text and target) |
| 1 | dismissed on watch (`oti` list of keys) |
| 8 | open on phone |
| 16 | request app icon (`mti.f1 = package`) |

Answering a call from the watch is **not** present.

**Calls (verified in code, Band 9 test pending):** ring = `7/0` with one Notification `{1:"phone", 2:"phone", 3 caller-or-number, 5 number-or-"", 7:0, 8 callType, 11 replySupported}`; callType 1 = incoming, 3 = outgoing. Stop ringing / call over = `7/1` `oti.f4 = { repeated qti{1:0, 2:"phone", 3:""} }`.

**App icons (verified on Band 9):** after a notification from an unknown package the watch sends `7/16` `oti.f16 = {1: package}`. Phone replies:
1. `7/15` `oti.f14 = {1: package}` → watch answers `oti.f15 = {1 status (0 ok), 2 pixelFormat, 3 size px, 5 segmentLength}`. Band 9: format 7, 176 px.
2. Raw pixels `size × size`, row-major, uploaded by mass transfer type 3 / detail 2. Pixel formats: 0/4 RGB565 LE · 1 RGB565 BE · 2/3 BGRA8888 · 7 RGB565 LE + A8 · 8 RGB565 BE + A8.
The watch caches icons per package (no new 7/16 for a known package).

## Fitness / health (type 8, payload `xva`)
Sync flow:
1. `8/1` gets **today's** file IDs, or `8/2` gets **historical** file IDs. The reply is a byte blob of concatenated 7-byte IDs.
2. Request files: `8/3` (several IDs concatenated) or `8/4` (one 7-byte ID).
3. Files arrive on **L2 channel 5 (FILE_FITNESS)**. Each is checked with CRC32 and then parsed.
4. `8/5` confirms (acks) each processed ID so the watch can drop it.

Seen on the Band 9 (2026-10-31 log):
- `8/5` is fire-and-forget (Mi Fitness `confirmFitnessId` sends `xva.f3 = id` without waiting for a reply).
- Without `8/5` the band pushes its **whole unconfirmed backlog** about 5 s after each file transfer: today's report (`…f00501`), the spot-check file (`…f00218`) and every minute-record file (~540 by 23:00). OpenWear now confirms each file once it is saved, except files that are still growing: today's report, today's spot checks and the newest minute file.
- Minute-record files (`daily_activity/record`, one record per minute per the schema) also gain a record **every time the phone syncs**, and the band starts a new file after a sync. With a 10 s sync, files were 60 s apart with ~7 records each. Steps and calories are increments, so every record is summed; record times are spread evenly up to the next file's start (at most 60 s apart).

**File ID (7 bytes)**:
```
u32 timestamp (LE)
i8  tz
u8  version
u8  type bits:
      bit 7     = sport (1) / daily (0)
      bits 6..2 = dataType
      bits 1..0 = fileType (record / report / gps)
```
Verified on Band 9: the reply to 8/1 carries IDs in `xva.f2` (concatenated) or `f3` (single); files arrive on channel 5 as `[total:u16][seq:u16][bytes]`, joined = `id(7) ‖ body ‖ CRC32 LE`, and the schemas parse `id ‖ body`. Files can arrive in any order, so match them by their embedded ID. Schemas may narrow integers (`uint32` with `byteSize: 3`), so `byteSize` wins.

**File formats** come as machine-readable JSON in the APK at `assets/schemas.zip` (extracted to `re/assets/schemas/`), covering 72 schemas.
- Health dataTypes: 0 daily_activity, 2 daytime_sleep, 3 night_sleep, 6 manual_measurement, 8 full_day_sleep, 9 abnormal, 10 weight_fat, 11 ecg, 12 temperature, 13 osa.
- Sport types: 3 indoor_running … 22 outdoor_foot, 24 climbing, 25 diving, and others.
- The parser should be **schema-driven**: our own interpreter of the schema format. Don't ship Xiaomi's JSON files.

Other fitness settings: 8/0 user profile, 8/8–9 SpO2 config, 8/10–11 HR / high-accuracy sleep, 8/12–13 sedentary, 8/14 stress, 8/21–22 vitality reminder, 8/42–43 goals, 8/45–46 start/stop realtime HR.

## Watch faces (type 4, payload `dtt`)
| sub | action |
|---|---|
| 0 | list installed |
| 1 | set active |
| 2 | delete |
| 4 | **pre-install** (announce file) |
| 7 | get current |
| 11 | edit |
| 14 | get specific |

Install: send `4/4`, then upload the face binary over **mass transfer** (below), with slice length `61440` for faces.

## Mass transfer (type 22 control + L2 channel 2 data) — verified on Band 9
1. `22/0` prepare: `f0h.f1 = {1 typeByte = type<<4 | detail, 2 md5(file), 3 fileLen, 4 compressMode 0}`.
   Reply `f0h.f2 = {1 md5, 2 status (0 ok, 1 busy), 4 resume offset, 5 slice length}` (Band 9: 16384). Command-level status 1 = watch already has the file (done). `22/1` `f0h.f3 = {1 op, 2 dataType}` cancels.
2. Payload = `header ‖ file ‖ CRC32(header ‖ file)` (CRC LE), header 22 bytes LE: `[0x00][typeByte][md5:16][fileLen:u32]`.
3. Slices of `sliceLength − 4` bytes; each L2 packet on **channel 2, opcode 1 (not encrypted)** is `[totalParts:u16][partIndex:u16, 1-based][bytes]`. Send the next slice after the L1 ACK of the previous one.
Known (type, detail): (3, 2) notification app icon.

## Other families of interest
| family | commands |
|---|---|
| Weather (10) | 0/1/2 current + forecast, 4 pressure, 5–10 city list, 12 UV |
| Alarms etc. (17) | 0 get alarms, 4 delete, 5 set, 10/11/13 world clock, 15/17 event reminders, 14/19 to-dos |
| Music (18) | 0 = watch requests media info (watch → phone), 1 sync, 3–13 music push / library, 18–21 voice recordings |

## Weather (type 10, payload field 12) — recovered from Mi Fitness 3.59.2
- **10/3** band → phone: please send weather. OpenWear answers with 10/0, 10/1, 10/2 (and also pushes on connect).
- **City list first.** The band shows weather only for cities in its list. Mi Fitness reads it with **10/5** (reply: field 4 `{repeated 1: {1 locationKey, 2 name}}`), puts the current location first, writes it back with **10/6** (same shape), then sends 10/0–10/2 with the same `locationKey`.
- Pressure (10/0 field 9) is a float in **Pa** (Mi Fitness multiplies hPa/mbar by 100).
- Shared **place** message: `{1 pubTime ISO-8601 with offset, 2 cityName, 3 locationName, 4 locationKey, 5 isCurrentLocation}`.
- `kv` = `{1 string unit/name, 2 sint32 value}`, `range` = `{1 sint32 from, 2 sint32 to}`.
- **10/0 current** = field 1 `{1 place, 2 code, 3 temp kv(unit "℃"/"℉"), 4 humidity kv("%"), 5 wind kv(direction, level), 6 uv kv, 7 aqi kv, 8 alerts, 9 pressure float}`.
- **10/1 daily** (≤ 7 days) = field 2 `{1 place, 2 {repeated 1 day}}`, day = `{1 aqi kv, 2 range(dayCode, nightCode), 3 range(high, low), 4 unit, 5 {1 sunrise "HH:mm", 2 sunset}, 6 wind kv}`.
- **10/2 hourly** = same shape as daily; code and temperature go in the `to` slot (field 2) of their ranges.
- Codes are the Xiaomi/CMA set: 0 sunny, 1 cloudy, 2 overcast, 3 shower, 4 thundershower, 5 thunder+hail, 6 sleet, 7/8/9 light/moderate/heavy rain, 10 storm, 13–16 snow, 18 fog, 19 freezing rain, 53–56 haze.
- Wind level from km/h: thresholds 1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 117.

## Music (type 18, payload field 20) — recovered from Mi Fitness 3.59.2
- **18/0** band → phone: please send the player state.
- **18/1** phone → band: field 1 `{1 state (0 none, 1 playing, 2 paused, 10 no permission), 2 volume %, 4 title, 5 artist, 6 position s, 7 duration s}`.
- Band controls arrive with field 2 `{1 control (0 play, 1 pause, 3 previous, 4 next, 5 volume), 2 volume %}`; the subtype is not yet confirmed on the Band 9, so OpenWear accepts any 18/x carrying field 2.

## Heart-rate monitoring config (8/10 get, 8/11 set) — partly recovered
`xva.8` message with fields 1 (0/1, "continuous" switch), 2 (interval), 3 bool, 4 int, 5 `{1 bool}`, 6/8 sub-messages, 7 bool, 9 (0/1/2).
Meanings beyond 1–2 are not confirmed; OpenWear does not write it yet (a partial write could reset the other fields).

## Daily activity report (health file, data type 0, file type 1)
Today's copy is listed by 8/1 and rewritten by the band through the day (its id timestamp is local midnight).
After the 7-byte id: 1 byte encryption/compression, 4 bytes validity flags (big-endian; bit 31−n marks body field n valid), then little-endian fields (versions 5 and 6 share this prefix):
`steps u32 · active kcal u16 · HR u8 · resting HR u8 · max HR u8 · max-HR time u32 · min HR u8 · min-HR time u32 · avg HR u8 · avg/max/min stress u8×3 · standing-hours mask u24 · total kcal u16 · recovery u16 · SpO₂ u8 · max SpO₂ u8 · time u32 · min SpO₂ u8 · time u32 · avg SpO₂ u8 · …`
Unset minimums read 0xff. Verified against a real v5 file from the Band 9 (65 bytes).

## Daily activity record (health file, data type 0, file type 0)

The band's own per-minute measurements. These include all-day heart rate. Versions 3–5 are known; the Band 9 sends v4.

Layout: `id(7) · flags(1) · validity(6, big-endian 48 bits)`, then fixed-size records until the end of the file. Records are one minute apart, starting from the id timestamp rounded down to a minute.

The validity mask has 4 bits per item, starting at bit 47:
- the first bit means the item is present in every record;
- the second bit means it is valid.

Items in order, with their size in bytes (little-endian):

| # | item | bytes | notes |
|---|------|-------|-------|
| 0 | HR-rise + steps | 2 | bit 15 sunshine (v5), bit 14 HR rise, bits 13–0 steps |
| 1 | activity type + kcal | 1 | |
| 2 | strength / sport type | 1 | |
| 3 | distance | 2 | |
| 4 | heart rate | 1 | 0 = no reading |
| 5 | battery | 1 | |
| 6 | kcal + energy | 2 | |
| 7 | SpO₂ | 1 | |
| 8 | stress | 1 | followed by 1 abnormal-HR byte when HR-rise is set |
| 9 | light | 2 | v4+ |
| 10 | movement | 2 | v4+ |
| 11 | floors | 1 | v5 |

Verified on a real v4 file: mask `ff ff f8 cf ff ff`, 16-byte records.

## Band screenshot (2/108) — used for watch-face pictures

The phone sends `2/108` with no body. The band may ask first with `2/112`, where field 45 is `{1: 2}` (it wants to send images). The phone answers `2/113`, field 74 `{1: [{1: 2, 2: 0 (allowed) | 1}]}`.

The picture arrives as data packets: `00 85 · total u16 · seq u16 (1-based) · bytes`. Joined together they form `name len u8 · name · 5 bytes · PNG · CRC32 (LE, over everything before it)`.

OpenWear switches to each face (4/1), waits about 2 s, takes a screenshot and switches back. This produces face pictures without any store or server.

## Weather units and pressure

Mi Fitness always sends temperatures in Celsius with unit `℃`, as the weather server returns them; the band converts to its own display unit. OpenWear previously sent Fahrenheit values with `℉` when the °F switch was on, and the band showed 0. The app's Metric/Imperial setting now only affects what the app shows.

Mi Fitness also sends pressure on its own as `10/4`, with a3u field 3 = Pa (float).

## Language (2/6)

The payload is `mer` field 20 `{1: "ll_CC"}` (e.g. `en_US`), taken from the phone locale. OpenWear sends it on connect, as Mi Fitness does.

## User profile and goals (8/0)

The payload is `xva` field 1:

| field | meaning | type |
|---|---|---|
| 1 | height | cm, int |
| 2 | weight | kg, float |
| 3 | birthday | `yyyymmdd`, int |
| 4 | sex | 1 male, 2 female |
| 5 | max HR | int |
| 6 | calorie goal | int |
| 7 | step goal | int |
| 8 | max MET | float |
| 9 | stand goal | hours |
| 10 | sleep goal | minutes |
| 11 | exercise goal | minutes |
| 12–15 | "value is a default" flags for height / weight / birthday / sex | int |
| 16–23 | medical ID: name, blood type, donor, emergency contact `{1 name, 2 number, 3 relation}`, allergies, conditions, treatment | mixed |

When a value is unknown, Mi Fitness sends defaults (170 cm, 60 kg, 1990-01-01, male) and sets the matching flag.

## Band weather settings (10/9 get, 10/10 set)

The payload is a3u field 6, `{1: temperature unit (1 °C, 2 °F; 0 = not supported or leave as is), 2: weather alerts (1 on)}`. Mi Fitness sends only the field being changed. The band shows weather in this unit and converts from the Celsius data it receives.

## 12/24-hour clock

Field 4 of the 2/3 time message means "use 12-hour". Mi Fitness sets it to `!DateFormat.is24HourFormat()`.

## Daily record validity (correction)

Each item's 4 validity bits are: present, then one valid bit for each of up to three packed values. Steps are the third value of item 0, so their valid bit is 44. Per-minute active calories are item 1 bits 5–0 (second value); total calories are item 6 bits 15–10 (first value).

## Current weather city (10/7)

`10/7` with a3u field 5 `{1 locationKey, 2 name}` makes that city the band's current weather city, adding it when missing (Gadgetbridge: "set current, add to list"). Reply status: 0 ok, 1 not supported, 3 already added. Gadgetbridge uses only 10/7 for bands without multiple weather locations and the list write (10/6) for the rest; OpenWear sends 10/7 first, then the list. Without a Xiaomi key the place gets an `accu:<number>` key (stable hash of the name), never "lat,lon". Sunrise and sunset are ISO-8601 with offset.

### 10/0 needs the alerts list (verified on Band 9, 2026-11-07)
The band ignores current conditions (and its Weather app says to turn on weather updates in the phone app) unless the message has field 8, the alerts list. Mi Fitness always sends it, empty when there are no alerts (`BlueToothSender.getAlertsList`). Sending `8: ''` fixed weather on the Band 9.
