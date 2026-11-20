"""アプリアイコン（1024x1024）を生成する。使い方: python scripts/make_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "FocusGuard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
top, bottom = (79, 70, 229), (49, 46, 129)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)))
# 盾
shield = [(512, 180), (790, 290), (760, 600), (512, 850), (264, 600), (234, 290)]
d.polygon(shield, fill=(255, 255, 255))
# 砂時計
c = (79, 70, 229)
d.polygon([(420, 352), (604, 352), (512, 500)], fill=c)
d.polygon([(512, 500), (604, 648), (420, 648)], fill=c)
d.rectangle([404, 330, 620, 352], fill=c)
d.rectangle([404, 648, 620, 670], fill=c)
img.save(OUT)
print("saved", OUT)
