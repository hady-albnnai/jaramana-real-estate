#!/usr/bin/env python3
"""Build the complete voice-free 60-second 'Why choose us?' marketing reel.

The approved 18-second opening is reused byte-for-byte visually. This renderer
creates scenes 05-14, then muxes either the selected Pixabay-licensed music
(when present) or the office's original temporary score for visual approval.

Dependencies:
  python3 -m pip install --target /tmp/reeldeps \
    pillow numpy imageio-ffmpeg opencv-python-headless arabic-reshaper python-bidi

Run:
  PYTHONPATH=/tmp/reeldeps python3 marketing/build_why_choose_reel.py
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
WORK = Path('/tmp/sweeda_why_choose_full')
WORK.mkdir(parents=True, exist_ok=True)
FPS = 30
DURATION = 60.0
W, H = 1080, 1920
OUT = ROOT / 'why_choose_reel_60s.mp4'
TEMP = WORK / 'why_choose_reel_silent.mp4'
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


def font(size):
    return ImageFont.truetype(str(FONT_PATH), size)


def text_layer(lines, sizes, colors, spacing=18, stroke=2, max_width=970):
    canvas = Image.new('RGBA', (W, 660), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    prepared = []
    total = 0
    for text, size, color in zip(lines, sizes, colors):
        current_font = font(size)
        shown = shaped(text)
        bounds = draw.textbbox((0, 0), shown, font=current_font, stroke_width=stroke)
        width = bounds[2] - bounds[0]
        if width > max_width:
            size = max(38, round(size * max_width / width))
            current_font = font(size)
            bounds = draw.textbbox((0, 0), shown, font=current_font, stroke_width=stroke)
            width = bounds[2] - bounds[0]
        height = bounds[3] - bounds[1]
        prepared.append((shown, current_font, color, width, height, bounds[1]))
        total += height
    total += spacing * (len(prepared) - 1)
    y = (canvas.height - total) // 2
    for shown, current_font, color, width, height, top in prepared:
        x = (W - width) // 2
        draw.text(
            (x, y - top), shown, font=current_font, fill=color,
            stroke_width=stroke, stroke_fill=(0, 0, 0, 235),
        )
        y += height + spacing
    return cv2.cvtColor(np.array(canvas), cv2.COLOR_RGBA2BGRA)


def gold_cutout(source, box, include_white=False):
    x0, y0, x1, y1 = box
    crop = source[y0:y1, x0:x1].copy()
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    hue, sat, val = cv2.split(hsv)
    mask = (hue >= 5) & (hue <= 42) & (sat > 30) & (val > 38)
    if include_white:
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        mask |= gray > 165
    alpha = cv2.GaussianBlur(mask.astype(np.uint8) * 255, (0, 0), .65)
    result = cv2.cvtColor(crop, cv2.COLOR_BGR2BGRA)
    result[:, :, 3] = alpha
    return result


def rectangle_layer(source, box, feather=18):
    x0, y0, x1, y1 = box
    crop = source[y0:y1, x0:x1].copy()
    h, w = crop.shape[:2]
    yy, xx = np.indices((h, w))
    edge = np.minimum.reduce([xx, w - 1 - xx, yy, h - 1 - yy]).astype(np.float32)
    alpha = smooth_array(np.clip(edge / max(1, feather), 0, 1))
    result = cv2.cvtColor(crop, cv2.COLOR_BGR2BGRA)
    result[:, :, 3] = (alpha * 255).astype(np.uint8)
    return result


def smooth_array(values):
    return values * values * (3 - 2 * values)


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


# Source artwork.
def poster(number):
    return cv2.imread(str(next((ROOT / 'posts').glob(f'poster_{number:02d}_*.png'))))


p02, p03, p05, p06, p07, p08, p09, p10 = [poster(n) for n in (2, 3, 5, 6, 7, 8, 9, 10)]
watermark_source = cv2.imread(str(ROOT / 'logo_watermark.png'))

header = gold_cutout(p10, (15, 20, 753, 315), include_white=True)
watermark = gold_cutout(watermark_source, (90, 115, 1150, 1075))
phone = rectangle_layer(p10, (205, 545, 563, 1248), 24)
contact = rectangle_layer(p10, (155, 1240, 615, 1373), 16)

# Feature evidence assets, all cut from approved campaign artwork.
publish_camera = gold_cutout(p02, (60, 825, 350, 1080))
publish_house = gold_cutout(p02, (60, 515, 350, 765))
photo_camera = gold_cutout(p06, (70, 510, 390, 860))
photo_gallery = gold_cutout(p06, (370, 510, 710, 860))
calendar = gold_cutout(p03, (145, 385, 515, 675))
bell = gold_cutout(p03, (510, 385, 880, 675))
representative = gold_cutout(p03, (145, 680, 520, 980))
handshake = gold_cutout(p07, (45, 425, 365, 775))
price_deal = gold_cutout(p07, (400, 425, 730, 775))
document = gold_cutout(p07, (395, 735, 730, 1100))
contract = gold_cutout(p07, (40, 735, 375, 1100))
scales = gold_cutout(p05, (35, 645, 365, 950))
lawyers = gold_cutout(p05, (395, 645, 730, 950))
commission = gold_cutout(p07, (395, 745, 735, 1110))
transfer_key = gold_cutout(p08, (495, 620, 740, 920))
transfer_stamp = gold_cutout(p08, (495, 835, 740, 1085))

# Text cards.
texts = {
    'publish': text_layer(['صوّر وانشر بنفسك', 'أو ارفع الصور والمعلومات'], [92, 66], [(246, 201, 86, 255), (245, 245, 245, 255)]),
    'photo': text_layer(['أو اطلب مصوّر المكتب', 'تصوير احترافي ورفع الإعلان عنك'], [88, 62], [(246, 201, 86, 255), (245, 245, 245, 255)]),
    'appointment': text_layer(['احجز المعاينة إلكترونياً', 'ضمن الأوقات المتاحة'], [84, 78], [(245, 245, 245, 255), (246, 201, 86, 255)]),
    'representative': text_layer(['مندوب من المكتب', 'في كل موعد معاينة مؤكد'], [96, 70], [(246, 201, 86, 255), (245, 245, 245, 255)]),
    'negotiation': text_layer(['التفاوض النهائي', 'داخل مكتبنا'], [100, 112], [(245, 245, 245, 255), (246, 201, 86, 255)]),
    'documents': text_layer(['وثائق واضحة ومدروسة', 'مو على الكلام'], [84, 100], [(245, 245, 245, 255), (246, 201, 86, 255)]),
    'contracts': text_layer(['عقود ينظّمها', 'محامون مختصون'], [96, 100], [(245, 245, 245, 255), (246, 201, 86, 255)]),
    'commission': text_layer(['كلها ضمن عمولة المكتب', 'عند إتمام الصفقة'], [76, 88], [(245, 245, 245, 255), (246, 201, 86, 255)]),
    'transfer': text_layer(['نقل الملكية', 'عبر مختصين وبأتعاب مخفضة'], [112, 68], [(246, 201, 86, 255), (245, 245, 245, 255)]),
    'cta': text_layer(['حمّل التطبيق الآن', 'للتواصل: 0958750199'], [108, 74], [(246, 201, 86, 255), (245, 245, 245, 255)]),
}
slogan = text_layer(['أمان — دقة — مصداقية'], [48], [(222, 177, 73, 255)], max_width=700)

rng = np.random.default_rng(950200)
noise = rng.normal(0, 1.15, (H, W, 1)).astype(np.float32)
yy, xx = np.indices((H, W), dtype=np.float32)
vignette = 1 - .30 * np.clip(((xx - W / 2) / (W * .72)) ** 2 + ((yy - H / 2) / (H * .78)) ** 2, 0, 1)
particles = [(rng.uniform(55, 1025), rng.uniform(230, 1720), rng.uniform(0, math.tau), rng.uniform(.7, 1.8)) for _ in range(38)]


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
    add_scaled(frame, watermark, (W // 2, 1110), .77, .055)
    return frame


def common(frame, time_s, final=False):
    width = 820 if not final else 1010
    add_scaled(frame, header, (W // 2, 190 if not final else 255), width / header.shape[1], 1)
    if not final:
        add_scaled(frame, slogan, (W // 2, 1760), .76, .82)


def pulse(local, start, duration=.70):
    amount = (local - start) / duration
    return math.sin(math.pi * amount) ** 1.35 if 0 <= amount <= 1 else 0


def feature_scene(local, absolute, text_key, icon_specs, dramatic=False):
    frame = background(absolute)
    common(frame, absolute)
    progress = smooth(local / .68)
    add_scaled(frame, texts[text_key], (W // 2, 700), lerp(.94, 1, progress), progress, 22 * (1 - progress))
    # Gold separator grows from the center.
    line = round(360 * smooth((local - .25) / .75))
    cv2.line(frame, (W // 2 - line, 930), (W // 2 + line, 930), GOLD, 3, cv2.LINE_AA)
    for index, (asset, center, scale) in enumerate(icon_specs):
        reveal = smooth((local - (.50 + index * .22)) / .58)
        bounce = 1 + .035 * pulse(local, 1.25 + index * .55)
        add_scaled(frame, asset, center, scale * lerp(.86, 1, reveal) * bounce, reveal, 28 * (1 - reveal))
    if dramatic and local > 1.0:
        glow = .5 + .5 * math.sin((local - 1) * math.pi * .7)
        overlay = frame.copy()
        cv2.circle(overlay, (W // 2, 1200), round(260 + 28 * glow), PALE_GOLD, 8, cv2.LINE_AA)
        frame = cv2.addWeighted(overlay, .045, frame, .955, 0)
    return frame


def publish_scene(local):
    frame = feature_scene(local, 18 + local, 'publish', [
        (publish_house, (300, 1210), 1.08),
        (publish_camera, (780, 1210), 1.06),
    ])
    return frame


def photo_scene(local):
    return feature_scene(local, 23 + local, 'photo', [
        (photo_camera, (300, 1200), 1.0),
        (photo_gallery, (785, 1200), .92),
    ], dramatic=True)


def appointment_scene(local):
    return feature_scene(local, 28 + local, 'appointment', [
        (calendar, (300, 1200), .82),
        (bell, (785, 1200), .82),
    ])


def representative_scene(local):
    frame = feature_scene(local, 33 + local, 'representative', [
        (representative, (W // 2, 1210), 1.18),
    ], dramatic=True)
    return frame


def negotiation_scene(local):
    return feature_scene(local, 38 + local, 'negotiation', [
        (handshake, (300, 1210), .98),
        (price_deal, (780, 1210), .95),
    ])


def documents_scene(local):
    return feature_scene(local, 43 + local, 'documents', [
        (contract, (300, 1210), .90),
        (document, (785, 1210), .90),
    ], dramatic=True)


def contracts_scene(local):
    return feature_scene(local, 48 + local, 'contracts', [
        (scales, (300, 1210), .94),
        (lawyers, (780, 1210), .94),
    ])


def commission_scene(local):
    return feature_scene(local, 52 + local, 'commission', [
        (commission, (W // 2, 1210), 1.05),
    ], dramatic=True)


def transfer_scene(local):
    return feature_scene(local, 55.5 + local, 'transfer', [
        (transfer_key, (325, 1210), 1.02),
        (transfer_stamp, (750, 1210), 1.00),
    ])


def cta_scene(local):
    frame = background(58 + local)
    common(frame, local, final=True)
    progress = smooth(local / .48)
    add_scaled(frame, texts['cta'], (W // 2, 720), lerp(.94, 1, progress), progress)
    add_scaled(frame, phone, (W // 2, 1250), lerp(.80, .94, progress), progress, 30 * (1 - progress))
    add_scaled(frame, contact, (W // 2, 1680), 1.28, progress)
    overlay = frame.copy()
    cv2.rectangle(overlay, (140, 1570), (940, 1780), PALE_GOLD, 6, cv2.LINE_AA)
    return cv2.addWeighted(overlay, .06 + .03 * progress, frame, .94 - .03 * progress, 0)


def gold_transition(first, second, amount, direction=1):
    amount = smooth(amount)
    x = np.arange(W, dtype=np.float32)
    center = lerp(-150, W + 150, amount) if direction > 0 else lerp(W + 150, -150, amount)
    mask = np.clip(((center - x) / 120 + .5) if direction > 0 else ((x - center) / 120 + .5), 0, 1)
    mask = smooth_array(mask)[None, :, None]
    result = first * (1 - mask) + second * mask
    band = np.exp(-((x - center) / 52) ** 2)[None, :, None]
    gold = np.empty_like(result)
    gold[:] = PALE_GOLD
    return np.clip(result * (1 - band * .20) + gold * (band * .20), 0, 255).astype(np.uint8)


SCENES = [
    (18.0, 23.0, publish_scene),
    (23.0, 28.0, photo_scene),
    (28.0, 33.0, appointment_scene),
    (33.0, 38.0, representative_scene),
    (38.0, 43.0, negotiation_scene),
    (43.0, 48.0, documents_scene),
    (48.0, 52.0, contracts_scene),
    (52.0, 55.5, commission_scene),
    (55.5, 58.0, transfer_scene),
    (58.0, 60.0, cta_scene),
]

opening = cv2.VideoCapture(str(ROOT / 'why_choose_preview_18s.mp4'))
if not opening.isOpened():
    raise SystemExit('Missing approved opening: why_choose_preview_18s.mp4')


def generated_frame(time_s):
    for index, (start, end, renderer) in enumerate(SCENES):
        if time_s < end or index == len(SCENES) - 1:
            local = max(0, time_s - start)
            current = renderer(local)
            if index < len(SCENES) - 1 and time_s >= end - .38:
                following = SCENES[index + 1][2](0)
                return gold_transition(current, following, (time_s - (end - .38)) / .38, 1 if index % 2 == 0 else -1)
            return current
    raise AssertionError('unreachable')


def visual_frame(index):
    time_s = index / FPS
    if time_s < 18:
        ok, frame = opening.read()
        if not ok:
            raise RuntimeError(f'Opening ended at frame {index}')
        return frame
    return generated_frame(time_s)


ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
render_command = [
    ffmpeg, '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
    '-c:v', 'libx264', '-preset', 'fast', '-tune', 'stillimage', '-crf', '16', '-profile:v', 'high',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-t', str(DURATION), str(TEMP),
]
process = subprocess.Popen(render_command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
try:
    for frame_index in range(round(DURATION * FPS)):
        process.stdin.write(visual_frame(frame_index).tobytes())
finally:
    process.stdin.close()
    opening.release()
stderr = process.stderr.read().decode('utf-8', 'replace')
if process.wait():
    print(stderr, file=sys.stderr)
    raise SystemExit(1)

licensed_music = ROOT / 'music' / 'cinematic-dubstep-304342.mp3'
if licensed_music.exists():
    audio_input = licensed_music
    output_name = OUT
    audio_edit = (
        '[1:a]atrim=start=0:end=53,asetpts=PTS-STARTPTS[first];'
        '[1:a]atrim=start=149:end=158.59,asetpts=PTS-STARTPTS[outro];'
        '[first][outro]acrossfade=d=2.5:c1=tri:c2=tri,'
        'atrim=start=0:end=60,afade=t=in:st=0:d=0.6,'
        'afade=t=out:st=59.25:d=0.75,'
        'loudnorm=I=-14:TP=-1.5:LRA=8,volume=-1.1dB[audio]'
    )
    mux_command = [
        ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
        '-i', str(TEMP), '-i', str(audio_input),
        '-filter_complex', audio_edit,
        '-map', '0:v:0', '-map', '[audio]',
        '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
        '-t', str(DURATION), '-movflags', '+faststart', str(output_name),
    ]
else:
    audio_input = ROOT / 'reels_promo_60s.mp4'
    output_name = ROOT / 'why_choose_reel_60s_temp_music.mp4'
    mux_command = [
        ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
        '-i', str(TEMP), '-i', str(audio_input),
        '-map', '0:v:0', '-map', '1:a:0',
        '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
        '-af', 'afade=t=in:st=0:d=1.2,afade=t=out:st=58.5:d=1.5',
        '-t', str(DURATION), '-movflags', '+faststart', str(output_name),
    ]

subprocess.run(mux_command, check=True)
print(output_name)
if not licensed_music.exists():
    print('NOTICE: rendered with temporary office music; Pixabay source track is missing.')
