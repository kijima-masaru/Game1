#!/usr/bin/env python
"""画像の明度・色の計測。参考画像とレンダーを同じ物差しで比べるためのもの。

    python tools/measure.py refs/reference_evening.png docs/lookdev/shots/best.png
    python tools/measure.py --hist out.png refs/reference_evening.png docs/lookdev/shots/best.png

出力（画像ごと）:
  - L の p5 / p50 / p95（sRGB 輝度、Rec.709 係数）
  - shadow_fraction: L < 20 / 40 / 60 の画素の割合（日陰の面積率）
  - 明部（上位 25%）と暗部（下位 25%）の平均色相・彩度（暖色光 × 寒色影の確認）
  - --hist で 32 bin の輝度ヒストグラムを重ねた PNG

点測定（lookdev の PROBE 行を使う）は tools/lookdev_shots.py --calib 側で行い、
ここの srgb_to_linear / luminance を共用する。
必要: Pillow, numpy
"""
from __future__ import annotations

import argparse
import colorsys
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

THRESHOLDS = (20, 40, 60)


def load_rgb(path: str | Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64)


def luminance(rgb: np.ndarray) -> np.ndarray:
    """sRGB 値のままの輝度（0-255）。参考画像の実測値と同じ定義。"""
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def srgb_to_linear(v: np.ndarray | float) -> np.ndarray | float:
    """0-1 の sRGB をリニアへ。"""
    v = np.asarray(v, dtype=np.float64)
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def linear_luminance(rgb01: np.ndarray) -> np.ndarray:
    lin = srgb_to_linear(rgb01)
    return 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]


def hue_sat(rgb: np.ndarray) -> tuple[float, float]:
    """平均色相（度、円周平均）と平均彩度（HSV の S）。rgb は (N,3) 0-255。"""
    hs = np.array([colorsys.rgb_to_hsv(*(px / 255.0))[:2] for px in rgb])
    h = hs[:, 0] * 2 * np.pi
    w = hs[:, 1]  # 彩度で重み付け（無彩色の色相は意味が無い）
    if w.sum() < 1e-9:
        return float("nan"), 0.0
    ang = np.degrees(np.arctan2((np.sin(h) * w).sum(), (np.cos(h) * w).sum())) % 360
    return float(ang), float(hs[:, 1].mean())


def analyze(path: str | Path) -> dict:
    rgb = load_rgb(path)
    L = luminance(rgb)
    flat = rgb.reshape(-1, 3)
    Lf = L.reshape(-1)
    p5, p25, p50, p75, p95 = np.percentile(Lf, [5, 25, 50, 75, 95])
    rng = np.random.default_rng(0)
    bright = flat[Lf >= p75]
    dark = flat[Lf <= p25]
    bright = bright[rng.choice(len(bright), min(len(bright), 20000), replace=False)]
    dark = dark[rng.choice(len(dark), min(len(dark), 20000), replace=False)]
    bh, bs = hue_sat(bright)
    dh, ds = hue_sat(dark)
    hist, _ = np.histogram(Lf, bins=32, range=(0, 256))
    return {
        "file": str(path),
        "size": [int(rgb.shape[1]), int(rgb.shape[0])],
        "L_p5": round(float(p5), 1), "L_p50": round(float(p50), 1), "L_p95": round(float(p95), 1),
        "shadow_fraction": {f"L<{t}": round(float((Lf < t).mean()), 3) for t in THRESHOLDS},
        "bright_q": {"hue_deg": round(bh, 1), "sat": round(bs, 3), "mean_rgb": [int(x) for x in bright.mean(0)]},
        "dark_q": {"hue_deg": round(dh, 1), "sat": round(ds, 3), "mean_rgb": [int(x) for x in dark.mean(0)]},
        "hist32": [int(x) for x in hist],
    }


def _font(size: int):
    for cand in ["C:/Windows/Fonts/meiryo.ttc", "C:/Windows/Fonts/msgothic.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if Path(cand).exists():
            try:
                return ImageFont.truetype(cand, size)
            except OSError:
                pass
    return ImageFont.load_default()


def plot_hist(results: list[dict], out: Path) -> None:
    """32 bin の輝度ヒストグラム（割合）を重ねて描く。matplotlib 無しで PIL のみ。"""
    W, H, pad = 1024, 480, 60
    colors = [(235, 120, 90), (110, 190, 250), (170, 230, 120), (240, 210, 90), (200, 150, 250)]
    img = Image.new("RGB", (W, H + 120), (24, 24, 28))
    d = ImageDraw.Draw(img)
    f = _font(16)
    fracs = [np.asarray(r["hist32"], dtype=float) / max(1, sum(r["hist32"])) for r in results]
    ymax = max(fr.max() for fr in fracs) * 1.05
    bw = (W - 2 * pad) / 32
    for i, fr in enumerate(fracs):
        col = colors[i % len(colors)]
        pts = []
        for b, v in enumerate(fr):
            x0 = pad + b * bw
            y = pad + (H - 2 * pad) * (1 - v / ymax)
            pts.append((x0 + bw / 2, y))
            if i == 0:
                d.rectangle([x0 + 1, y, x0 + bw - 1, pad + H - 2 * pad], fill=(col[0] // 3, col[1] // 3, col[2] // 3))
        d.line(pts, fill=col, width=3)
        d.text((pad, H + 10 + i * 22), f"{Path(results[i]['file']).name}   p5/p50/p95 = {results[i]['L_p5']}/{results[i]['L_p50']}/{results[i]['L_p95']}   "
               f"L<20 {results[i]['shadow_fraction']['L<20']:.2f}  L<40 {results[i]['shadow_fraction']['L<40']:.2f}  L<60 {results[i]['shadow_fraction']['L<60']:.2f}",
               fill=col, font=f)
    for t in THRESHOLDS:
        x = pad + t / 256 * (W - 2 * pad)
        d.line([(x, pad), (x, pad + H - 2 * pad)], fill=(90, 90, 100), width=1)
        d.text((x + 3, pad), f"L={t}", fill=(150, 150, 160), font=f)
    d.line([(pad, pad + H - 2 * pad), (W - pad, pad + H - 2 * pad)], fill=(160, 160, 170), width=1)
    for L in (0, 64, 128, 192, 255):
        x = pad + L / 256 * (W - 2 * pad)
        d.text((x - 8, pad + H - 2 * pad + 6), str(L), fill=(160, 160, 170), font=f)
    d.text((pad, 20), "luminance histogram (32 bins, fraction of pixels)", fill=(230, 230, 230), font=_font(20))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--hist", help="ヒストグラム PNG の出力先")
    ap.add_argument("--json", action="store_true", help="JSON で出力")
    a = ap.parse_args()
    results = [analyze(p) for p in a.images]
    if a.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
    else:
        for r in results:
            sf = r["shadow_fraction"]
            print(f"{Path(r['file']).name}")
            print(f"  L p5/p50/p95 = {r['L_p5']} / {r['L_p50']} / {r['L_p95']}")
            print(f"  shadow_fraction  L<20 {sf['L<20']:.3f}   L<40 {sf['L<40']:.3f}   L<60 {sf['L<60']:.3f}")
            print(f"  bright q (top 25%)  hue {r['bright_q']['hue_deg']:.0f}deg  sat {r['bright_q']['sat']:.3f}  rgb {r['bright_q']['mean_rgb']}")
            print(f"  dark   q (low 25%)  hue {r['dark_q']['hue_deg']:.0f}deg  sat {r['dark_q']['sat']:.3f}  rgb {r['dark_q']['mean_rgb']}")
    if a.hist:
        plot_hist(results, Path(a.hist))
        print("hist:", a.hist)


if __name__ == "__main__":
    main()
