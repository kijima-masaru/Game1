#!/usr/bin/env python
"""ピクセル整合の検証（フェーズ 3 C 系）。実機で lookdev を起動して測る。

    python tools/lookdev_c.py c1          # 投影: FOV スイープ、板の実測ピクセル高さ
    python tools/lookdev_c.py c2          # シマー: 等速パンの連番から隣接フレーム MAD
    python tools/lookdev_c.py c3          # モアレ: 昼の Nearest と Nearest+mipmap を同一カットで
    python tools/lookdev_c.py c2 --fov 18 --frames 60 --pan 2.0

出力は docs/lookdev/c*_*.png と docs/lookdev/c*_*.json。連番は docs/lookdev/shots/seq_*/（Git 管理外）。
"""
from __future__ import annotations

import argparse
import json
import math
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
PITCH = 42.0
DESIGN_H = 360


def godot(args: list[str]) -> str:
    cmd = [ls.godot_bin(), "--path", str(ROOT), ls.SCENE, "--", "hud=0", *args]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout


def parse_json_lines(out: str, tag: str) -> list[dict]:
    return [json.loads(line[len(tag) + 1:]) for line in out.splitlines() if line.startswith(tag + " ")]


# ---------------------------------------------------------------------------
# C-1
# ---------------------------------------------------------------------------
def board_heights(img: Image.Image) -> list[int]:
    """マゼンタの板 3 枚（上・中・下）の実測ピクセル高さ。"""
    a = np.asarray(img.convert("RGB")).astype(int)
    m = (a[..., 0] > 180) & (a[..., 2] > 180) & (a[..., 1] < 90)
    rows = np.nonzero(m.any(axis=1))[0]
    if rows.size == 0:
        return []
    # 連続する行のグループ = 1 枚の板
    groups: list[list[int]] = [[int(rows[0])]]
    for r in rows[1:]:
        if r - groups[-1][-1] > 2:
            groups.append([])
        groups[-1].append(int(r))
    return [g[-1] - g[0] + 1 for g in groups]


def run_c1(fovs: list[float], texel: float) -> None:
    results = []
    items = []
    for fov in fovs + ["ortho"]:
        name = f"c1_fov{fov}" if fov != "ortho" else "c1_ortho"
        out = SHOTS / f"{name}.png"
        SHOTS.mkdir(parents=True, exist_ok=True)
        args = ["c1=1", "time=noon", "fog=0", "glow=0", "lamps=0", f"texel={texel}", f"shot={out.as_posix()}"]
        args += ["proj=ortho"] if fov == "ortho" else [f"fov={fov}"]
        stdout = godot(args)
        cam = parse_json_lines(stdout, "C1CAM")[0]
        boards = parse_json_lines(stdout, "C1BOARD")
        img = Image.open(out)
        hs = board_heights(img)
        if fov == "ortho":
            ratio_ground = 1.0
        else:
            f = float(fov)
            ratio_ground = math.sin(math.radians(PITCH + f / 2)) / math.sin(math.radians(PITCH - f / 2))
        row = {
            "fov": fov, "distance_m": round(cam["distance"], 2), "cam_height_m": round(cam["height"], 2),
            "ground_dist_ratio_top_over_bottom": round(ratio_ground, 3),
            "board_dist_m": [round(b["dist"], 2) for b in boards],
            "board_px_top_mid_bottom": hs,
            "measured_ratio_bottom_over_top": round(hs[-1] / hs[0], 3) if len(hs) >= 2 and hs[0] else None,
        }
        results.append(row)
        print(f"fov={str(fov):5s} dist={row['distance_m']:6.2f}m  ground ratio(top/bottom)={ratio_ground:.3f}  "
              f"board px (top,mid,bottom)={hs}  measured bottom/top={row['measured_ratio_bottom_over_top']}")
        items.append((f"fov={fov} dist={row['distance_m']}m  board px top/mid/bottom = {hs}", out))
    (OUT / "c1_projection.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    ls.sheet("C-1 projection — same 1 m board at screen top / center / bottom (28 texel/m at center)", items, OUT / "c1_projection.png", cols=3)


# ---------------------------------------------------------------------------
# C-2
# ---------------------------------------------------------------------------
CONDS = {
    "a_nearest": [],
    "b_mipmap": ["filter=mipmap"],
    "c_mipmap_snap": ["filter=mipmap", "snap=1"],
    "d_mipmap_snap_fxaa": ["filter=mipmap", "snap=1", "fxaa=1"],
}


def mad_series(dirpath: Path, region: tuple[int, int, int, int] | None = None) -> list[float]:
    files = sorted(dirpath.glob("f*.png"))
    prev = None
    out = []
    for f in files:
        a = luminance(np.asarray(Image.open(f).convert("RGB")).astype(np.float64))
        if region:
            x0, y0, x1, y1 = region
            a = a[y0:y1, x0:x1]
        if prev is not None:
            out.append(float(np.abs(a - prev).mean()))
        prev = a
    return out


def plot_series(series: dict[str, list[float]], title: str, out: Path) -> None:
    W, H, pad = 1100, 420, 60
    colors = {"a_nearest": (235, 110, 90), "b_mipmap": (110, 190, 250), "c_mipmap_snap": (170, 230, 120), "d_mipmap_snap_fxaa": (240, 210, 90)}
    img = Image.new("RGB", (W, H + 40 + 24 * len(series)), (24, 24, 28))
    d = ImageDraw.Draw(img)
    ymax = max(max(v) for v in series.values()) * 1.1 or 1.0
    n = max(len(v) for v in series.values())
    for i, (k, v) in enumerate(series.items()):
        col = colors.get(k, (200, 200, 200))
        pts = [(pad + j * (W - 2 * pad) / max(n - 1, 1), pad + (H - 2 * pad) * (1 - x / ymax)) for j, x in enumerate(v)]
        d.line(pts, fill=col, width=2)
        d.text((pad, H + 10 + i * 24), f"{k:22s} mean MAD = {np.mean(v):6.2f}   median = {np.median(v):6.2f}   max = {np.max(v):6.2f}", fill=col, font=ls.font(16))
    d.line([(pad, pad + H - 2 * pad), (W - pad, pad + H - 2 * pad)], fill=(160, 160, 170))
    d.line([(pad, pad), (pad, pad + H - 2 * pad)], fill=(160, 160, 170))
    d.text((pad - 50, pad - 8), f"{ymax:.1f}", fill=(160, 160, 170), font=ls.font(14))
    d.text((pad - 20, pad + H - 2 * pad + 4), "0", fill=(160, 160, 170), font=ls.font(14))
    d.text((W - pad - 60, pad + H - 2 * pad + 4), f"frame {n}", fill=(160, 160, 170), font=ls.font(14))
    d.text((pad, 16), title, fill=(235, 235, 235), font=ls.font(20))
    img.save(out)
    print("plot:", out.relative_to(ROOT))


def run_c2(fov: float, frames: int, pan: float, texel: float, crop: tuple[int, int, int, int], extra: list[str] | None = None, tag: str = "", no_flat: bool = False) -> None:
    base = ["time=evening", "fog=0", "glow=0", "lamps=0", f"fov={fov}", f"texel={texel}", f"seq_frames={frames}", f"pan={pan}", *(extra or [])]
    summary = {}
    for flat in ((False,) if no_flat else (False, True)):
        series = {}
        crops = []
        for cond, extra in CONDS.items():
            tag_ = tag + ("flat_" if flat else "tex_") + cond
            d = SHOTS / f"seq_{tag_}"
            if d.exists():
                shutil.rmtree(d)
            d.mkdir(parents=True)
            godot([*base, *extra, *(["flat=1"] if flat else []), f"seq={d.as_posix()}"])
            n = len(list(d.glob("f*.png")))
            if n < 2:
                sys.exit(f"連番が撮れていません: {d}")
            s_full = mad_series(d)
            s_crop = mad_series(d, crop)
            series[cond] = s_crop if flat else s_full
            summary[tag_] = {"frames": n, "mad_full_mean": round(float(np.mean(s_full)), 3), "mad_crop_mean": round(float(np.mean(s_crop)), 3),
                            "mad_full_max": round(float(np.max(s_full)), 3)}
            print(f"{tag_:30s} frames={n:3d}  MAD full mean={np.mean(s_full):6.2f} max={np.max(s_full):6.2f}   crop(shadow edge) mean={np.mean(s_crop):6.2f}")
            mid = sorted(d.glob("f*.png"))[n // 2]
            im = Image.open(mid).convert("RGB")
            x0, y0, x1, y1 = crop
            crops.append((f"{cond}  MAD full {np.mean(s_full):.2f} / edge {np.mean(s_crop):.2f}", im.crop((x0, y0, x1, y1)).resize(((x1 - x0) * 6, (y1 - y0) * 6), Image.NEAREST)))
        kind = "flat albedo (shadow/geometry edges only), MAD in edge crop" if flat else "textured, MAD over full frame"
        plot_series(series, f"C-2 shimmer — adjacent-frame MAD, pan {pan} m / {frames} frames, fov {fov}  [{kind}]", OUT / f"c2_{tag}mad_{'flat' if flat else 'tex'}.png")
        # x6 crops sheet
        cw, ch = (crop[2] - crop[0]) * 6, (crop[3] - crop[1]) * 6
        pad, cap = 12, 30
        sheet = Image.new("RGB", (2 * cw + 3 * pad, 60 + 2 * (ch + cap + pad)), (24, 24, 28))
        dd = ImageDraw.Draw(sheet)
        dd.text((pad, 14), f"C-2 representative frame (x6 nearest) — {'flat' if flat else 'textured'}", fill=(235, 235, 235), font=ls.font(24))
        for i, (label, im) in enumerate(crops):
            x = pad + (i % 2) * (cw + pad)
            y = 60 + (i // 2) * (ch + cap + pad)
            sheet.paste(im, (x, y))
            dd.text((x, y + ch + 4), label, fill=(220, 220, 220), font=ls.font(18))
        ls.save_sheet(sheet, OUT / f"c2_{tag}frames_{'flat' if flat else 'tex'}_x6.png")
    (OUT / f"c2_{tag}shimmer.json").write_text(json.dumps({"fov": fov, "frames": frames, "pan_m": pan, "crop": crop, "results": summary}, ensure_ascii=False, indent=1), encoding="utf-8")


# ---------------------------------------------------------------------------
# C-3
# ---------------------------------------------------------------------------
def run_c3(fov: float, texel: float) -> None:
    items = []
    for label, extra in (("noon nearest", []), ("noon nearest+mipmap (world only)", ["filter=mipmap"])):
        out = SHOTS / f"c3_{'mipmap' if extra else 'nearest'}.png"
        godot(["time=noon", "fog=0", "glow=0", "lamps=0", f"fov={fov}", f"texel={texel}", *extra, f"shot={out.as_posix()}"])
        items.append((label, out))
    ls.sheet("C-3 moire — noon, same cut", items, OUT / "c3_moire.png", cols=2)
    # 屋根と路面の拡大
    crops = []
    for label, p in items:
        im = Image.open(p).convert("RGB")
        for name, box in (("roof", (0, 220, 160, 340)), ("road", (60, 20, 220, 140))):
            crops.append((f"{label} — {name}", im.crop(box).resize(((box[2] - box[0]) * 4, (box[3] - box[1]) * 4), Image.NEAREST)))
    cw, ch = 640, 480
    pad, cap = 12, 30
    sheet = Image.new("RGB", (2 * cw + 3 * pad, 60 + 2 * (ch + cap + pad)), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 14), "C-3 moire close-up (x4 nearest)", fill=(235, 235, 235), font=ls.font(24))
    order = [0, 2, 1, 3]  # nearest roof, mipmap roof, nearest road, mipmap road
    for i, idx in enumerate(order):
        label, im = crops[idx]
        x = pad + (i % 2) * (cw + pad)
        y = 60 + (i // 2) * (ch + cap + pad)
        sheet.paste(im, (x, y))
        d.text((x, y + ch + 4), label, fill=(220, 220, 220), font=ls.font(18))
    ls.save_sheet(sheet, OUT / "c3_moire_closeup.png")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("which", choices=["c1", "c2", "c3"])
    ap.add_argument("--fovs", default="12,18,22,30,45")
    ap.add_argument("--fov", type=float, default=22.0)
    ap.add_argument("--texel", type=float, default=28.0)
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--pan", type=float, default=2.0)
    ap.add_argument("--crop", default="50,90,170,210", help="C-2 の影エッジ切り出し x0,y0,x1,y1（640x360 座標）")
    ap.add_argument("--extra", default="", help="C-2 追加引数（例: proj=ortho）")
    ap.add_argument("--tag", default="", help="C-2 出力名の接頭辞")
    ap.add_argument("--no-flat", action="store_true")
    a = ap.parse_args()
    crop = tuple(int(v) for v in a.crop.split(","))
    if a.which == "c1":
        run_c1([float(x) for x in a.fovs.split(",")], a.texel)
    elif a.which == "c2":
        run_c2(a.fov, a.frames, a.pan, a.texel, crop, a.extra.split(), a.tag, a.no_flat)  # type: ignore[arg-type]
    else:
        run_c3(a.fov, a.texel)


if __name__ == "__main__":
    main()
