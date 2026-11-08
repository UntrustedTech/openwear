#!/usr/bin/env python3
"""Builds the README banner and promo images from the rendered screens.

First render the screens (sample data only):
    cd app && flutter test tool/screenshots_test.dart
Then:
    python3 brand/make_promo.py

Writes brand/promo/*.png. Needs Pillow.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SCREENS = ROOT / "brand/screens"
OUT = ROOT / "brand/promo"
FONTS = ROOT / "app/assets/fonts"

BACKGROUND = (12, 12, 14)
TEXT = (242, 240, 233)
MUTED = (150, 148, 142)
ACCENT = (255, 91, 31)


def font(weight, size):
    name = {"regular": "Regular", "medium": "Medium", "bold": "Bold"}[weight]
    return ImageFont.truetype(str(FONTS / f"SpaceGrotesk-{name}.ttf"), size)


def mono(size):
    return ImageFont.truetype(str(FONTS / "JetBrainsMono-Medium.ttf"), size)


def phone(screen, width):
    """[screen] in a rounded phone body with a soft shadow, [width] px wide."""
    shot = Image.open(SCREENS / f"{screen}.png").convert("RGB")
    height = round(shot.height * width / shot.width)
    shot = shot.resize((width, height), Image.LANCZOS)
    bezel = max(6, width // 40)
    radius = width // 7
    w, h = width + 2 * bezel, height + 2 * bezel
    pad = width // 10
    out = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad + pad // 3, pad + w, pad + h + pad // 3),
        radius + bezel,
        fill=(0, 0, 0, 170),
    )
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(pad // 2)))
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        (0, 0, w - 1, h - 1), radius + bezel, fill=(32, 32, 36, 255),
        outline=(70, 70, 76, 255), width=2,
    )
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, shot.width - 1, shot.height - 1), radius, fill=255
    )
    body.paste(shot, (bezel, bezel), mask)
    out.alpha_composite(body, (pad, pad))
    return out


def glow(img, center, radius, color, alpha):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    x, y = center
    ImageDraw.Draw(layer).ellipse(
        (x - radius, y - radius, x + radius, y + radius), fill=(*color, alpha)
    )
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius // 2)))


def banner():
    W, H = 2400, 1260
    img = Image.new("RGBA", (W, H), (*BACKGROUND, 255))
    glow(img, (1700, 700), 520, ACCENT, 60)
    logo = Image.open(ROOT / "brand/openwear-icon-512.png").convert("RGBA")
    img.alpha_composite(logo.resize((150, 150), Image.LANCZOS), (150, 300))
    d = ImageDraw.Draw(img)
    d.text((150, 490), "OpenWear", font=font("bold", 132), fill=TEXT)
    d.text(
        (154, 650),
        "Your Xiaomi band, without the cloud.",
        font=font("regular", 54),
        fill=MUTED,
    )
    y = 780
    for line in (
        "Health data stays on your phone",
        "Notifications, calls, weather, music",
        "60+ watch faces, Health Connect",
    ):
        d.ellipse((158, y + 22, 176, y + 40), fill=ACCENT)
        d.text((200, y), line, font=font("medium", 40), fill=TEXT)
        y += 70
    d.text(
        (154, 1080),
        "OPEN SOURCE  ·  GPL-3.0  ·  ANDROID",
        font=mono(30),
        fill=MUTED,
    )
    for screen, x, y, w in (
        ("health-dark", 1180, 170, 470),
        ("sleep-dark", 1840, 170, 470),
        ("today-dark", 1460, 80, 540),
    ):
        img.alpha_composite(phone(screen, w), (x, y))
    img.convert("RGB").save(OUT / "banner.png", optimize=True)


def row(name, screens, title, caption):
    W, H = 2400, 1500
    img = Image.new("RGBA", (W, H), (*BACKGROUND, 255))
    glow(img, (W // 2, 900), 700, ACCENT, 38)
    d = ImageDraw.Draw(img)
    tw = d.textlength(title, font=font("bold", 76))
    d.text(((W - tw) / 2, 70), title, font=font("bold", 76), fill=TEXT)
    cw = d.textlength(caption, font=font("regular", 40))
    d.text(((W - cw) / 2, 175), caption, font=font("regular", 40), fill=MUTED)
    width = 520
    shots = [phone(s, width) for s in screens]
    gap = 10
    total = sum(s.width for s in shots) + gap * (len(shots) - 1)
    x = (W - total) // 2
    for s in shots:
        img.alpha_composite(s, (x, 250))
        x += s.width + gap
    img.convert("RGB").save(OUT / f"{name}.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    banner()
    row(
        "health",
        ["today-dark", "heart-rate-dark", "sleep-dark"],
        "Everything at a glance",
        "Steps, heart rate and sleep stages, straight from the band",
    )
    row(
        "band",
        ["faces-dark", "settings-dark", "health-dark"],
        "Your band, your way",
        "Watch faces, band settings, Find band and more",
    )
    row(
        "light-and-dark",
        ["today-light", "today-dark", "health-light"],
        "Light and dark",
        "Follows your phone, with accent colours and a pure-black option",
    )
    print("promo images written to", OUT)
