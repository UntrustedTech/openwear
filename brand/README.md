# OpenWear icon

A band outline with an orange pulse running through it and out the other side, on the app's near-black background (`#0C0C0E`, band `#F2F0E9`, pulse `#FF5B1F`, the app's accent).

`make_icons.py` draws every icon from one set of coordinates. Change the design there and run `python3 brand/make_icons.py` (needs Pillow). It writes:

- **Android launcher:** adaptive icon (`drawable/ic_launcher_foreground.xml` over `@color/openwear_background`), a monochrome layer for themed icons, and PNG fallbacks in every `mipmap-*` folder (square and round).
- **Status bar:** `drawable/ic_stat_openwear.xml`, used by the band connection notification.
- **Splash:** the launcher foreground, used by `launch_background.xml` and the Android 12+ splash in `values-v31` / `values-night-v31`.
- **Band app:** `band-app/src/logo.png` (120 px, round).
- **Masters:** `openwear-icon.svg`, `openwear-icon-512.png` and `openwear-icon-full-1024.png`.

The in-app logo (`app/lib/ui/widgets/openwear_logo.dart`) paints the same geometry. Keep the two in step.
