#!/usr/bin/env python3
"""Build Loraneem Tech's launch-congratulations post for the office app.

This is a marketing-only artifact. It imports the already approved Arabic
HarfBuzz/FreeType renderer from the Loraneem appreciation campaign so every
Arabic letter and diacritic is rasterized from real Cairo glyph IDs.

Build from repository root:
  python3 -m pip install --target /tmp/posterdeps \
    pillow numpy qrcode uharfbuzz freetype-py
  PYTHONPATH=/tmp/posterdeps \
    python3 marketing/loraneem_launch_congrats/build_launch_post.py
"""
from __future__ import annotations

import sys
from pathlib import Path

SHARED_DIR = Path(__file__).resolve().parents[1] / "thanks_loraneem"
sys.path.insert(0, str(SHARED_DIR))

import build_thanks_post as shared  # noqa: E402
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path(__file__).resolve().parent
ASSETS = ROOT / "assets" / "images"

LORANEEM_LOGO = ASSETS / "loraneem_tech_logo.png"
OFFICE_LOGO = ASSETS / "logo_app.png"

ARABIC_STRINGS = (
    ("بكل فخر نبارك إطلاق تطبيق", "kufi", "Bold"),
    ("المكتب العقاري الإلكتروني", "cairo", "Black"),
    ("السويداء", "kufi", "Bold"),
    ("باكورة أعمالنا", "cairo", "Black"),
    ("أول فصل من رحلة تقنية نصنع فيها الأفكار واقعاً.", "cairo", "Bold"),
    ("مبارك للمكتب العقاري الإلكتروني — السويداء", "cairo", "SemiBold"),
)

NAVY = (4, 10, 27)
WHITE = (246, 249, 255)
MUTED = (169, 183, 204)
CYAN = (20, 226, 224)
GREEN = (37, 241, 172)
PURPLE = (128, 111, 255)
GOLD = (218, 177, 72)
GOLD_LIGHT = (255, 235, 167)


def _gradient_line(canvas: Image.Image, box: tuple[int, int, int, int],
                   colors: tuple[tuple[int, int, int], ...],
                   radius: int = 3) -> None:
    """Draw one crisp horizontal brand-gradient line."""
    x0, y0, x1, y1 = box
    width = max(1, x1 - x0)
    layer = shared.rgba_layer(canvas.size)
    draw = ImageDraw.Draw(layer)
    segments = len(colors) - 1
    for x in range(width):
        p = x / max(1, width - 1) * segments
        idx = min(segments - 1, int(p))
        t = p - idx
        a, b = colors[idx], colors[idx + 1]
        color = tuple(round(a[c] * (1 - t) + b[c] * t) for c in range(3))
        draw.line((x0 + x, y0, x0 + x, y1), fill=(*color, 235), width=1)
    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    canvas.alpha_composite(layer)


def _draw_loraneem_header(canvas: Image.Image) -> None:
    """Use the supplied Loraneem mark unmodified, uncropped, and unwarped."""
    box = (105, 72, 1335, 420)
    shared.rounded_panel(
        canvas, box, radius=42, fill=(3, 8, 25, 238),
        border_a=CYAN, border_b=PURPLE, border_width=2, glow=CYAN,
    )
    shared.paste_contained(canvas, LORANEEM_LOGO, (132, 91, 1308, 401))
    _gradient_line(canvas, (170, 414, 1270, 420), (CYAN, GREEN, PURPLE), 3)


def _draw_circuit_halo(canvas: Image.Image, center: tuple[int, int], radius: int) -> None:
    """A restrained AI/circuit halo framing the launched application."""
    cx, cy = center
    layer = shared.rgba_layer(canvas.size)
    draw = ImageDraw.Draw(layer)

    # Concentric brand rings.
    draw.ellipse((cx-radius, cy-radius, cx+radius, cy+radius),
                 outline=(*CYAN, 92), width=3)
    draw.ellipse((cx-radius+23, cy-radius+23, cx+radius-23, cy+radius-23),
                 outline=(*GOLD, 72), width=2)
    draw.arc((cx-radius-18, cy-radius-18, cx+radius+18, cy+radius+18),
             198, 326, fill=(*PURPLE, 210), width=5)
    draw.arc((cx-radius-18, cy-radius-18, cx+radius+18, cy+radius+18),
             18, 145, fill=(*GREEN, 210), width=5)

    # Symmetric circuit paths; the launch project is visibly connected to
    # Loraneem's identity without altering either supplied logo.
    paths = [
        [(cx-radius, cy-152), (205, cy-152), (205, cy-255), (118, cy-255)],
        [(cx-radius, cy+150), (250, cy+150), (250, cy+252), (155, cy+252)],
        [(cx+radius, cy-152), (1235, cy-152), (1235, cy-255), (1322, cy-255)],
        [(cx+radius, cy+150), (1190, cy+150), (1190, cy+252), (1285, cy+252)],
    ]
    for index, pts in enumerate(paths):
        color = CYAN if index in (0, 3) else PURPLE
        draw.line(pts, fill=(*color, 105), width=3, joint="curve")
        ex, ey = pts[-1]
        draw.ellipse((ex-7, ey-7, ex+7, ey+7), outline=(*color, 210), width=3)
        draw.ellipse((ex-2, ey-2, ex+2, ey+2), fill=(*WHITE, 230))

    # Delicate celebratory light points—not generic confetti.
    points = [(-410, -238), (-350, 270), (-300, -318), (318, -305),
              (390, 252), (440, -215), (-470, 70), (472, 82)]
    for i, (dx, dy) in enumerate(points):
        color = (GOLD_LIGHT, CYAN, GREEN, PURPLE)[i % 4]
        x, y = cx + dx, cy + dy
        draw.line((x-10, y, x+10, y), fill=(*color, 180), width=2)
        draw.line((x, y-10, x, y+10), fill=(*color, 180), width=2)
        draw.ellipse((x-2, y-2, x+2, y+2), fill=(*WHITE, 240))

    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(0.25)))


def _draw_project_hero(canvas: Image.Image) -> None:
    center = (720, 1002)
    _draw_circuit_halo(canvas, center, 332)

    shared.rounded_panel(
        canvas, (400, 682, 1040, 1322), radius=76,
        fill=(3, 7, 15, 246), border_a=GOLD_LIGHT, border_b=CYAN,
        border_width=4, glow=GOLD,
    )

    # Two soft glows behind the supplied square app identity.
    glow = shared.rgba_layer(canvas.size)
    glow_mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(glow_mask).ellipse((430, 712, 1010, 1292), fill=160)
    glow.putalpha(glow_mask.filter(ImageFilter.GaussianBlur(62)))
    color = Image.new("RGBA", canvas.size, (*GOLD, 0))
    color.putalpha(glow.getchannel("A"))
    canvas.alpha_composite(color)

    shared.paste_contained(canvas, OFFICE_LOGO, (448, 730, 992, 1274))


def _draw_launch_badge(canvas: Image.Image) -> None:
    box = (330, 1365, 1110, 1494)
    shared.rounded_panel(
        canvas, box, radius=64, fill=(6, 14, 30, 238),
        border_a=CYAN, border_b=PURPLE, border_width=3, glow=GREEN,
    )
    shared.draw_gradient_text(
        canvas, "باكورة أعمالنا", 1379, 58,
        GOLD_LIGHT, GOLD, family="cairo", weight="Black", glow_color=GOLD,
    )

    layer = shared.rgba_layer(canvas.size)
    draw = ImageDraw.Draw(layer)
    for x, color in ((360, CYAN), (1080, PURPLE)):
        draw.ellipse((x-7, 1422-7, x+7, 1422+7), fill=(*color, 240))
        draw.ellipse((x-17, 1422-17, x+17, 1422+17), outline=(*color, 80), width=2)
    canvas.alpha_composite(layer)


def _draw_footer(canvas: Image.Image) -> None:
    shared.draw_centered(
        canvas, "أول فصل من رحلة تقنية نصنع فيها الأفكار واقعاً.",
        1523, 35, WHITE, weight="Bold",
    )
    shared.draw_centered(
        canvas, "مبارك للمكتب العقاري الإلكتروني — السويداء",
        1592, 29, MUTED, weight="SemiBold",
    )
    shared.draw_divider(canvas, 1684, 700)

    layer = shared.rgba_layer(canvas.size)
    draw = ImageDraw.Draw(layer)
    latin_font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 23,
    )
    text = "CODE  •  AI  •  LIMITLESS EVOLUTION"
    bbox = draw.textbbox((0, 0), text, font=latin_font)
    x = (canvas.width - (bbox[2] - bbox[0])) // 2
    draw.text((x, 1712), text, font=latin_font, fill=(*CYAN, 205))
    canvas.alpha_composite(layer)


def build_feed() -> Image.Image:
    canvas = shared.base_background(1440, 1800)
    _draw_loraneem_header(canvas)

    shared.draw_centered(
        canvas, "بكل فخر نبارك إطلاق تطبيق", 442, 39,
        GOLD_LIGHT, family="kufi", weight="Bold",
    )
    shared.draw_centered(
        canvas, "المكتب العقاري الإلكتروني", 502, 58,
        WHITE, weight="Black", shadow=True,
    )
    shared.draw_centered(
        canvas, "السويداء", 578, 37,
        MUTED, family="kufi", weight="Bold",
    )

    _draw_project_hero(canvas)
    _draw_launch_badge(canvas)
    _draw_footer(canvas)
    return canvas.convert("RGB")


def _assert_arabic_glyph_coverage() -> None:
    """Fail the build if Cairo/Noto Kufi would emit a missing glyph."""
    for text, family, weight in ARABIC_STRINGS:
        face = shared.hb.Face(shared._font_bytes(family))
        hb_font = shared.hb.Font(face)
        hb_font.set_variations({"wght": shared.WEIGHT_VALUES[weight]})
        buffer = shared.hb.Buffer()
        buffer.add_str(text)
        buffer.guess_segment_properties()
        shared.hb.shape(hb_font, buffer, {"kern": True, "liga": True, "calt": True})
        missing = [info.codepoint for info in buffer.glyph_infos if info.codepoint == 0]
        if missing:
            raise RuntimeError(f"Missing Arabic glyph in: {text}")


def main() -> None:
    _assert_arabic_glyph_coverage()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    image = build_feed()
    png = OUT_DIR / "loraneem_congrats_feed_1440x1800.png"
    jpg = OUT_DIR / "loraneem_congrats_feed_1440x1800.jpg"
    image.save(png, "PNG", optimize=True)
    image.save(jpg, "JPEG", quality=95, subsampling=0, optimize=True,
               progressive=True)
    for output in (png, jpg):
        with Image.open(output) as check:
            if check.size != (1440, 1800):
                raise RuntimeError(f"Unexpected output size: {output} -> {check.size}")
    print(png)
    print(jpg)
    print(f"Arabic glyph coverage: {len(ARABIC_STRINGS)}/{len(ARABIC_STRINGS)}")


if __name__ == "__main__":
    main()
