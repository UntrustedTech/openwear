# Legacy Huami family (Mi Band ≤ 7, Huami-derived models). Lower priority.

Source: `com.huami.bluetooth.profile.*`, `com.xiaomi.fit.device.huami.*`, `libdevice-encrypt.so` (arm64).
Bind UI: `BindHuaMiDeviceDeviceActivity` / `BindHuamiViewModel` / `HuaMiDeviceBinder`.

## Auth module (`AuthModule`, module id 128; `AuthModule2`, module id 130)
Commands are a 1-byte opcode followed by data. Responses are prefixed with `0x10 | opcode` (`CMD_RESPONSE_PREFIX = 16`).

| op | name |
|---|---|
| 0 | QUERY_VERSION |
| 1 | START_LOCAL_BINDING |
| 2 | START_CLOUD_BINDING |
| 3 | VERIFY_SIGNATURE |
| 4 | REQUEST_RANDOM_NUMBER (16 B) |
| 5 | AUTHORIZE(cipher) |
| 6 | REQUEST_DE_AUTHORIZE |
| 7 | DE_AUTHORIZE |

- Result codes: 1 = success, 0 = unknown.
- ECDH public key length is **48 bytes**, which suggests a 163-bit binary curve (2 × 24 B).
- Key generation is native: JNI `KeyShareApiImpl.generatePublicKeyExternal/PrivateKeyExternal` in `libdevice-encrypt.so`, which exports `ecdh_generate_keys`, `ecdh_shared_secret` and `ecdsa_sign`.
- Session flow: request random (4) → encrypt the random with the stored auth key → AUTHORIZE (5).
  TODO: confirm the cipher and mode by decompiling the AUTHORIZE caller, and confirm the curve with `analyze_function` on `ecdh_generate_keys`.

## Status
- Not needed for the Smart Band 9 (Xiaomi Wear protocol).
- Gadgetbridge has an open implementation of this family and can be used as a cross-check reference.
- Planned order: deliver the Wear protocol (Band 8/9/10, Redmi Watch 3+, Watch S-series) first, then this family.
