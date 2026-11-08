# Transport — Xiaomi Wear protocol (BLE "SAR" link)

Source: `com.xiaomi.wearable.transport.*`, `defpackage.f25`, `com.xiaomi.miot.ble.CRCUtil` (static analysis). All multi-byte integers are **little-endian**.

## L0 — GATT
| Item | UUID |
|---|---|
| Service | `0000fe95-0000-1000-8000-00805f9b34fb` (Xiaomi) |
| SAR write characteristic | `0000005f-0000-1000-8000-00805f9b34fb` |
| SAR notify characteristic | `0000005e-0000-1000-8000-00805f9b34fb` (enable CCCD `0x2902`) |
| SPP alternative (BT Classic) | RFCOMM `00001101-0000-1000-8000-00805f9b34fb` |

Other `0xFE95` characteristics 0x0050–0x005A exist (legacy MiIO/MiBeacon). They're not needed for the Wear SAR link.
Writes are chunked to the negotiated `MTU-3`.

## L1 — SAR framing (`TransportL1`, `L1Packet`)
8-byte header followed by the payload:
```
off size field
0   2    magic       = 0xA5A5 (bytes A5 A5)
2   1    (frx << 4) | type     type: 0=NAK 1=ACK 2=CMD 3=DATA; frx bit 4
3   1    seq         u8, per-direction sequence number
4   2    length      payload length (u16 LE)
6   2    crc16       CRC-16/ARC over the payload (reflected poly 0xA001, init 0, no xorout)
8   n    payload
```

### L1 control (type=CMD), payload `[cmd:u8][data…]`
| cmd | name |
|---|---|
| 1 | L1START_REQ |
| 2 | L1START_RSP |
| 3 | L1STOP_REQ |
| 4 | L1STOP_RSP |

The app sends **L1START_REQ** after enabling notifications. Its data is TLV `[type:u8][len:u16][value]`:
| type | name | value sent by app |
|---|---|---|
| 1 | VERSION | `01 00 00` (major 1, minor 0, rev 0) |
| 2 | MPS | `u16 = 0xFC00` (64512) |
| 3 | TX_WIN | `u16 = 32` |
| 4 | SEND_TIMEOUT | `u16 = 10000` ms |
| 5 | DEVICE_TYPE | (device → app) |
| 6 | DEVICE_NAME | (device → app) |

Defaults: remote TX window 4. An ACK is sent after a window of DATA frames (`TX_WIN_ACK_THR`). TODO: confirm the ACK/NAK payload (likely the acked seq) from a capture.

## L2 — channel multiplexing (`L2Packet`), carried in L1 DATA payloads
```
[channel:u8][opcode:u8][payload…]
```
| channel | name |
|---|---|
| 1 | PB (protobuf commands, the main one) |
| 2 | MASS (bulk file transfer: watchfaces, OTA, music) |
| 3 | MASS_VOICE |
| 4 | FILE_SENSOR |
| 5 | FILE_FITNESS (activity/sleep/HR files) |
| 6 | OTA |
| 7 | NETWORK |
| 8 | LYRA |
| 9 | RESEARCH |
| 10 | MULTI_MODAL |

| opcode | meaning |
|---|---|
| 1 | WRITE (plaintext) |
| 2 | WRITE_ENC (encrypted payload) |
| 3 | READ |

Before auth, PB messages are sent plaintext (`unauthCall`). After auth (see 02), payloads on encrypted channels use opcode 2.

## Payload encryption after auth
- **V2 (BLE SAR; expected for Band 9).** `CipherApiCall.encryptDataV2`:
  `AES-128-CTR(key = encKey, IV = encKey)`. The 16-byte key doubles as the IV, and there's no MAC.
  Decrypt with `decKey` as both key and IV.
- **V1 (older SPP / `TransportV1`).** `encryptData(type, data)`:
  `AES-128-CCM(encKey, nonce = encIV(4) ‖ LE32(0) ‖ LE32(counter|0), 4-byte tag)`.
  For `type == 101` the counter increments, and the output is prefixed with a `u16` counter.

## PB command envelope (channel 1), message `wyt`
```
message Command {            // wyt
  int32  type    = 1;        // family (see 03-commands)
  uint32 subtype = 2;
  oneof payload {
    Auth          auth          = 3;   // type 1
    System        system        = 4;   // type 2
    WatchFace     watch_face    = 6;   // type 4
    Nfc           nfc           = 7;   // type 5
    Notification  notification  = 9;   // type 7
    Fitness       fitness       = 10;  // type 8
    Esim          esim          = 11;  // type 9
    Weather       weather       = 12;  // type 10
    Stock         stock         = 13;  // type 11
    ...           (14..25)             // types 12..23
    uint32        status        = 100; // error / result code
  }
}
```

## SPP v1 (older models)

The version probe (`BA DC FE …`) is itself an SPP v1 packet. Bands that answer with a major version below 2 keep talking v1; OpenWear then skips the v2 link session and starts auth right away (`lib/protocol/spp_v1.dart`, `Link.isV1`). Format as described by Gadgetbridge's XiaomiSppPacketV1:

- Packet: `BA DC FE`, channel (low nibble), flags (`0x80` always, `0x40` wants a reply), u16 LE length of the next three bytes plus payload, opcode (2 = send), frame serial, data type (0 plain, 1 encrypted, 2 auth), payload, `EF`.
- Channels: 0 version, 1 commands band→phone, 2 commands phone→band, 3 fitness, 5 mass transfer, 7 OTA. No ACKs.
- Auth commands (type 1, subtype ≥ 17) go out as data type 2, plain.
- Encryption is AES-CCM with a 4-byte tag, using the session's 4-byte IVs (HKDF output bytes 32–39, unused by v2). Nonce = IV ‖ 0u32 ‖ counter u32 LE. Outgoing commands use a running counter (from 1) and carry it as a u16 LE prefix; other outgoing data and everything incoming use counter 0, no prefix.

Not yet tried on a v1 band.
