#!/usr/bin/env python3
"""Render the 18-second visual proof for the voice-free 'Why choose us?' reel.

Dependencies:
  python3 -m pip install --target /tmp/reeldeps \
    pillow numpy imageio-ffmpeg opencv-python-headless arabic-reshaper python-bidi

Run:
  PYTHONPATH=/tmp/reeldeps python3 marketing/build_why_choose_preview.py
"""

from pathlib import Path
import math
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import arabic_reshaper
from bidi.algorithm import get_display
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parent
WORK = Path('/tmp/sweeda_why_choose')
WORK.mkdir(parents=True, exist_ok=True)
FPS = 30
DURATION = 18.0
W, H = 1080, 1920
OUT = ROOT / 'why_choose_preview_18s.mp4'
TEMP = WORK / 'why_choose_preview_silent.mp4'
FONT_PATH = Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
GOLD = (49, 174, 229)  # BGR
PALE_GOLD = (112, 212, 255)


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smooth(value):
    value = clamp(value)
    return value * value * (3 - 2 * value)


def ease_out(value):
    value = clamp(value)
    return 1 - (1 - value) ** 3


def lerp(a, b, amount):
    return a + (b - a) * amount


def shaped(text):
    return get_display(arabic_reshaper.reshape(text))


def load_font(size, style='Bold'):
    font = ImageFont.truetype(str(FONT_PATH), size)
    return font


def text_layer(lines, sizes, colors, spacing=20, stroke=2, max_width=970):
    canvas = Image.new('RGBA', (W, 720), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    prepared = []
    total = 0
    for text, size, color in zip(lines, sizes, colors):
        font = load_font(size)
        shown = shaped(text)
        box = draw.textbbox((0, 0), shown, font=font, stroke_width=stroke)
        width = box[2] - box[0]
        if width > max_width:
            new_size = max(38, round(size * max_width / width))
            font = load_font(new_size)
            box = draw.textbbox((0, 0), shown, font=font, stroke_width=stroke)
            width = box[2] - box[0]
        height = box[3] - box[1]
        prepared.append((shown, font, color, width, height, box[1]))
        total += height
    total += spacing * (len(prepared) - 1)
    y = (canvas.height - total) // 2
    for shown, font, color, width, height, top in prepared:
        x = (W - width) // 2
        draw.text(
            (x, y - top),
            shown,
            font=font,
            fill=color,
            stroke_width=stroke,
            stroke_fill=(0, 0, 0, 235),
        )
        y += height + spacing
    return cv2.cvtColor(np.array(canvas), cv2.COLOR_RGBA2BGRA)


def gold_cutout(source, box, include_white=False):
    x0, y0, x1, y1 = box
    crop = source[y0:y1, x0:x1].copy()
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    hue, sat, val = cv2.split(hsv)
    mask = (hue >= 5) & (hue <= 42) & (sat > 34) & (val > 42)
    if include_white:
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        mask |= gray > 170
    alpha = cv2.GaussianBlur(mask.astype(np.uint8) * 255, (0, 0), .6)
    result = cv2.cvtColor(crop, cv2.COLOR_BGR2BGRA)
    result[:, :, 3] = alpha
    return result


def add_rgba(destination, foreground, x, y, opacity=1.0):
    h, w = foreground.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(destination.shape[1], x + w), min(destination.shape[0], y + h)
    if x1 <= x0 or y1 <= y0:
        return
    fg = foreground[y0 - y:y1 - y, x0 - x:x1 - x]
    alpha = fg[:, :, 3:4].astype(np.float32) / 255 * opacity
    area = destination[y0:y1, x0:x1].astype(np.float32)
    destination[y0:y1, x0:x1] = np.clip(
        fg[:, :, :3].astype(np.float32) * alpha + area * (1 - alpha), 0, 255
    ).astype(np.uint8)


def add_scaled(destination, layer, center, scale=1.0, opacity=1.0, y_offset=0):
    if opacity <= 0:
        return
    width = max(1, round(layer.shape[1] * scale))
    height = max(1, round(layer.shape[0] * scale))
    resized = cv2.resize(layer, (width, height), interpolation=cv2.INTER_LANCZOS4)
    x = round(center[0] - width / 2)
    y = round(center[1] - height / 2 + y_offset)
    add_rgba(destination, resized, x, y, opacity)


def deform_wing(image, side, openness, bend, time_s):
    h, w = image.shape[:2]
    root_x = 169.0 if side == 'left' else 13.0
    root_y = 195.0
    yy, xx = np.indices((h, w), dtype=np.float32)
    source_x = root_x + (xx - root_x) / max(openness, .58)
    distance = np.clip(np.abs(source_x - root_x) / (w * .9), 0, 1)
    source_y = yy - bend * distance ** 1.55
    output = cv2.remap(
        image,
        source_x.astype(np.float32),
        source_y.astype(np.float32),
        cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 0),
    )
    if .45 <= time_s <= 1.65:
        progress = smooth((time_s - .45) / 1.2)
        tip = 2 if side == 'left' else w - 2
        center = lerp(root_x, tip, progress)
        band = np.exp(-((xx - center) / 14) ** 2)
        alpha = output[:, :, 3] / 255
        mix = (band * alpha * math.sin(math.pi * progress) * .22)[:, :, None]
        highlight = np.empty_like(output[:, :, :3], np.float32)
        highlight[:] = PALE_GOLD
        output[:, :, :3] = np.clip(
            output[:, :, :3] * (1 - mix) + highlight * mix, 0, 255
        ).astype(np.uint8)
    return output


def wing_motion(time_s):
    if time_s < .22:
        return .80, 15
    if time_s < .42:
        amount = smooth((time_s - .22) / .20)
        return lerp(.80, .75, amount), lerp(15, 20, amount)
    if time_s < 1.20:
        amount = ease_out((time_s - .42) / .78)
        return lerp(.75, 1.045, amount), lerp(20, -4, amount)
    if time_s < 1.58:
        amount = smooth((time_s - 1.20) / .38)
        return lerp(1.045, .994, amount), lerp(-4, 1, amount)
    amount = smooth((time_s - 1.58) / .30)
    return lerp(.994, 1.0, amount), lerp(1, 0, amount)


# Approved visual sources.
poster_02 = cv2.imread(str(ROOT / 'posts' / 'poster_02_publish.png'))
poster_09 = cv2.imread(str(ROOT / 'posts' / 'poster_09_archive.png'))
watermark_source = cv2.imread(str(ROOT / 'logo_watermark.png'))
wing_left = cv2.imread('/tmp/sweeda_reel_60/p10_left.png', cv2.IMREAD_UNCHANGED)
wing_right = cv2.imread('/tmp/sweeda_reel_60/p10_right.png', cv2.IMREAD_UNCHANGED)
brand_logo = cv2.imread('/tmp/sweeda_reel_60/p10_logo.png', cv2.IMREAD_UNCHANGED)

# Hero and evidence assets.
watermark = gold_cutout(watermark_source, (90, 115, 1150, 1075), include_white=False)
seller_icon = gold_cutout(poster_02, (65, 520, 345, 760))
buyer_icon = gold_cutout(poster_02, (415, 520, 720, 760))
shield_icon = gold_cutout(poster_09, (70, 940, 355, 1245))
lock_icon = gold_cutout(poster_09, (400, 940, 715, 1245))

hero_text = text_layer(
    ['ليش تختار', 'المكتب العقاري الإلكتروني؟'],
    [104, 78],
    [(244, 244, 244, 255), (246, 201, 86, 255)],
    spacing=26,
)
reality_text = text_layer(
    ['من قلب الواقع الفعلي', 'بالسويداء'],
    [86, 118],
    [(245, 245, 245, 255), (246, 201, 86, 255)],
    spacing=18,
)
problem_text = text_layer(
    ['درسنا مشاكل', 'البائع والمشتري'],
    [88, 108],
    [(245, 245, 245, 255), (246, 201, 86, 255)],
    spacing=18,
)
safety_text = text_layer(
    ['وصممنا خطوات عملية', 'الدقة والأمان أولاً'],
    [72, 106],
    [(245, 245, 245, 255), (246, 201, 86, 255)],
    spacing=22,
)
slogan = text_layer(
    ['أمان — دقة — مصداقية'], [48], [(222, 177, 73, 255)], spacing=0, max_width=700
)

rng = np.random.default_rng(950199)
noise = rng.normal(0, 1.15, (H, W, 1)).astype(np.float32)
yy, xx = np.indices((H, W), dtype=np.float32)
vignette = 1 - .30 * np.clip(((xx - W / 2) / (W * .72)) ** 2 + ((yy - H / 2) / (H * .78)) ** 2, 0, 1)
particles = [(rng.uniform(60, 1020), rng.uniform(250, 1700), rng.uniform(0, math.tau), rng.uniform(.7, 1.8)) for _ in range(34)]


def background(time_s):
    base = np.empty((H, W, 3), np.float32)
    base[:] = [8, 9, 11]
    base += noise
    base *= vignette[:, :, None]
    frame = np.clip(base, 0, 255).astype(np.uint8)
    for x, y, phase, radius in particles:
        alpha = .18 + .16 * math.sin(time_s * .8 + phase)
        py = int((y - time_s * (2 + radius)) % 1600 + 180)
        overlay = frame.copy()
        cv2.circle(overlay, (int(x), py), max(1, round(radius)), (70, 168, 220), -1, cv2.LINE_AA)
        frame = cv2.addWeighted(overlay, alpha, frame, 1 - alpha, 0)
    return frame


def header_layer(time_s, opening=False):
    canvas = np.zeros((330, 768, 4), np.uint8)
    openness, bend = wing_motion(time_s) if opening else (1.0, 0)
    left = deform_wing(wing_left, 'left', openness, bend, time_s)
    right = deform_wing(wing_right, 'right', openness, bend, max(0, time_s - 2 / FPS))
    destination = np.zeros((330, 768, 3), np.uint8)
    add_rgba(destination, left, 18, 35)
    add_rgba(destination, right, 568, 35)
    add_rgba(destination, brand_logo, 105, 58)
    alpha = np.max(destination, axis=2)
    canvas[:, :, :3] = destination
    canvas[:, :, 3] = np.clip(alpha * 1.7, 0, 255).astype(np.uint8)
    return canvas


def common_brand(frame, time_s, hero=False):
    header = header_layer(time_s, opening=hero)
    width = 1020 if hero else 760
    scale = width / header.shape[1]
    add_scaled(frame, header, (W // 2, 270 if hero else 190), scale, 1.0)
    add_scaled(frame, slogan, (W // 2, 1765), .76, .80)


def intro_scene(local):
    frame = background(local)
    common_brand(frame, local, hero=True)
    progress = smooth((local - .55) / .72)
    # Giant question mark as a quiet depth element.
    question = text_layer(['؟'], [410], [(190, 139, 36, 100)], stroke=0)
    add_scaled(frame, question, (W // 2, 1165), lerp(.82, 1.0, progress), .25 * progress)
    add_scaled(frame, hero_text, (W // 2, 1040), lerp(.93, 1.0, progress), progress, 20 * (1 - progress))
    line = round(350 * progress)
    cv2.line(frame, (W // 2 - line, 1390), (W // 2 + line, 1390), GOLD, 3, cv2.LINE_AA)
    return frame


def reality_scene(local):
    frame = background(local + 4.5)
    common_brand(frame, local)
    progress = smooth(local / .75)
    add_scaled(frame, watermark, (W // 2, 1030), lerp(.70, .78, progress), .18 * progress, 35 * (1 - progress))
    add_scaled(frame, reality_text, (W // 2, 920), lerp(.95, 1, progress), progress, 22 * (1 - progress))
    sweep = int(lerp(-180, W + 180, smooth(local / 2.5)))
    overlay = frame.copy()
    cv2.line(overlay, (sweep - 90, 520), (sweep + 90, 1470), PALE_GOLD, 10, cv2.LINE_AA)
    frame = cv2.addWeighted(overlay, .05, frame, .95, 0)
    return frame


def problem_scene(local):
    frame = background(local + 8.5)
    common_brand(frame, local)
    progress = smooth(local / .68)
    left_x = round(lerp(-160, 285, progress))
    right_x = round(lerp(W + 160, 795, progress))
    add_scaled(frame, seller_icon, (left_x, 1140), 1.28, progress)
    add_scaled(frame, buyer_icon, (right_x, 1140), 1.18, progress)
    line_progress = smooth((local - .55) / .85)
    start, end = (360, 1165), (720, 1165)
    middle = (round(lerp(start[0], end[0], line_progress)), start[1])
    cv2.line(frame, start, middle, GOLD, 5, cv2.LINE_AA)
    if line_progress > .75:
        cv2.circle(frame, (W // 2, 1165), 13, PALE_GOLD, -1, cv2.LINE_AA)
    add_scaled(frame, problem_text, (W // 2, 710), lerp(.95, 1, progress), progress, 18 * (1 - progress))
    return frame


def safety_scene(local):
    frame = background(local + 12.5)
    common_brand(frame, local)
    progress = smooth(local / .72)
    pulse = .5 + .5 * math.sin(max(0, local - .7) * math.pi * .8)
    add_scaled(frame, shield_icon, (300, 1140), lerp(.90, 1.12, progress), progress)
    add_scaled(frame, lock_icon, (780, 1140), lerp(.86, 1.06, progress), progress)
    if progress > .65:
        overlay = frame.copy()
        cv2.circle(overlay, (W // 2, 1140), round(270 + 35 * pulse), PALE_GOLD, 8, cv2.LINE_AA)
        frame = cv2.addWeighted(overlay, .06, frame, .94, 0)
    add_scaled(frame, safety_text, (W // 2, 710), lerp(.94, 1, progress), progress, 20 * (1 - progress))
    return frame


def gold_transition(first, second, amount, direction=1):
    amount = smooth(amount)
    x = np.arange(W, dtype=np.float32)
    center = lerp(-150, W + 150, amount) if direction > 0 else lerp(W + 150, -150, amount)
    mask = np.clip(((center - x) / 120 + .5) if direction > 0 else ((x - center) / 120 + .5), 0, 1)
    mask = (mask * mask * (3 - 2 * mask))[None, :, None]
    result = first * (1 - mask) + second * mask
    band = np.exp(-((x - center) / 52) ** 2)[None, :, None]
    gold = np.empty_like(result)
    gold[:] = PALE_GOLD
    return np.clip(result * (1 - band * .20) + gold * (band * .20), 0, 255).astype(np.uint8)


def frame_at(index):
    time_s = index / FPS
    scenes = [
        (0.0, 4.5, intro_scene),
        (4.5, 8.5, reality_scene),
        (8.5, 12.5, problem_scene),
        (12.5, 18.0, safety_scene),
    ]
    for scene_index, (start, end, renderer) in enumerate(scenes):
        if time_s < end or scene_index == len(scenes) - 1:
            local = time_s - start
            current = renderer(max(0, local))
            if scene_index < len(scenes) - 1 and time_s >= end - .45:
                following = scenes[scene_index + 1][2](0)
                return gold_transition(current, following, (time_s - (end - .45)) / .45, 1 if scene_index % 2 == 0 else -1)
            return current
    raise AssertionError('unreachable')


ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
command = [
    ffmpeg, '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-tune', 'stillimage', '-crf', '16', '-profile:v', 'high',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-t', str(DURATION), str(TEMP),
]
process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
try:
    for frame_index in range(round(DURATION * FPS)):
        process.stdin.write(frame_at(frame_index).tobytes())
finally:
    process.stdin.close()
stderr = process.stderr.read().decode('utf-8', 'replace')
if process.wait():
    print(stderr, file=sys.stderr)
    raise SystemExit(1)

# Temporary proof music comes from the office's previously approved original
# soundtrack. The final render swaps this stream for the selected CC BY track.
subprocess.run([
    ffmpeg, '-y', '-hide_banner', '-loglevel', 'error', '-i', str(TEMP),
    '-i', str(ROOT / 'reels_promo_60s.mp4'), '-map', '0:v:0', '-map', '1:a:0',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', str(DURATION),
    '-movflags', '+faststart', str(OUT),
], check=True)
print(OUT)
