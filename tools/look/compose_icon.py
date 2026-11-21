#!/usr/bin/env python3
"""Composes the Android icon layers from the rendered island (tools/look/icon.gd)."""
import sys
from PIL import Image, ImageDraw, ImageFilter
raw = sys.argv[1] if len(sys.argv) > 1 else "/tmp/icon_fg_raw.png"
fg = Image.open(raw).convert("RGBA")
W = 432
bg = Image.new("RGBA", (W, W))
d = ImageDraw.Draw(bg)
top = (255, 196, 160); bot = (130, 196, 255)
for y in range(W):
    t = y / (W - 1)
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,))
sun = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(sun).ellipse((W * 0.18, W * 0.08, W * 0.82, W * 0.72), fill=(255, 236, 190, 150))
bg = Image.alpha_composite(bg, sun.filter(ImageFilter.GaussianBlur(30)))
bg.convert("RGB").save("assets/icon/adaptive_bg.png")
fgc = fg.crop(fg.getbbox())
r = int(W * 0.64) / max(fgc.size)
fgc = fgc.resize((int(fgc.size[0] * r), int(fgc.size[1] * r)), Image.LANCZOS)
canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))
canvas.paste(fgc, ((W - fgc.size[0]) // 2, (W - fgc.size[1]) // 2 + 6), fgc)
canvas.save("assets/icon/adaptive_fg.png")
full = Image.alpha_composite(bg, canvas)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, W - 1), radius=96, fill=255)
icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
icon.paste(full, (0, 0), mask)
icon.resize((192, 192), Image.LANCZOS).save("assets/icon/icon_192.png")
icon.resize((256, 256), Image.LANCZOS).save("icon.png")
icon.save("/tmp/icon_preview.png")
