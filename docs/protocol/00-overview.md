# Mi Fitness 3.59.2 — Protocol RE notes (clean-room spec)

Target: `com.xiaomi.wearable` 3.59.2i (versionCode 359002), minSdk 26, targetSdk 35.
base.apk sha256 `d7b0a2b45e12899d91f9323bd59dad8e3531c490cbf1bc83345f5631929cfbe2`, 57,313 classes.
This spec describes behaviour only. Do not copy Xiaomi code into the app.

## Protocol families (two stacks in one app)
| Family | Devices | Java stack | Native |
|---|---|---|---|
| Xiaomi "Wear" (newer) | Smart Band 8+, Redmi Watch 3+, Watch S1+ | `com.xiaomi.wearable.{transport,connection,core,wear.api}` | none found (crypto in Java) |
| Huami (legacy) | Mi Band ≤7, Amazfit-derived | `com.huami.bluetooth.profile.*` (`AuthModule`, `AuthModule2`, `EncryptEchoModule`) | `libdevice-encrypt.so` — JNI `KeyShareApiImpl.generatePublicKeyExternal/PrivateKeyExternal`; exports `ecdh_generate_keys`, `ecdh_shared_secret`, `ecdsa_sign` |

Bind UIs: `BindBleDeviceDeviceActivity`, `BindLocalDeviceActivity` (+`BindLocalViewModel`, a local bind path to investigate for no-account mode), `BindHuaMiDeviceDeviceActivity`, `BindThirdPartyDeviceActivity`.
Server bind models: `com.xiaomi.fitness.device.manager.api.model.{BindECDHInfo, BindHelloInfo, BindKey, BindSignInfo, BindStatus}`.

## Xiaomi Wear transport layers (confirmed statically)
- **L0**: physical link, `layerl0.BleChannel` (GATT) or `layerl0.SppChannel` (BT Classic RFCOMM).
- **L1**: framing and reliability, `layerl1.{L1Packet, CMDPacket, DataPacket, ACKPacket}`, `TransportL1`.
- **L2**: `L2Packet(channel: byte, opCode: byte, priority: int, payload: byte[])`, `HEADER_SIZE = 2` (byte 0 = channel, byte 1 = opcode). Priority is local only (`DEFAULT = 0`, `HIGHEST = 10`).
- Two generations: `TransportV1`/`TaskQueueV1` and `TransportV2`/`TaskQueueV2` (`CMD_TIMEOUT = 200` ms in V2).

### Send path (`TaskQueueV2.enqueue`)
```
channel  = getChannel(task)
encrypt  = needEncrypt(task.type)
opCode   = getOpCode(encrypt)          // opcode marks plaintext vs encrypted
data     = getData(task)               // serialized protobuf
if encrypt: data = CryptoHandlerV2.encryptDataV2(data)
send L2Packet(channel, opCode, priority(channel), data)
```
Related: `channelEncryption(byte)`, `shouldDispatchAuthPacket()`, `shouldTreatPlainPbAsAuth()`, `handleVersion(byte[])`, `sendStartRequest(cb)`.

## Auth / session
- `com.xiaomi.wearable.wear.api.WearAuthV1`, `WearAuthV2`. V2 ctor: `(String, byte[], String, String, boolean, WearApiCall, int)`, with helper methods `h(byte[],byte[])` and `k(byte[],byte[],byte[])` (key-derivation candidates).
- `CryptoHandlerV2.encryptDataV2` handles session encryption.
- Protobuf message classes are **obfuscated** (e.g. `u05`).

## Documents
- `01-transport.md`: GATT UUIDs, L1 SAR framing (magic A5A5, CRC-16/ARC), L1START TLVs, L2 channels/opcodes, payload crypto V1/V2
- `02-pairing-and-auth.md`: no-account local bind (ECDH P-256, HKDF "miwear-bind"), account bind, session auth (HKDF "miwear-auth")
- `03-commands.md`: command families, notifications/calls, health sync and file IDs, watch faces, mass transfer
- `04-legacy-huami.md`: Mi Band ≤7 stack (surface only)
- `05-capture-guide.md`: Phase 2 capture plan for the Smart Band 9
- `re/recovered.proto` (855 messages), `re/commands.tsv` (301 command pairs), `re/assets/schemas/` (72 binary file schemas). Reference only.

## Status (static analysis complete for the Wear protocol)
- [x] L1 header, CRC, L1START config TLVs
- [x] L2 channel and opcode values
- [x] Bind and session handshakes, KDF labels, key splits
- [x] No-account (local) bind path identified and specified
- [x] Protobuf schema recovered (46 of ~855 messages' fields still untyped)
- [x] Health sync flow and file format source (schemas.zip)
- [ ] Confirm with a capture: ACK/NAK payload, V1 vs V2 crypto on Band 9, mass prepare fields, `appDeviceId` format
- [ ] Account-bind server endpoints (`BindHelloInfo`/`BindECDHInfo`/`BindSignInfo`/`BindKey`)
- [ ] Whether Band 9 requires a non-empty `userId` for a local bind
- [ ] Legacy Huami cipher and curve details
