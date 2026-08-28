#!/usr/bin/env python3
"""Replace the temporary proof soundtrack with the selected CC BY 4.0 track.

Expected input:
  marketing/music/tranquil-fields-eastern.mp3

The H.264 video stream is copied without quality loss; only audio is encoded.
"""

from pathlib import Path
import subprocess
import sys

try:
    import imageio_ffmpeg
except ImportError:
    raise SystemExit(
        'Install imageio-ffmpeg outside the repo:\n'
        'python3 -m pip install --target /tmp/reeldeps imageio-ffmpeg\n'
        'PYTHONPATH=/tmp/reeldeps python3 marketing/apply_why_choose_music.py'
    )

ROOT = Path(__file__).resolve().parent
VIDEO = ROOT / 'why_choose_reel_60s_temp_music.mp4'
MUSIC = ROOT / 'music' / 'tranquil-fields-eastern.mp3'
OUTPUT = ROOT / 'why_choose_reel_60s.mp4'

for path in (VIDEO, MUSIC):
    if not path.exists():
        raise SystemExit(f'Missing required file: {path}')

ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
subprocess.run([
    ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
    '-i', str(VIDEO), '-stream_loop', '-1', '-i', str(MUSIC),
    '-map', '0:v:0', '-map', '1:a:0',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
    '-af', 'afade=t=in:st=0:d=1.2,afade=t=out:st=58.5:d=1.5',
    '-t', '60', '-movflags', '+faststart', str(OUTPUT),
], check=True)
print(OUTPUT)
