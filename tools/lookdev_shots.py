#!/usr/bin/env python
"""lookdev シーンを設定違いで撮影し、比較シートを作る。

    python tools/lookdev_shots.py            # 全セット撮影 → docs/lookdev/shots/ とシート
    python tools/lookdev_shots.py --only times,proj   # 一部だけ
    python tools/lookdev_shots.py --stats             # 撮影せず既存 PNG の明度統計だけ

撮影は `godot`（PATH 上）を実機で起動して行う。ヘッドレスでは撮れない。
参考画像 refs/reference_evening.png があれば、夕方のシートに並べる。
必要: Pillow, numpy
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "lookdev"
SHOTS = OUT / "shots"
REF = ROOT / "refs" / "reference_evening.png"
SCENE = "res://scenes/lookdev.tscn"
UPSCALE = 2  # 640x360 → 1280x720（整数倍・Nearest）

# 撮影セット。name → (ラベル, 引数リスト)
SETS: dict[str, list[tuple[str, list[str]]]] = {
    "times": [
        ("morning", ["time=morning"]),
        ("noon", ["time=noon"]),
        ("evening", ["time=evening"]),
        ("night", ["time=night"]),
    ],
    "proj": [
        ("evening persp", ["time=evening", "proj=persp"]),
        ("evening ortho", ["time=evening", "proj=ortho"]),
        ("evening persp dof=0", ["time=evening", "proj=persp", "dof=0"]),
        ("evening ortho billboard=y", ["time=evening", "proj=ortho", "billboard=y"]),
    ],
    "tonemap": [
        ("linear", ["time=evening", "tonemap=linear"]),
        ("reinhard", ["time=evening", "tonemap=reinhard"]),
        ("filmic", ["time=evening", "tonemap=filmic"]),
        ("aces", ["time=evening", "tonemap=aces"]),
        ("agx", ["time=evening", "tonemap=agx"]),
        ("reinhard white=4", ["time=evening", "tonemap=reinhard", "white=4"]),
        ("filmic white=4", ["time=evening", "tonemap=filmic", "white=4"]),
    ],
    "post": [
        ("glow=1 fog=1", ["time=evening", "glow=1", "fog=1"]),
        ("glow=0 fog=1", ["time=evening", "glow=0", "fog=1"]),
        ("glow=1 fog=0", ["time=evening", "glow=1", "fog=0"]),
        ("ssao=1", ["time=evening", "ssao=1"]),
        ("ssao=1 ssil=1", ["time=evening", "ssao=1", "ssil=1"]),
    ],
    "pixel": [
        ("pixel=1 (1280x720)", ["time=evening", "pixel=1"]),
        ("pixel=2 (640x360 x2)", ["time=evening", "pixel=2"]),
        ("pixel=3 (426x240 x3)", ["time=evening", "pixel=3"]),
        ("pixel=2 ortho", ["time=evening", "pixel=2", "proj=ortho"]),
        ("pixel=2 filter=mipmap", ["time=evening", "pixel=2", "filter=mipmap"]),
        ("pixel=2 ortho filter=mipmap", ["time=evening", "pixel=2", "proj=ortho", "filter=mipmap"]),
    ],
    "shadow": [
        ("soft=0 res=4096", ["time=evening", "soft=0", "shadowres=4096"]),
        ("soft=1 res=4096", ["time=evening", "soft=1", "shadowres=4096"]),
        ("soft=2 res=4096", ["time=evening", "soft=2", "shadowres=4096"]),
        ("soft=0 res=1024", ["time=evening", "soft=0", "shadowres=1024"]),
    ],
    "sun": [
        ("sun_az=165 (front-right)", ["time=evening", "sun_az=165"]),
        ("sun_az=185 (front)", ["time=evening", "sun_az=185"]),
        ("sun_az=205 (front-left, default)", ["time=evening", "sun_az=205"]),
        ("sun_az=205 sun_elev=8", ["time=evening", "sun_az=205", "sun_elev=8"]),
        ("sun_az=205 sun_elev=20", ["time=evening", "sun_az=205", "sun_elev=20"]),
    ],
    "night": [
        ("night omnishadow=1", ["time=night", "omnishadow=1"]),
        ("night omnishadow=0", ["time=night", "omnishadow=0"]),
        ("night glow=0", ["time=night", "glow=0"]),
        ("night ortho", ["time=night", "proj=ortho"]),
        ("night emissive_energy=1 (no visible glow)", ["time=night", "emissive_energy=1"]),
        ("night emissive_energy=8", ["time=night", "emissive_energy=8"]),
    ],
}


def godot_bin() -> str:
    g = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot.cmd")
    if not g:
        sys.exit("godot が見つかりません。PATH か GODOT 環境変数で指定してください。")
    return g


def shoot(name: str, args: list[str]) -> Path:
    SHOTS.mkdir(parents=True, exist_ok=True)
    out = SHOTS / f"{name}.png"
    cmd = [godot_bin(), "--path", str(ROOT), SCENE, "--", "hud=0",
           f"shot={out.as_posix()}", *args]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if not out.exists():
        print(r.stdout[-2000:], r.stderr[-2000:])
        sys.exit(f"撮影に失敗: {name}")
    return out


def luminance(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGB")).astype(float)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def stats(path: Path) -> str:
    L = luminance(Image.open(path))
    p5, p50, p95 = np.percentile(L, [5, 50, 95])
    return f"L p5={p5:5.1f} p50={p50:5.1f} p95={p95:5.1f}"


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for cand in ["C:/Windows/Fonts/meiryo.ttc", "C:/Windows/Fonts/msgothic.ttc",
                 "C:/Windows/Fonts/YuGothM.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if Path(cand).exists():
            try:
                return ImageFont.truetype(cand, size)
            except OSError:
                pass
    return ImageFont.load_default()


def upscale(img: Image.Image, w: int, h: int) -> Image.Image:
    """整数倍なら Nearest、それ以外（参考画像）は LANCZOS で幅を合わせる。"""
    if img.width * UPSCALE == w and img.height * UPSCALE == h:
        return img.resize((w, h), Image.NEAREST)
    scale = w / img.width
    nh = round(img.height * scale)
    im = img.resize((w, nh), Image.LANCZOS)
    canvas = Image.new("RGB", (w, h), (20, 20, 20))
    canvas.paste(im, (0, (h - nh) // 2))
    return canvas


def sheet(title: str, items: list[tuple[str, Path]], out: Path, cols: int = 2) -> None:
    W, H = 640 * UPSCALE, 360 * UPSCALE
    pad, cap = 12, 34
    rows = (len(items) + cols - 1) // cols
    sheet_img = Image.new("RGB", (cols * W + (cols + 1) * pad, 60 + rows * (H + cap + pad)), (24, 24, 28))
    d = ImageDraw.Draw(sheet_img)
    d.text((pad, 14), title, fill=(235, 235, 235), font=font(26))
    f = font(20)
    for i, (label, p) in enumerate(items):
        x = pad + (i % cols) * (W + pad)
        y = 60 + (i // cols) * (H + cap + pad)
        img = Image.open(p).convert("RGB")
        sheet_img.paste(upscale(img, W, H), (x, y))
        d.text((x, y + H + 6), f"{label}    {stats(p)}", fill=(220, 220, 220), font=f)
    out.parent.mkdir(parents=True, exist_ok=True)
    save_sheet(sheet_img, out)


def save_sheet(img: Image.Image, out: Path) -> None:
    """リポジトリに入れるので 256 色に量子化して容量を 1/3 程度にする。"""
    # ドット絵部分は色数が少ないのでほぼ無劣化。Glow のグラデーションだけディザで縞を防ぐ。
    img.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).save(out, optimize=True)
    print("sheet:", out.relative_to(ROOT), f"{out.stat().st_size / 1048576:.1f} MB")


def find_cyan(img: Image.Image) -> tuple[int, int] | None:
    """自販機スプライトの発光パネル（シアン）の重心。スプライト拡大比較の切り出しに使う。"""
    a = np.asarray(img.convert("RGB")).astype(int)
    m = (a[..., 2] > 180) & (a[..., 1] > 180) & (a[..., 0] < 190) & (a[..., 2] - a[..., 0] > 40)
    ys, xs = np.nonzero(m)
    if len(xs) < 4:
        return None
    return int(xs.mean()), int(ys.mean())


def sprite_sheet(items: list[tuple[str, Path]], out: Path, zoom: int = 6) -> None:
    """スプライト周辺を切り出して拡大（Nearest）。texel が画面ピクセルにどう乗るかを見る。"""
    cw, ch = 96, 72
    tiles: list[tuple[str, Image.Image]] = []
    for label, p in items:
        img = Image.open(p).convert("RGB")
        k = img.height / 360.0                   # 描画解像度に応じて切り出し幅を合わせる
        c = find_cyan(img)
        if c is None:
            continue
        w, h = int(cw * k), int(ch * k)
        x0 = max(0, min(img.width - w, c[0] - w // 2))
        y0 = max(0, min(img.height - h, c[1] - h // 3))
        crop = img.crop((x0, y0, x0 + w, y0 + h)).resize((cw * zoom, ch * zoom), Image.NEAREST)
        tiles.append((label, crop))
    if not tiles:
        return
    pad, cap = 12, 30
    W, H = cw * zoom, ch * zoom
    cols = min(3, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    sheet_img = Image.new("RGB", (cols * W + (cols + 1) * pad, 60 + rows * (H + cap + pad)), (24, 24, 28))
    d = ImageDraw.Draw(sheet_img)
    d.text((pad, 14), f"lookdev — sprite close-up (x{zoom} nearest)", fill=(235, 235, 235), font=font(26))
    f = font(20)
    for i, (label, im) in enumerate(tiles):
        x = pad + (i % cols) * (W + pad)
        y = 60 + (i // cols) * (H + cap + pad)
        sheet_img.paste(im, (x, y))
        d.text((x, y + H + 4), label, fill=(220, 220, 220), font=f)
    save_sheet(sheet_img, out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="カンマ区切りのセット名")
    ap.add_argument("--stats", action="store_true", help="撮影せず統計だけ")
    a = ap.parse_args()
    names = [n for n in a.only.split(",") if n] or list(SETS)

    if a.stats:
        for p in sorted(SHOTS.glob("*.png")):
            print(f"{p.name:40s} {stats(p)}")
        if REF.exists():
            print(f"{'REFERENCE':40s} {stats(REF)}")
        return

    for n in names:
        items: list[tuple[str, Path]] = []
        for label, args in SETS[n]:
            fname = f"{n}_{label.replace(' ', '_').replace('=', '').replace('(', '').replace(')', '')}"
            p = shoot(fname, args)
            print(f"  {fname:40s} {stats(p)}")
            items.append((label, p))
        if n in ("times", "tonemap", "proj", "sun") and REF.exists():
            items.insert(0, ("REFERENCE (refs/reference_evening.png)", REF))
        cols = 3 if len(items) in (3, 5, 6, 9) else 2
        sheet(f"lookdev — {n}", items, OUT / f"sheet_{n}.png", cols=cols)

    crops = [
        ("persp pixel=2", SHOTS / "proj_evening_persp.png"),
        ("ortho pixel=2 (1 texel = 1 px)", SHOTS / "proj_evening_ortho.png"),
        ("ortho billboard=y", SHOTS / "proj_evening_ortho_billboardy.png"),
        ("persp pixel=1 (1280x720)", SHOTS / "pixel_pixel1_1280x720.png"),
        ("persp pixel=3 (426x240)", SHOTS / "pixel_pixel3_426x240_x3.png"),
        ("persp filter=mipmap", SHOTS / "pixel_pixel2_filtermipmap.png"),
    ]
    crops = [(l, p) for l, p in crops if p.exists()]
    if crops:
        sprite_sheet(crops, OUT / "sheet_sprite.png")


if __name__ == "__main__":
    main()
