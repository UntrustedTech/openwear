# OpenWear band app

A Xiaomi Vela quick app (.rpk) that runs on the band itself. Confirmed
installing and running on a Smart Band 9 (192×490 screen) on 2026-11-02.

Build (Node 18):

    npm install
    npx aiot build        # dist/org.openwear.band.debug.<version>.rpk

The debug build is signed with aiot-toolkit's built-in key, which the band
accepts. Install it from OpenWear: Settings → Apps → Install app (.rpk).

Reference: https://iot.mi.com/vela/quickapp/ (Xiaomi Vela JS app docs).
