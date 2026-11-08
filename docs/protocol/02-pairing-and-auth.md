# Pairing (bind) and session auth — Xiaomi Wear protocol

Source: static analysis of Mi Fitness 3.59.2. Not yet confirmed with a live capture (Phase 2).
Classes referenced: `com.xiaomi.device.binder.LocalWearBinderV2`, `com.xiaomi.wearable.wear.api.WearAuthV2`, `com.xiaomi.fit.device.bind.LocalDeviceBinder`.

## Primitives
| Name | Definition |
|---|---|
| `HMAC(k, m)` | HMAC-SHA256 |
| `HKDF(info, ikm, salt, L)` | RFC 5869 HKDF-SHA256: extract with `salt` (empty → 32 zero bytes), expand with ASCII `info` |
| `CCM_ENC(key, nonce12, pt, aad)` | AES-128-CCM, **4-byte tag** (ciphertext‖tag) |
| ECDH | NIST P-256 (secp256r1). Public keys go on the wire as raw 64-byte `X‖Y` (no `0x04` prefix) |
| `RAND(n)` | n bytes from a CSPRNG |

All bind and auth messages are protobuf commands with `type = 1` (auth/bind family) and the subtype listed below. Protobuf message classes are obfuscated (`wyt`/`xyt` wrapper, `ab0`/`bb0` auth payload). Field numbers are TBD (see 03-protobuf).

## A. Local bind (NO Xiaomi account), first-time pairing
Sent through `unauthCall` (unencrypted channel).

1. **Hello (1/18)**: app creates a P-256 keypair and sends `{ appDeviceId: string, appPubKey: 64B }`.
   `appDeviceId = LocalBindTool.generateAppDeviceIdWithPhoneId(mac, userId|null, phoneId)` (TODO: confirm format).
2. Device replies `{ devPubKey: 64B, devRandom: 16B, devSign: 32B }`.
   Error code `7` = signature failure.
3. App computes
   - `shared = ECDH(appPriv, devPub)`
   - checks `HMAC(shared, devRandom ‖ oob?) == devSign`
     (`oob` = optional out-of-band string, e.g. a QR code; omitted if empty)
4. App draws `appRandom = RAND(16)` and computes
   `okm = HKDF("miwear-bind", ikm=shared, salt=appRandom‖devRandom, 56)`:

   | bytes | name | use |
   |---|---|---|
   | 0–15 | `devKey` | (device→app) |
   | 16–31 | `bindKey` | encrypts the bind result |
   | 32–35 | `devIV` | |
   | 36–39 | `appIV` | |
   | **40–55** | **`authKey` (appToken)** | **long-term per-device secret. Persist it.** |
5. **Confirm (1/19)**: app sends `{ appRandom, HMAC(shared, appRandom ‖ oob?) }`.
   The **user confirms on the watch**. Failure strings in the app include "device cancelled".
6. **Bind result (1/25)**: app sends
   `CCM_ENC(bindKey, nonce = 10 11 12 13 14 15 16 17 18 19 1A 1B, pb{ userId, phoneInfo{0, sdkInt, model} }, aad = "bind-data")`.
   Success → local bind is complete. Store `authKey`, `mac`, `did`, `sn`, `appDeviceId`.
7. Mi Fitness then calls `recordToServer(sn, did, model)` as **best effort**: a failure is only logged. It is **not needed** for the bind.

> Our app: "No account" mode runs A and then skips step 7.
> Open question: does `userId` in step 6 have to be non-empty? `getBindWithUserId()` exists, so some models may require one. Test per model.

## B. Account bind (Xiaomi account)
Base URL `https://hlth.io.mi.com/healthapp/` (`DeviceBindService`, a Retrofit form POST whose field `data` = JSON, plus a `locale` query).
Requests need a Xiaomi account session (passport login, then `serviceToken` and signed requests). That client is a separate work item.

| Step | Endpoint | Request model | Response |
|---|---|---|---|
| 1 | `POST bind/hello` | `BindHelloInfo{did, mac, model, sn, mode, randomMac, deviceRandom, isSupportFind}` | `ApplyBindInfo` |
| 2 | `POST bind/ecdh` | `BindECDHInfo{bindDid, bindIndex, devicePublicKey, deviceSign}` | verify result (`VerifyBindInfo{bind_key…}`) |
| 3 | `POST device/bind_with_devicesign` | `BindSignInfo{did, mac, model, sign, token, bind_key}` | bool |
| 4 | `POST bind/bind` | (confirm) | |
| - | `GET user/get_bindkey` | | `BindKey{bindkey, ret}`, so a key bound with an account **can be re-downloaded** after login |
| - | `POST home/unbind`, `privacy/device/delete`, `bind/update_device_info`, `source/record_source` | | |

Also `POST https://hlth.io.mi.com/app/v1/bind/device_local_bind` (`uploadDeviceLocalBind`): the best-effort "record local bind" call from A.7.

In this mode the cloud takes part in the ECDH/sign exchange and keeps the key. Either way the result is a per-device `authKey`, so session auth (C) is the same.
Our app's account mode: log in, then `user/get_bindkey` for already-bound bands, or the full flow for new binds.

## C. Session auth (every connection), `WearAuthV2`
Input: `authKey` (16 B) from A or B.
1. **App verify (1/26)**: `{ appRandom = RAND(16), userId?: string, flag: bool }`.
   Error `4` = "device not bound".
2. Device replies `{ devRandom, devSign }`.
3. `okm = HKDF("miwear-auth", ikm=authKey, salt=appRandom‖devRandom, 64)`:
   `decKey = okm[0:16]`, `encKey = okm[16:32]`, `decIV = okm[32:36]`, `encIV = okm[36:40]`.
4. Check `HMAC(decKey, devRandom ‖ appRandom [‖ n]) == devSign`.
5. **App confirm (1/27)**:
   `{ HMAC(encKey, appRandom‖devRandom), CCM_ENC(encKey, nonce = encIV ‖ LE32(0) ‖ LE32(0), pb companionInfo{0, sdkInt, model, region, appCapability}) }`.
6. Device replies `{ ok, capability, capabilityV2, capabilityV3 }`.
   `CipherApiCall.updateKeys(decKey, encKey, decIV, encIV)` and the session is ready.

Later encrypted traffic goes through `CryptoHandlerV2.encryptDataV2/decryptDataV2`, keyed by the session keys above. **TODO**: confirm the per-packet nonce counter (most likely `IV ‖ LE32(counter) ‖ LE32(0)`).

## Legacy Huami family (Mi Band ≤7)
Separate stack: `com.huami.bluetooth.profile.channel.module.auth.AuthModule{,2}` plus native ECDH in `libdevice-encrypt.so`. Not yet analysed.

## Bind discovery: getBindInfo (1/17), mandatory first step

Every bind (account or local) starts with 1/17. The band silently ignores 1/18 until it has been asked this.

- Request `ab0.f11 = {1: bool checkDynamicCode, 2: bytes MD5(userId) (only when bindWithUserId)}`
- Response `ab0.f12 = {1: verifyMode, 2: sn, 3: mac, 4: model, 5: oobMode, 6: bytes deviceRandom, 7: did}`; `ab0.f3 = 1` means "already bound".
- verifyMode **2** → local ECDH bind (LocalWearBinderV2, needs no server; oobMode 0/2/3 supported).
- verifyMode **1** → PSK bind (PSKWearBinderV2). The band holds a factory pre-shared key known only to
  Xiaomi's server, so the server must take part in the first bind:
  1. server `applyBind(verifyMode, model, mac, randomMac, nodeId, sn, did, deviceRandom)` → challenge
  2. 1/18 `ab0.f13 = {1,2,3: bytes}` (server challenge) → band `ab0.f14 = {1: pubKey, 2: deviceSign}`
  3. server `verifyBind(bindIndex, did, pubKey, deviceSign, model)` → bind key
  4. 1/19 `ab0.f15 = {1: appRandom, 2: HMAC(key, appRandom‖oob), 3: bytes}` → band shows confirm (oobMode 3) →
     `ab0.f16 = {1: devRandom, 2: HMAC(key, devRandom‖oob), 3: bindSign}`
  5. server `confirmBind(locale, bindIndex, did, bindSign, model)` → then 1/25 result as in the local flow.
  After that, session auth (1/26–27) uses the per-device authKey from `user/get_bindkey`; no server is needed per session.

Observed on Smart Band 9 (`miwear.watch.n66gl`, fw transport 2.0.97): **verifyMode 1, oobMode 3**. A fully
offline first bind is therefore not possible on this model; "no account" means one server-assisted bind (or
key retrieval from an existing Mi Fitness bind), then fully offline use.

## Cloud API signing (health API, used to fetch a PSK band's auth key)

- Login: Xiaomi passport `pass/serviceLogin?sid=miothealth&_json=true` → `pass/serviceLoginAuth2`
  (`hash` = uppercase MD5 of the password, plus `callback`/`qs`/`_sign` echoed from step 1) → GET `location`
  sets the `serviceToken` cookie. The reply carries `ssecurity` and `userId`.
- Host: `https://hlth.io.mi.com/` for region cn, otherwise `https://{region}.hlth.io.mi.com/`.
  Cookies: `userId`, `cUserId`, `serviceToken`, `locale`.
- Per request: `_nonce` = b64(8 random bytes ‖ BE int32 minutes since epoch).
  `signedNonce` = b64(SHA-256(b64d(ssecurity) ‖ b64d(nonce))).
- Params (sorted, empty ones dropped) get `rc4_hash__` = b64(SHA-1("METHOD&/path&k=v…&signedNonce")).
  Every value is then encrypted with **one continuous** RC4 stream (key b64d(signedNonce), first 1024 bytes
  dropped), in sorted key order, and base64-encoded. `signature` is the same SHA-1 over the encrypted values.
  The response body is b64 RC4 ciphertext under a fresh stream with the same key.
- The signed path drops the service prefix: DeviceBindService (`healthapp/`) signs `/user/get_bindkey`;
  DeviceApiService (no prefix) signs `/app/v1/source/get_source_list`.
- `POST app/v1/source/get_source_list`, `data={"page_size":N,"page_start":…}` → `list[]` of devices.
  Each device's `detail` holds `auth_key`, `app_device_id`, `mac_address`, `encrypt_key`, `beaconkey`, and so on.
  `page_next` is the cursor.
- Session key source (Mi Fitness `DeviceModelExtKt`): Huami → `detail.auth_key`; local bind → `detail.token`;
  dual-core WearOS → `detail.app_token`; **Xiaomi Wear cloud bind → `detail.encrypt_key`** (hex, `ByteUtil.stringToBytes`).
  Observed Band 9 record has no `app_device_id`; WearAuthV2 then sends only hb0 field 1 (appRandom).

### PSK bind: server calls (`/healthapp/` prefix, signed path without it; byte fields are URL-safe base64)
- `POST bind/hello` data `{mode: verifyMode, model, mac, randomMac (= mac), phone_id, node_id: "", sn, did,
  random_d: sb0.f6, is_support_find}` → `{bind_index, bind_did, pub_s, random_s, sign_s}`.
- 1/18 `ab0.f13 = {1: pub_s, 2: sign_s, 3: random_s}` → `ab0.f14 = {1: pub_d, 2: sign_d}`.
- `POST bind/ecdh` data `{bind_index, bind_did, pub_d, sign_d}` → `{device_key (b64), oob_code (int), bind_key (string), …}`.
- 1/19 `ab0.f15 = {1: appRandom16, 2: HMAC(device_key, appRandom‖"%06d"(oob_code)), 3: UTF-8(bind_key)}`.
  The band asks the user to confirm, then replies `ab0.f16 = {1: devRandom, 2: HMAC(device_key, devRandom‖oob), 3: bind_sign}`.
  Error 6 = cancelled on the band; error 7 = app signature rejected.
- `POST bind/bind?locale=…` data `{bind_index, bind_did, bind_sign}` → `{success, ret}`.
- 1/25 `ab0.f29 = {1: CCM(device_key, nonce 10..1B, sc0{1: userId, 2: od0{1: 0, 2: sdk, 3: model, 4: appCapabilities}}, aad "bind-data")}`.
