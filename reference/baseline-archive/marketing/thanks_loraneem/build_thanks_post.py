#!/usr/bin/env python3
"""Build the approved Loraneem Tech appreciation feed post and story.

The script keeps both supplied brand marks unmodified and uses them only with
contain-style scaling. Arabic shaping dependencies are installed outside the
repository:

  python3 -m pip install --target /tmp/posterdeps \
    pillow numpy qrcode uharfbuzz freetype-py
  PYTHONPATH=/tmp/posterdeps python3 marketing/thanks_loraneem/build_thanks_post.py
"""
from __future__ import annotations

import math
import random
from functools import lru_cache
from pathlib import Path

import freetype
import numpy as np
import qrcode
import uharfbuzz as hb
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path(__file__).resolve().parent
ASSETS = ROOT / "assets" / "images"
FONT_DIR = OUT_DIR / "fonts"

CAIRO = FONT_DIR / "Cairo-Variable.ttf"
KUFI = FONT_DIR / "NotoKufiArabic-Variable.ttf"
MONO = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")

OFFICE_LOGO = ASSETS / "logo_app.png"
LORANEEM_LOGO = ASSETS / "loraneem_tech_logo.png"
FACEBOOK_URL = "https://www.facebook.com/loraneemtech"

GOLD = (218, 177, 72)
GOLD_LIGHT = (255, 235, 167)
WHITE = (245, 248, 255)
MUTED = (173, 185, 204)
CYAN = (20, 226, 224)
GREEN = (37, 241, 172)
PURPLE = (128, 111, 255)
NAVY = (5, 12, 31)


@lru_cache(maxsize=128)
def font(size: int, family: str = "cairo", weight: str = "Regular") -> ImageFont.FreeTypeFont:
    path = CAIRO if family == "cairo" else KUFI
    f = ImageFont.truetype(str(path), size=size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


WEIGHT_VALUES = {
    "ExtraLight": 200,
    "Light": 300,
    "Regular": 400,
    "Medium": 500,
    "SemiBold": 600,
    "Bold": 700,
    "ExtraBold": 800,
    "Black": 900,
}


@lru_cache(maxsize=4)
def _font_bytes(family: str) -> bytes:
    return (CAIRO if family == "cairo" else KUFI).read_bytes()


@lru_cache(maxsize=256)
def render_arabic_mask(text: str, size: int, family: str,
                       weight: str) -> Image.Image:
    """Shape and rasterize Arabic with HarfBuzz + FreeType.

    Pillow in the production sandbox has no libraqm. The former fallback used
    Unicode Presentation Forms, but Cairo intentionally omits several of those
    legacy code points; isolated alifs, waws and hamzas therefore appeared as
    narrow tofu rectangles. HarfBuzz shapes the original logical Arabic into
    actual font glyph IDs, preserving every letter, ligature and diacritic.
    """
    path = CAIRO if family == "cairo" else KUFI
    weight_value = WEIGHT_VALUES.get(weight, 400)

    hb_face = hb.Face(_font_bytes(family))
    hb_font = hb.Font(hb_face)
    hb_font.scale = (size * 64, size * 64)
    hb_font.set_variations({"wght": weight_value})

    buffer = hb.Buffer()
    buffer.add_str(text)
    buffer.guess_segment_properties()
    hb.shape(hb_font, buffer, {"kern": True, "liga": True, "calt": True})

    ft_face = freetype.Face(str(path))
    ft_face.set_pixel_sizes(0, size)
    try:
        coords = [weight_value, 0] if family == "cairo" else [weight_value]
        ft_face.set_var_design_coords(coords)
    except (AttributeError, freetype.FT_Exception):
        pass

    glyphs: list[tuple[int, int, np.ndarray]] = []
    pen_x = 0
    pen_y = 0
    load_flags = freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_NORMAL
    for info, pos in zip(buffer.glyph_infos, buffer.glyph_positions):
        ft_face.load_glyph(info.codepoint, load_flags)
        bitmap = ft_face.glyph.bitmap
        raw = np.asarray(bitmap.buffer, dtype=np.uint8)
        if bitmap.rows and bitmap.pitch:
            pixels = raw.reshape((bitmap.rows, abs(bitmap.pitch)))[:, :bitmap.width]
        else:
            pixels = np.zeros((0, 0), dtype=np.uint8)
        gx = round((pen_x + pos.x_offset) / 64) + ft_face.glyph.bitmap_left
        gy = -round((pen_y + pos.y_offset) / 64) - ft_face.glyph.bitmap_top
        glyphs.append((gx, gy, pixels))
        pen_x += pos.x_advance
        pen_y += pos.y_advance

    visible = [(gx, gy, pixels) for gx, gy, pixels in glyphs if pixels.size]
    if not visible:
        return Image.new("L", (1, 1), 0)
    min_x = min(gx for gx, _, _ in visible)
    max_x = max(gx + pixels.shape[1] for gx, _, pixels in visible)
    min_y = min(gy for _, gy, _ in visible)
    max_y = max(gy + pixels.shape[0] for _, gy, pixels in visible)
    pad = 3
    result = np.zeros((max_y - min_y + pad * 2,
                       max_x - min_x + pad * 2), dtype=np.uint8)
    for gx, gy, pixels in visible:
        x0 = gx - min_x + pad
        y0 = gy - min_y + pad
        roi = result[y0:y0 + pixels.shape[0], x0:x0 + pixels.shape[1]]
        np.maximum(roi, pixels, out=roi)
    return Image.fromarray(result, "L")


def rgba_layer(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, (0, 0, 0, 0))


def fit_contain(image: Image.Image, box: tuple[int, int]) -> Image.Image:
    """Scale proportionally without crop, stretch, color treatment, or masks."""
    copy = image.copy().convert("RGB")
    copy.thumbnail(box, Image.Resampling.LANCZOS)
    return copy


def centered_x(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont, width: int) -> int:
    box = draw.textbbox((0, 0), text, font=fnt, stroke_width=0)
    return int((width - (box[2] - box[0])) / 2 - box[0])


def _place_mask(mask: Image.Image, canvas_size: tuple[int, int],
                x: int, y: int) -> Image.Image:
    placed = Image.new("L", canvas_size, 0)
    placed.paste(mask, (x, y))
    return placed


def _color_mask(mask: Image.Image, color: tuple[int, int, int],
                opacity: float = 1.0) -> Image.Image:
    layer = Image.new("RGBA", mask.size, (*color, 0))
    layer.putalpha(mask.point(lambda p: round(p * opacity)))
    return layer


def draw_centered(
    canvas: Image.Image,
    text: str,
    y: int,
    size: int,
    color: tuple[int, int, int] = WHITE,
    *,
    family: str = "cairo",
    weight: str = "Bold",
    arabic: bool = True,
    shadow: bool = False,
    stroke: int = 0,
    stroke_fill: tuple[int, int, int] = (0, 0, 0),
) -> tuple[int, int, int, int]:
    if arabic:
        glyph_mask = render_arabic_mask(text, size, family, weight)
        x = (canvas.width - glyph_mask.width) // 2
        # Match Pillow's former top bearing so the approved composition keeps
        # its exact rhythm while HarfBuzz preserves marks above the letters.
        actual_y = y + round(size * .50)
        mask = _place_mask(glyph_mask, canvas.size, x, actual_y)
        if shadow:
            shadow_mask = mask.filter(ImageFilter.GaussianBlur(max(2, size / 24)))
            shadow_layer = _color_mask(shadow_mask, (0, 0, 0), .78)
            canvas.alpha_composite(shadow_layer, (0, max(2, size // 32)))
        if stroke:
            outline = mask.filter(ImageFilter.MaxFilter(stroke * 2 + 1))
            canvas.alpha_composite(_color_mask(outline, stroke_fill))
        canvas.alpha_composite(_color_mask(mask, color))
        return (x, actual_y, x + glyph_mask.width, actual_y + glyph_mask.height)

    layer = rgba_layer(canvas.size)
    d = ImageDraw.Draw(layer)
    fnt = font(size, family, weight)
    x = centered_x(d, text, fnt, canvas.width)
    box = d.textbbox((x, y), text, font=fnt, stroke_width=stroke)
    if shadow:
        glow = rgba_layer(canvas.size)
        gd = ImageDraw.Draw(glow)
        gd.text((x, y + max(2, size // 32)), text, font=fnt, fill=(0, 0, 0, 210),
                stroke_width=stroke + max(1, size // 45), stroke_fill=(0, 0, 0, 180))
        canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(max(2, size / 24))))
    d.text((x, y), text, font=fnt, fill=(*color, 255), stroke_width=stroke,
           stroke_fill=(*stroke_fill, 255))
    canvas.alpha_composite(layer)
    return box


def draw_gradient_text(
    canvas: Image.Image,
    text: str,
    y: int,
    size: int,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    *,
    family: str = "cairo",
    weight: str = "Black",
    arabic: bool = True,
    glow_color: tuple[int, int, int] | None = None,
) -> tuple[int, int, int, int]:
    if arabic:
        glyph_mask = render_arabic_mask(text, size, family, weight)
        x = (canvas.width - glyph_mask.width) // 2
        actual_y = y + round(size * .50)
        mask = _place_mask(glyph_mask, canvas.size, x, actual_y)
        box = (x, actual_y, x + glyph_mask.width, actual_y + glyph_mask.height)
    else:
        fnt = font(size, family, weight)
        mask = Image.new("L", canvas.size, 0)
        md = ImageDraw.Draw(mask)
        x = centered_x(md, text, fnt, canvas.width)
        box = md.textbbox((x, y), text, font=fnt)
        md.text((x, y), text, font=fnt, fill=255)

    if glow_color:
        blur = mask.filter(ImageFilter.GaussianBlur(max(5, size / 12)))
        canvas.alpha_composite(_color_mask(blur, glow_color, .22))

    # Normalize gradient to the actual text vertical extent, not the full image.
    top_y, bottom_y = max(0, box[1]), min(canvas.height - 1, box[3])
    rel = np.clip((np.arange(canvas.height)[:, None] - top_y) /
                  max(1, bottom_y - top_y), 0, 1).astype(np.float32)
    a = np.array(top, dtype=np.float32)
    b = np.array(bottom, dtype=np.float32)
    row = a[None, None, :] * (1 - rel[:, :, None]) + b[None, None, :] * rel[:, :, None]
    rgb = np.repeat(row, canvas.width, axis=1).astype(np.uint8)
    grad = Image.fromarray(rgb, "RGB").convert("RGBA")
    grad.putalpha(mask)
    canvas.alpha_composite(grad)
    return box


def base_background(width: int, height: int) -> Image.Image:
    """Premium black/navy base joining office gold with Loraneem cyan/purple."""
    y, x = np.ogrid[0:height, 0:width]
    arr = np.zeros((height, width, 3), dtype=np.float32)
    arr[:] = (4, 7, 15)

    # Vertical navy lift.
    v = (y / height).astype(np.float32)
    arr += np.dstack([
        np.broadcast_to(1.5 + 1.5 * v, (height, width)),
        np.broadcast_to(3.0 + 5.5 * v, (height, width)),
        np.broadcast_to(8.0 + 13.0 * v, (height, width)),
    ])

    def radial(cx: float, cy: float, radius: float, color: tuple[int, int, int], strength: float) -> None:
        dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / radius
        alpha = np.clip(1 - dist, 0, 1) ** 2 * strength
        nonlocal arr
        arr += alpha[..., None] * np.array(color, dtype=np.float32)

    radial(-0.04 * width, 0.12 * height, 0.72 * width, (235, 173, 45), 0.20)
    radial(1.04 * width, 0.42 * height, 0.78 * width, (0, 221, 222), 0.16)
    radial(0.84 * width, 0.80 * height, 0.60 * width, (107, 78, 255), 0.10)
    radial(0.34 * width, 0.98 * height, 0.58 * width, (20, 218, 169), 0.055)

    # Edge vignette.
    nx = (x - width / 2) / (width / 2)
    ny = (y - height / 2) / (height / 2)
    vignette = np.clip((nx * nx + ny * ny - 0.18) * 5.2, 0, 1)
    arr *= (1 - 0.31 * vignette[..., None])

    rng = np.random.default_rng(20260829 + width + height)
    arr += rng.normal(0, 1.18, arr.shape[:2])[..., None]
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    canvas = Image.fromarray(arr, "RGB").convert("RGBA")

    # Fine technical grid and diagonal glass facets.
    texture = rgba_layer((width, height))
    d = ImageDraw.Draw(texture)
    grid_start = int(height * 0.27)
    for gx in range(-width, width * 2, max(70, width // 14)):
        d.line((gx, grid_start, gx + int(height * 0.46), int(height * 0.76)),
               fill=(18, 198, 207, 13), width=1)
    for gy in range(grid_start, int(height * 0.78), max(70, height // 18)):
        d.line((0, gy, width, gy), fill=(111, 136, 171, 9), width=1)

    # Oversized premium arcs; deliberately subtle behind content.
    d.arc((-int(width * .45), -int(height * .17), int(width * .72), int(height * .62)),
          276, 79, fill=(*GOLD, 30), width=max(2, width // 600))
    d.arc((int(width * .48), int(height * .18), int(width * 1.39), int(height * .73)),
          92, 259, fill=(*CYAN, 24), width=max(2, width // 620))
    d.polygon([(0, int(height*.61)), (int(width*.42), int(height*.35)),
               (int(width*.79), int(height*.73)), (0, int(height*.91))],
              fill=(212, 170, 61, 7))
    d.polygon([(width, int(height*.32)), (int(width*.58), int(height*.58)),
               (width, int(height*.82))], fill=(22, 225, 218, 7))
    canvas.alpha_composite(texture)

    # Very faint binary/code rhythm around the hero zone.
    code = rgba_layer((width, height))
    cd = ImageDraw.Draw(code)
    mono = ImageFont.truetype(str(MONO), max(13, width // 82))
    random.seed(29082026 + width)
    for col in range(6):
        gx = int(width * (0.018 + col * .045)) if col < 3 else int(width * (.86 + (col-3)*.045))
        digits = "\n".join("".join(random.choice("01") for _ in range(2)) for _ in range(18))
        cd.multiline_text((gx, int(height*.31)), digits, font=mono,
                          fill=(18, 225, 219, 13), spacing=max(4, height // 250))
    canvas.alpha_composite(code.filter(ImageFilter.GaussianBlur(.25)))

    # Hairline frame.
    frame = rgba_layer((width, height))
    fd = ImageDraw.Draw(frame)
    inset = max(22, width // 44)
    fd.rounded_rectangle((inset, inset, width-inset, height-inset),
                         radius=max(32, width // 27), outline=(*GOLD, 43), width=max(1, width // 720))
    fd.line((inset + 65, inset, width * .45, inset), fill=(*GOLD_LIGHT, 115), width=2)
    fd.line((width * .60, height-inset, width-inset-65, height-inset), fill=(*CYAN, 78), width=2)
    canvas.alpha_composite(frame)
    return canvas


def rounded_panel(
    canvas: Image.Image,
    box: tuple[int, int, int, int],
    *,
    radius: int,
    fill: tuple[int, int, int, int],
    border_a: tuple[int, int, int],
    border_b: tuple[int, int, int] | None = None,
    border_width: int = 2,
    shadow_color: tuple[int, int, int] = (0, 0, 0),
    glow: tuple[int, int, int] | None = None,
) -> None:
    x0, y0, x1, y1 = box
    mask = Image.new("L", canvas.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(box, radius=radius, fill=255)

    shadow_mask = mask.filter(ImageFilter.GaussianBlur(max(12, radius // 2)))
    shadow = Image.new("RGBA", canvas.size, (*shadow_color, 0))
    shadow.putalpha(shadow_mask.point(lambda p: int(p * .38)))
    canvas.alpha_composite(shadow)

    if glow:
        outer = mask.filter(ImageFilter.GaussianBlur(max(22, radius)))
        glow_layer = Image.new("RGBA", canvas.size, (*glow, 0))
        glow_layer.putalpha(outer.point(lambda p: int(p * .12)))
        canvas.alpha_composite(glow_layer)

    fill_layer = Image.new("RGBA", canvas.size, fill)
    fill_layer.putalpha(ImageChops.multiply(mask, fill_layer.getchannel("A")))
    canvas.alpha_composite(fill_layer)

    outer = mask
    inner = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(inner).rounded_rectangle(
        (x0 + border_width, y0 + border_width, x1 - border_width, y1 - border_width),
        radius=max(0, radius - border_width), fill=255)
    rim = ImageChops.subtract(outer, inner)
    if border_b:
        grad = np.zeros((canvas.height, canvas.width, 4), dtype=np.uint8)
        start, end = np.array(border_a), np.array(border_b)
        for px in range(max(0, x0), min(canvas.width, x1 + 1)):
            t = (px - x0) / max(1, x1 - x0)
            grad[:, px, :3] = (start * (1-t) + end * t).astype(np.uint8)
            grad[:, px, 3] = 255
        border = Image.fromarray(grad, "RGBA")
    else:
        border = Image.new("RGBA", canvas.size, (*border_a, 255))
    border.putalpha(rim)
    canvas.alpha_composite(border)


def paste_contained(canvas: Image.Image, path: Path, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    original = Image.open(path)
    fitted = fit_contain(original, (x1-x0, y1-y0))
    x = x0 + (x1-x0-fitted.width)//2
    y = y0 + (y1-y0-fitted.height)//2
    canvas.alpha_composite(fitted.convert("RGBA"), (x, y))


def draw_sender(canvas: Image.Image, box: tuple[int, int, int, int], logo_size: int,
                title_size: int, sub_size: int) -> None:
    rounded_panel(canvas, box, radius=max(22, logo_size//3),
                  fill=(7, 9, 16, 198), border_a=(215, 174, 69),
                  border_b=(108, 88, 39), border_width=2)
    x0, y0, x1, y1 = box
    logo_box = (x1-logo_size-24, y0+(y1-y0-logo_size)//2,
                x1-24, y0+(y1-y0-logo_size)//2+logo_size)
    paste_contained(canvas, OFFICE_LOGO, logo_box)

    title_mask = render_arabic_mask(
        "المكتب العقاري الإلكتروني", title_size, "cairo", "Bold")
    subtitle_mask = render_arabic_mask(
        "السويداء  •  أمان — دقة — مصداقية", sub_size, "cairo", "SemiBold")
    tx = logo_box[0] - 25
    title_y = y0 + int((y1-y0)*.23)
    subtitle_y = y0 + int((y1-y0)*.61)
    canvas.alpha_composite(_color_mask(title_mask, WHITE),
                           (tx-title_mask.width, title_y))
    canvas.alpha_composite(_color_mask(subtitle_mask, GOLD, .94),
                           (tx-subtitle_mask.width, subtitle_y))


def draw_divider(canvas: Image.Image, y: int, width: int) -> None:
    layer = rgba_layer(canvas.size)
    d = ImageDraw.Draw(layer)
    cx = canvas.width // 2
    half = width // 2
    d.line((cx-half, y, cx-18, y), fill=(*GOLD, 130), width=2)
    d.line((cx+18, y, cx+half, y), fill=(*CYAN, 105), width=2)
    d.polygon([(cx, y-8), (cx+8, y), (cx, y+8), (cx-8, y)], fill=(*GOLD_LIGHT, 240))
    d.ellipse((cx-2, y-2, cx+2, y+2), fill=(255, 255, 255, 255))
    canvas.alpha_composite(layer)


def draw_badge(canvas: Image.Image, box: tuple[int, int, int, int], size: int) -> None:
    rounded_panel(canvas, box, radius=(box[3]-box[1])//2,
                  fill=(11, 17, 29, 225), border_a=GOLD,
                  border_b=CYAN, border_width=2, glow=(26, 223, 215))
    text_mask = render_arabic_mask(
        "شركاء النجاح التقني", size, "kufi", "Bold")
    cx = (box[0] + box[2]) // 2
    cy = (box[1] + box[3]) // 2
    canvas.alpha_composite(_color_mask(text_mask, GOLD_LIGHT),
                           (cx-text_mask.width//2, cy-text_mask.height//2))


def draw_phone_icon(draw: ImageDraw.ImageDraw, cx: int, cy: int, scale: float,
                    color: tuple[int, int, int, int]) -> None:
    # Minimal handset icon drawn from two rounded capsules and a connecting arc.
    w = max(3, int(5 * scale))
    draw.arc((cx-int(16*scale), cy-int(18*scale), cx+int(15*scale), cy+int(18*scale)),
             112, 253, fill=color, width=w)
    draw.rounded_rectangle((cx-int(14*scale), cy-int(18*scale), cx-int(4*scale), cy-int(7*scale)),
                           radius=max(2, int(3*scale)), fill=color)
    draw.rounded_rectangle((cx+int(4*scale), cy+int(7*scale), cx+int(14*scale), cy+int(18*scale)),
                           radius=max(2, int(3*scale)), fill=color)


def draw_contact_panel(canvas: Image.Image, box: tuple[int, int, int, int], *,
                       label_y: int, numbers_y: int, fb_y: int,
                       label_size: int, number_size: int, fb_size: int,
                       qr_box: tuple[int, int, int, int] | None = None,
                       qr_label_y: int | None = None) -> None:
    rounded_panel(canvas, box, radius=max(26, (box[3]-box[1])//9),
                  fill=(5, 11, 25, 226), border_a=GOLD,
                  border_b=PURPLE, border_width=2, glow=(31, 224, 213))
    draw_centered(canvas, "للتواصل مع فريق التطوير", label_y, label_size,
                  GOLD_LIGHT, weight="Bold")

    layer = rgba_layer(canvas.size)
    d = ImageDraw.Draw(layer)
    nums = "0933713023   •   0938862469"
    nf = font(number_size, "cairo", "Bold")
    nx = centered_x(d, nums, nf, canvas.width)
    nb = d.textbbox((nx, numbers_y), nums, font=nf)
    icon_x = max(box[0] + 45, nx - int(number_size*.65))
    draw_phone_icon(d, icon_x, numbers_y + int(number_size*.58), number_size/38,
                    (*GREEN, 255))
    d.text((nx, numbers_y), nums, font=nf, fill=(*WHITE, 255))

    fb = "facebook.com/loraneemtech"
    ff = font(fb_size, "cairo", "SemiBold")
    fx = centered_x(d, fb, ff, canvas.width)
    d.ellipse((fx-int(fb_size*.78), fb_y+int(fb_size*.18),
               fx-int(fb_size*.12), fb_y+int(fb_size*.84)),
              outline=(*CYAN, 255), width=max(2, fb_size//13))
    f_icon = font(max(13, int(fb_size*.58)), "cairo", "Black")
    d.text((fx-int(fb_size*.45), fb_y+int(fb_size*.51)), "f", font=f_icon,
           fill=(*CYAN, 255), anchor="mm")
    d.text((fx, fb_y), fb, font=ff, fill=(*CYAN, 255))
    canvas.alpha_composite(layer)

    if qr_box:
        qr = qrcode.QRCode(version=None, box_size=10, border=2,
                           error_correction=qrcode.constants.ERROR_CORRECT_H)
        qr.add_data(FACEBOOK_URL)
        qr.make(fit=True)
        qr_img = qr.make_image(fill_color="#071323", back_color="#ffffff").convert("RGB")
        x0, y0, x1, y1 = qr_box
        qsize = min(x1-x0, y1-y0)
        qr_img = qr_img.resize((qsize, qsize), Image.Resampling.NEAREST)
        qpanel = (x0-10, y0-10, x0+qsize+10, y0+qsize+10)
        rounded_panel(canvas, qpanel, radius=18, fill=(255,255,255,255),
                      border_a=CYAN, border_b=GREEN, border_width=3,
                      glow=CYAN)
        canvas.alpha_composite(qr_img.convert("RGBA"), (x0, y0))
        if qr_label_y is not None:
            draw_centered(canvas, "امسح الرمز لمتابعة صفحة لورانيم", qr_label_y,
                          max(20, fb_size-5), MUTED, weight="SemiBold")


def logo_panel(canvas: Image.Image, box: tuple[int, int, int, int], padding: int) -> None:
    rounded_panel(canvas, box, radius=max(28, (box[3]-box[1])//14),
                  fill=(4, 10, 27, 244), border_a=GOLD,
                  border_b=PURPLE, border_width=3, glow=CYAN)
    x0, y0, x1, y1 = box
    # Gold sender identity flows into cyan/purple developer identity.
    accent = rgba_layer(canvas.size)
    ad = ImageDraw.Draw(accent)
    ad.line((x0+40, y0, (x0+x1)//2, y0), fill=(*GOLD_LIGHT, 230), width=4)
    ad.line(((x0+x1)//2, y0, x1-40, y0), fill=(*CYAN, 220), width=4)
    canvas.alpha_composite(accent)
    paste_contained(canvas, LORANEEM_LOGO,
                    (x0+padding, y0+padding, x1-padding, y1-padding))


def build_feed() -> Image.Image:
    w, h = 1440, 1800
    canvas = base_background(w, h)

    draw_sender(canvas, (260, 62, 1180, 166), logo_size=82,
                title_size=30, sub_size=20)
    draw_centered(canvas, "رسالة شكر وتقدير", 210, 31, GOLD,
                  family="kufi", weight="SemiBold")
    draw_centered(canvas, "لم يكتبوا كوداً فقط…", 278, 67, WHITE,
                  weight="Black", shadow=True)
    draw_gradient_text(canvas, "بل حوّلوا رؤيتنا إلى واقع.", 382, 72,
                       GOLD_LIGHT, GOLD, family="cairo", weight="Black",
                       glow_color=GOLD)
    draw_divider(canvas, 518, 680)
    draw_centered(canvas, "كل الشكر والتقدير لفريق تطوير", 550, 40,
                  MUTED, weight="Bold")

    logo_panel(canvas, (112, 632, 1328, 1166), padding=48)

    draw_centered(canvas, "على جهودهم في تطوير تطبيق", 1206, 33,
                  MUTED, weight="SemiBold")
    draw_centered(canvas, "المكتب العقاري الإلكتروني", 1260, 46,
                  WHITE, weight="Black")
    draw_badge(canvas, (445, 1345, 995, 1426), 28)

    draw_contact_panel(canvas, (175, 1480, 1265, 1708),
                       label_y=1510, numbers_y=1562, fb_y=1632,
                       label_size=27, number_size=40, fb_size=29)
    draw_centered(canvas, "شكراً لأنكم كنتم جزءاً من الحكاية", 1732, 23,
                  (141, 151, 169), weight="SemiBold")
    return canvas.convert("RGB")


def build_story() -> Image.Image:
    w, h = 1080, 1920
    canvas = base_background(w, h)

    draw_sender(canvas, (145, 78, 935, 184), logo_size=82,
                title_size=28, sub_size=18)
    draw_centered(canvas, "رسالة شكر وتقدير", 228, 27, GOLD,
                  family="kufi", weight="SemiBold")
    draw_centered(canvas, "لم يكتبوا كوداً فقط…", 300, 53, WHITE,
                  weight="Black", shadow=True)
    draw_gradient_text(canvas, "بل حوّلوا رؤيتنا إلى واقع.", 390, 57,
                       GOLD_LIGHT, GOLD, weight="Black", glow_color=GOLD)
    draw_divider(canvas, 500, 560)
    draw_centered(canvas, "كل الشكر والتقدير لفريق تطوير", 535, 32,
                  MUTED, weight="Bold")

    logo_panel(canvas, (68, 612, 1012, 1042), padding=32)

    draw_centered(canvas, "على جهودهم في تطوير تطبيق", 1080, 28,
                  MUTED, weight="SemiBold")
    draw_centered(canvas, "المكتب العقاري الإلكتروني", 1130, 38,
                  WHITE, weight="Black")
    draw_badge(canvas, (322, 1212, 758, 1282), 24)

    draw_contact_panel(canvas, (105, 1342, 975, 1810),
                       label_y=1373, numbers_y=1426, fb_y=1492,
                       label_size=24, number_size=33, fb_size=25,
                       qr_box=(455, 1570, 625, 1740), qr_label_y=1760)
    draw_centered(canvas, "شكراً لأنكم كنتم جزءاً من الحكاية", 1840, 20,
                  (141, 151, 169), weight="SemiBold")
    return canvas.convert("RGB")


def save_pair(image: Image.Image, stem: str) -> None:
    png = OUT_DIR / f"{stem}.png"
    jpg = OUT_DIR / f"{stem}.jpg"
    image.save(png, "PNG", optimize=True)
    image.save(jpg, "JPEG", quality=95, subsampling=0, optimize=True,
               progressive=True)
    print(png)
    print(jpg)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    save_pair(build_feed(), "loraneem_thanks_feed_1440x1800")
    save_pair(build_story(), "loraneem_thanks_story_1080x1920")


if __name__ == "__main__":
    main()
