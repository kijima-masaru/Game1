# -*- coding: utf-8 -*-
"""フェーズ 14 T-3 のプレースホルダのビルボード（木・岩・塔など）を assets/placeholder/ に生成する。
28 texel/m。輪郭 1 px の単純な図形で、素材の工程で PixelLab の素材に差し替える前提。実行: python tools/gen_placeholders.py
"""
import os, random
from PIL import Image, ImageDraw
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.makedirs("assets/placeholder", exist_ok=True)
TPM = 28
OUT = (20, 18, 22, 255)


def outline(img):
    px = img.load(); w, h = img.size
    src = img.copy().load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 0: continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, y + dy)
                if 0 <= q[0] < w and 0 <= q[1] < h and src[q][3] > 0:
                    px[x, y] = OUT; break
    return img


def blob(draw, cx, cy, r, cols, rnd, n=14):
    for _ in range(n):
        a = rnd.uniform(0, 6.283); d = rnd.uniform(0, r * 0.55)
        rr = rnd.uniform(r * 0.45, r * 0.75)
        x = cx + d * 1.1 * __import__("math").cos(a); y = cy + d * 0.8 * __import__("math").sin(a)
        draw.ellipse((x - rr, y - rr * 0.85, x + rr, y + rr * 0.85), fill=rnd.choice(cols))


def broadleaf(name, h_m, crown, trunk, cols, seed, fruit=None):
    rnd = random.Random(seed)
    w, h = int(crown * TPM * 1.1), int(h_m * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    tw = max(4, int(0.35 * TPM))
    d.rectangle((w // 2 - tw // 2, int(h * 0.55), w // 2 + tw // 2, h), fill=trunk)
    blob(d, w / 2, h * 0.34, crown * TPM * 0.5, cols, rnd)
    if fruit:
        for _ in range(18):
            x = rnd.uniform(w * 0.2, w * 0.8); y = rnd.uniform(h * 0.12, h * 0.55)
            if img.getpixel((int(x), int(y)))[3] > 0: d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=fruit)
    outline(img).save("assets/placeholder/%s.png" % name)


def conifer(name, h_m, seed):
    rnd = random.Random(seed)
    w, h = int(2.2 * TPM), int(h_m * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rectangle((w // 2 - 3, int(h * 0.8), w // 2 + 3, h), fill=(70, 50, 38, 255))
    cols = [(38, 66, 46, 255), (30, 54, 40, 255), (46, 76, 50, 255)]
    tiers = 5
    for i in range(tiers):
        y0 = int(h * (0.02 + i * 0.17)); y1 = int(h * (0.22 + i * 0.17))
        hw = int(w * (0.18 + i * 0.09))
        d.polygon([(w // 2, y0), (w // 2 - hw + rnd.randint(-2, 2), y1), (w // 2 + hw + rnd.randint(-2, 2), y1)], fill=cols[i % 3])
    outline(img).save("assets/placeholder/%s.png" % name)


def rock(name, seed):
    rnd = random.Random(seed)
    w, h = int(1.4 * TPM), int(1.0 * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.polygon([(4, h - 2), (2, h * 0.5), (w * 0.3, 3), (w * 0.7, 6), (w - 3, h * 0.45), (w - 5, h - 2)], fill=(104, 108, 116, 255))
    d.polygon([(w * 0.3, 3), (w * 0.7, 6), (w * 0.55, h * 0.5), (w * 0.2, h * 0.5)], fill=(124, 128, 136, 255))
    for _ in range(40):
        x, y = rnd.randint(2, w - 3), rnd.randint(4, h - 3)
        if img.getpixel((x, y))[3] > 0: d.point((x, y), fill=(88, 92, 100, 255))
    outline(img).save("assets/placeholder/%s.png" % name)


def tower(name, h_m, head, seed, lamp=False):
    w, h = int(1.2 * TPM), int(h_m * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    c = (92, 96, 104, 255)
    d.line((w * 0.25, h, w * 0.45, 4), fill=c, width=3); d.line((w * 0.75, h, w * 0.55, 4), fill=c, width=3)
    for i in range(1, 8):
        y = int(h * i / 8); d.line((w * 0.25 + (w * 0.2) * i / 8, y, w * 0.75 - (w * 0.2) * i / 8, y), fill=c, width=2)
    if head == "lamp":
        d.rectangle((w * 0.2, 0, w * 0.8, 10), fill=(220, 225, 235, 255))
    elif head == "bell":
        d.rectangle((w * 0.3, 0, w * 0.7, 14), fill=(60, 44, 36, 255)); d.rectangle((w * 0.42, 4, w * 0.58, 12), fill=(140, 110, 60, 255))
    outline(img).save("assets/placeholder/%s.png" % name)


def pillar(name):
    w, h = int(0.5 * TPM), int(1.6 * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rectangle((2, 4, w - 3, h - 1), fill=(120, 118, 112, 255)); d.rectangle((2, 4, 5, h - 1), fill=(96, 94, 90, 255))
    d.polygon([(2, 4), (w // 2, 0), (w - 3, 4)], fill=(120, 118, 112, 255))
    outline(img).save("assets/placeholder/%s.png" % name)


def backnet(name):
    w, h = int(2.3 * TPM), int(5.0 * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    c = (110, 114, 120, 255)
    d.line((2, h, 2, 0), fill=c, width=3); d.line((w - 3, h, w - 3, 0), fill=c, width=3); d.line((2, 1, w - 3, 1), fill=c, width=3)
    for y in range(4, h, 6): d.line((4, y, w - 5, y), fill=(120, 124, 130, 110), width=1)
    for x in range(6, w - 4, 6): d.line((x, 2, x, h - 1), fill=(120, 124, 130, 110), width=1)
    img.save("assets/placeholder/%s.png" % name)


def cow(name):
    w, h = int(1.4 * TPM), int(1.0 * TPM)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rectangle((0, h - 6, w - 1, h - 1), fill=(96, 94, 92, 255))
    d.rounded_rectangle((4, h * 0.35, w - 6, h - 7), radius=6, fill=(70, 68, 72, 255))
    d.ellipse((w - 16, h * 0.15, w - 2, h * 0.55), fill=(70, 68, 72, 255))
    outline(img).save("assets/placeholder/%s.png" % name)


broadleaf("ph_tree_broadleaf", 5.0, 3.2, (74, 54, 40, 255), [(46, 74, 44, 255), (38, 62, 40, 255), (56, 84, 48, 255)], 1)
broadleaf("ph_tree_ume", 3.0, 2.6, (66, 50, 42, 255), [(52, 72, 46, 255), (44, 62, 42, 255), (60, 80, 50, 255)], 2)
broadleaf("ph_tree_kaki", 3.6, 2.8, (72, 52, 40, 255), [(44, 70, 40, 255), (36, 58, 36, 255), (52, 78, 44, 255)], 3, fruit=(200, 120, 50, 255))
conifer("ph_tree_conifer", 6.0, 4)
rock("ph_rock", 5)
tower("ph_light_tower", 10.0, "lamp", 6)
tower("ph_fire_tower", 8.0, "bell", 7)
pillar("ph_stone_pillar")
backnet("ph_backnet")
cow("ph_cow_statue")
print("placeholders:", sorted(os.listdir("assets/placeholder")))
