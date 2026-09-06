#!/usr/bin/env python
"""E-3b: テストスプライト（28x56 texel）を奥から手前へ歩かせ、3 条件で GIF と MAD を出す。

    python tools/lookdev_walk.py            # A/B/C を撮影 → docs/lookdev/video/E3_*.gif, docs/lookdev/e3b_*.png/json
    python tools/lookdev_walk.py --frames 90 --fov 18

条件:
  A: スプライト Nearest（現状）
  B: スプライトに線形フィルタ + ミップマップ
  C: 見かけの texel/px 比を最も近い整数に丸める（この FOV 範囲では常に 56 px）
  D: C に加えて足元の画面位置を整数ピクセルにスナップ（ピクセルパーフェクト）
MAD はスプライト周辺（WALK 行の画面座標で追跡した 48x72 px の窓）で取る。GIF は等倍と、
スプライト追跡窓の x3。GIF は Git 管理外（docs/lookdev/video/）。
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lookdev_shots as ls  # noqa: E402
from measure import luminance  # noqa: E402

ROOT, SHOTS, OUT = ls.ROOT, ls.SHOTS, ls.OUT
VIDEO = OUT / "video"
WIN_W, WIN_H = 48, 72   # 追跡窓（640x360 座標）


def run(mode: str, frames: int, fov: float, extra: list[str]) -> tuple[Path, list[dict]]:
    d = SHOTS / f"seq_walk_{mode}"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    cmd = [ls.godot_bin(), "--path", str(ROOT), ls.SCENE, "--", "hud=0", "time=evening", "fog=0", "glow=0", "lamps=0",
           f"fov={fov}", f"walk={mode}", f"seq_frames={frames}", f"seq={d.as_posix()}", *extra]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    walk = [json.loads(line[5:]) for line in r.stdout.splitlines() if line.startswith("WALK ")]
    if len(list(d.glob("f*.png"))) < 2:
        print(r.stdout[-1500:])
        sys.exit(f"連番が撮れていません: {mode}")
    return d, walk


def window(w: dict, size: tuple[int, int]) -> tuple[int, int, int, int]:
    cx, cy = int(round(w["px"])), int(round(w["py"]))
    x0 = max(0, min(size[0] - WIN_W, cx - WIN_W // 2))
    y0 = max(0, min(size[1] - WIN_H, cy - WIN_H + 8))   # 足元が py。上へ 64px
    return x0, y0, x0 + WIN_W, y0 + WIN_H


def sprite_mask(rgb: np.ndarray) -> np.ndarray:
    """テストスプライトの画素（高彩度の赤/青/黄、または白い輪郭）。背景は低彩度なので彩度で分けられる。"""
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1.0)
    white = (mn > 200)
    return ((sat > 0.5) & (mx > 90)) | white


def analyze(d: Path, walk: list[dict]) -> dict:
    """MAD を 3 通り: 全画面 / スプライト追跡窓（背景の流れを含む）/ スプライト画素マスク（前後フレームの和集合）。
    マスク MAD が「スプライト自身の標本化の揺れ」に最も近い。"""
    files = sorted(d.glob("f*.png"))
    frames = [Image.open(f).convert("RGB") for f in files]
    size = frames[0].size
    mads_full, mads_win, mads_mask = [], [], []
    prev = prev_win = prev_mask = None
    prev_L = None
    for im, w in zip(frames, walk):
        rgb = np.asarray(im).astype(np.float64)
        L = luminance(rgb)
        x0, y0, x1, y1 = window(w, size)
        win = L[y0:y1, x0:x1]
        m = sprite_mask(rgb)[y0:y1, x0:x1]
        if prev is not None:
            mads_full.append(float(np.abs(L - prev).mean()))
            mads_win.append(float(np.abs(win - prev_win).mean()))
            u = m | prev_mask
            mads_mask.append(float(np.abs(win - prev_win)[u].mean()) if u.any() else 0.0)
        prev, prev_win, prev_mask = L, win, m
    hs = [w["h_px"] for w in walk]
    return {"frames": len(frames), "mad_full_mean": round(float(np.mean(mads_full)), 3), "mad_window_mean": round(float(np.mean(mads_win)), 3),
            "mad_window_max": round(float(np.max(mads_win)), 3), "mad_sprite_mean": round(float(np.mean(mads_mask)), 3), "mad_sprite_max": round(float(np.max(mads_mask)), 3),
            "h_px_min": round(min(hs), 2), "h_px_max": round(max(hs), 2),
            "scale_values": sorted({round(w["scale"], 3) for w in walk}), "series_window": [round(v, 3) for v in mads_mask]}


def gifs(mode: str, d: Path, walk: list[dict]) -> None:
    VIDEO.mkdir(parents=True, exist_ok=True)
    files = sorted(d.glob("f*.png"))
    frames = [Image.open(f).convert("RGB") for f in files]
    size = frames[0].size
    base = frames[0].quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q = [base] + [im.quantize(palette=base, dither=Image.Dither.NONE) for im in frames[1:]]
    q[0].save(VIDEO / f"E3_{mode}_1x.gif", save_all=True, append_images=q[1:], duration=33, loop=0)
    crops = []
    for im, w in zip(frames, walk):
        x0, y0, x1, y1 = window(w, size)
        crops.append(im.crop((x0, y0, x1, y1)).resize((WIN_W * 6, WIN_H * 6), Image.NEAREST))
    cb = crops[0].quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    cq = [cb] + [im.quantize(palette=cb, dither=Image.Dither.NONE) for im in crops[1:]]
    cq[0].save(VIDEO / f"E3_{mode}_sprite_x6.gif", save_all=True, append_images=cq[1:], duration=33, loop=0)
    big = [im.resize((size[0] * 3, size[1] * 3), Image.NEAREST) for im in frames]
    bb = big[0].quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    bq = [bb] + [im.quantize(palette=bb, dither=Image.Dither.NONE) for im in big[1:]]
    bq[0].save(VIDEO / f"E3_{mode}_3x.gif", save_all=True, append_images=bq[1:], duration=33, loop=0)


def sheet(results: dict[str, dict], seqs: dict[str, tuple[Path, list[dict]]]) -> None:
    # 代表 3 フレーム（奥・中・手前）のスプライト窓を x6 で並べる
    cols = 3
    W, H = WIN_W * 6, WIN_H * 6
    pad, cap = 12, 28
    img = Image.new("RGB", (cols * W + (cols + 1) * pad, 60 + len(results) * (H + cap + pad)), (24, 24, 28))
    d = ImageDraw.Draw(img)
    d.text((pad, 14), "E-3b test sprite 28x56 texel, far / mid / near (x6 nearest)", fill=(235, 235, 235), font=ls.font(22))
    for r, (mode, res) in enumerate(results.items()):
        dpath, walk = seqs[mode]
        files = sorted(dpath.glob("f*.png"))
        idxs = [1, len(files) // 2, len(files) - 2]
        for c, i in enumerate(idxs):
            im = Image.open(files[i]).convert("RGB")
            x0, y0, x1, y1 = window(walk[i], im.size)
            crop = im.crop((x0, y0, x1, y1)).resize((W, H), Image.NEAREST)
            x = pad + c * (W + pad)
            y = 60 + r * (H + cap + pad)
            img.paste(crop, (x, y))
            d.text((x, y + H + 2), f"{mode}: frame {i}  h={walk[i]['h_px']:.1f}px scale={walk[i]['scale']:.2f}", fill=(220, 220, 220), font=ls.font(15))
        d.text((pad + 3 * (W + pad) - 4, 60 + r * (H + cap + pad)), f"MAD sprite {res['mad_sprite_mean']:.2f}", fill=(220, 220, 220), font=ls.font(15))
    ls.save_sheet(img, OUT / "e3b_walk_sprite_x6.png")


def plot(results: dict[str, dict]) -> None:
    W, H, pad = 1100, 400, 60
    colors = {"A": (235, 110, 90), "B": (110, 190, 250), "C": (170, 230, 120), "D": (240, 210, 90)}
    img = Image.new("RGB", (W, H + 40 + 24 * len(results)), (24, 24, 28))
    d = ImageDraw.Draw(img)
    ymax = max(max(r["series_window"]) for r in results.values()) * 1.1
    for i, (mode, r) in enumerate(results.items()):
        v = r["series_window"]
        pts = [(pad + j * (W - 2 * pad) / max(len(v) - 1, 1), pad + (H - 2 * pad) * (1 - x / ymax)) for j, x in enumerate(v)]
        d.line(pts, fill=colors[mode], width=2)
        sv = r['scale_values']
        d.text((pad, H + 10 + i * 24), f"{mode}: sprite-mask MAD mean {r['mad_sprite_mean']:.2f} max {r['mad_sprite_max']:.2f}   h_px {r['h_px_min']}..{r['h_px_max']}   scale {sv[0]}..{sv[-1]}", fill=colors[mode], font=ls.font(16))
    d.line([(pad, pad + H - 2 * pad), (W - pad, pad + H - 2 * pad)], fill=(160, 160, 170))
    d.text((pad, 16), "E-3b sprite walk far->near: adjacent-frame MAD on sprite pixels (mask)", fill=(235, 235, 235), font=ls.font(20))
    img.save(OUT / "e3b_walk_mad.png")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", type=int, default=90)
    ap.add_argument("--fov", type=float, default=18.0)
    ap.add_argument("--extra", default="")
    ap.add_argument("--modes", default="A,B,C,D")
    a = ap.parse_args()
    results, seqs = {}, {}
    for mode in a.modes.split(","):
        d, walk = run(mode, a.frames, a.fov, a.extra.split())
        res = analyze(d, walk)
        results[mode] = res
        seqs[mode] = (d, walk)
        sv = res['scale_values']
        print(f"{mode}: frames={res['frames']} MAD full={res['mad_full_mean']:.2f} window={res['mad_window_mean']:.2f} sprite-mask={res['mad_sprite_mean']:.2f} (max {res['mad_sprite_max']:.2f})  h_px {res['h_px_min']}..{res['h_px_max']}  scale {sv[0]}..{sv[-1]} ({len(sv)} values)")
        gifs(mode, d, walk)
    (OUT / "e3b_walk.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    plot(results)
    sheet(results, seqs)
    for g in sorted(VIDEO.glob("E3_*.gif")):
        print(f"{g.name:28s} {g.stat().st_size / 1048576:5.1f} MB")


if __name__ == "__main__":
    main()
