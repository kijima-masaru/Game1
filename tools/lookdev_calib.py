#!/usr/bin/env python
"""lookdev の較正スイープ。実機で撮影し、路面上の点で日向/日陰を測る。

    python tools/lookdev_calib.py ambient                # ambient_mul スイープ（影の明度比）
    python tools/lookdev_calib.py ambient --mults 1,0.6,0.45,0.34,0.26,0.2,0.15,0.1
    python tools/lookdev_calib.py wall --ambient-mul 0.3  # 壁アルベドのスイープ
    python tools/lookdev_calib.py tonemap --white 4      # 5 モードの SHA-256 と統計

較正中の固定条件: fog=0 glow=0 lamps=0（街灯・発光板 OFF）。sun_energy は触らない。
点測定は lookdev.gd の probe_grid が出力する PROBE 行（画面投影した路面格子点の
3x3 平均画素・幾何による日向/日陰判定・縁からの余裕）から、
日向の芯・日陰の芯を 1 点ずつ選んで使う。選定条件:
  - 路面上（|z| <= 2.5）、建物から 1.5 m 以上
  - 日向/日陰の縁から 1.5 m 以上（半影と接地 AO を避ける）
  - 条件を満たす中で、縁からの余裕が最大 → 同点なら画面中央に近いもの
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lookdev_shots as ls  # noqa: E402
from measure import analyze, srgb_to_linear  # noqa: E402

ROOT = ls.ROOT
SHOTS = ls.SHOTS
OUT = ls.OUT
FIXED = ["hud=0", "time=evening", "fog=0", "glow=0", "lamps=0"]


def run(name: str, args: list[str]) -> tuple[Path, list[dict]]:
    SHOTS.mkdir(parents=True, exist_ok=True)
    out = SHOTS / f"{name}.png"
    cmd = [ls.godot_bin(), "--path", str(ROOT), ls.SCENE, "--", *FIXED, f"shot={out.as_posix()}", *args]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    probes = [json.loads(line[6:]) for line in r.stdout.splitlines() if line.startswith("PROBE ")]
    if not out.exists():
        print(r.stdout[-1500:], r.stderr[-1500:])
        sys.exit(f"撮影に失敗: {name}")
    return out, probes


def pick_points(probes: list[dict], size: tuple[int, int]) -> tuple[dict, dict]:
    cx, cy = size[0] / 2, size[1] / 2

    def best(shadow: bool) -> dict:
        cands = [p for p in probes if p["shadow"] == shadow and p["wall"] >= 1.5 and p["margin"] >= 1.5]
        if not cands:
            cands = [p for p in probes if p["shadow"] == shadow and p["wall"] >= 1.5]
        if not cands:
            sys.exit(f"計測点が見つかりません shadow={shadow}")
        cands.sort(key=lambda p: (-p["margin"], (p["px"] - cx) ** 2 + (p["py"] - cy) ** 2))
        return cands[0]

    return best(False), best(True)


def sample(img: Image.Image, px: int, py: int) -> np.ndarray:
    a = np.asarray(img.convert("RGB")).astype(np.float64)
    return a[py - 1:py + 2, px - 1:px + 2].reshape(-1, 3).mean(0)


def lum_srgb(rgb255: np.ndarray) -> float:
    return float(0.2126 * rgb255[0] + 0.7152 * rgb255[1] + 0.0722 * rgb255[2])


def lum_lin(rgb255: np.ndarray) -> float:
    lin = srgb_to_linear(rgb255 / 255.0)
    return float(0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2])


def mark(img_path: Path, lit: dict, sh: dict, out: Path) -> None:
    im = Image.open(img_path).convert("RGB").resize((1280, 720), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for p, col, label in ((lit, (255, 230, 80), "LIT"), (sh, (80, 200, 255), "SHADOW")):
        x, y = p["px"] * 2, p["py"] * 2
        d.rectangle([x - 8, y - 8, x + 8, y + 8], outline=col, width=2)
        d.line([(x - 16, y), (x + 16, y)], fill=col, width=1)
        d.line([(x, y - 16), (x, y + 16)], fill=col, width=1)
        d.text((x + 12, y - 24), f"{label} world=({p['x']:.1f},{p['z']:.1f}) px=({p['px']},{p['py']})", fill=col, font=ls.font(16))
    im.save(out)


def sweep_ambient(mults: list[float], extra: list[str], tag: str) -> None:
    rows = []
    items = []
    lit = sh = None
    for m in mults:
        name = f"calib_{tag}_ambient_{m:.2f}"
        path, probes = run(name, [f"ambient_mul={m}", "probe_grid=1", *extra])
        img = Image.open(path)
        if lit is None:
            lit, sh = pick_points(probes, img.size)
            print(f"計測点  日向: world=({lit['x']:.1f}, 0, {lit['z']:.1f}) px=({lit['px']},{lit['py']}) margin={lit['margin']}m wall={lit['wall']:.1f}m")
            print(f"        日陰: world=({sh['x']:.1f}, 0, {sh['z']:.1f}) px=({sh['px']},{sh['py']}) margin={sh['margin']}m wall={sh['wall']:.1f}m")
            mark(path, lit, sh, OUT / f"calib_{tag}_points.png")
        a = sample(img, lit["px"], lit["py"])
        b = sample(img, sh["px"], sh["py"])
        st = analyze(path)
        row = {
            "mult": m, "lit_L": lum_srgb(a), "sh_L": lum_srgb(b),
            "ratio_srgb": lum_srgb(b) / max(lum_srgb(a), 1e-6),
            "ratio_lin": lum_lin(b) / max(lum_lin(a), 1e-9),
            "lit_rgb": [int(round(v)) for v in a], "sh_rgb": [int(round(v)) for v in b],
            "p50": st["L_p50"], "p95": st["L_p95"], "sf40": st["shadow_fraction"]["L<40"],
            "dark_hue": st["dark_q"]["hue_deg"], "dark_sat": st["dark_q"]["sat"],
        }
        rows.append(row)
        items.append((f"ambient x{m:.2f}  ratio sRGB {row['ratio_srgb']:.3f} / lin {row['ratio_lin']:.3f}", path))
        print(f"x{m:<5.2f} lit L={row['lit_L']:6.1f} rgb={row['lit_rgb']}  shadow L={row['sh_L']:5.1f} rgb={row['sh_rgb']}  "
              f"ratio sRGB={row['ratio_srgb']:.3f} lin={row['ratio_lin']:.3f}   p50={row['p50']} p95={row['p95']} L<40={row['sf40']:.2f} darkhue={row['dark_hue']:.0f}")
    best = min(rows, key=lambda r: abs(r["ratio_srgb"] - 0.120))
    print(f"目標 0.120 に最も近い: ambient x{best['mult']:.2f} (sRGB {best['ratio_srgb']:.3f}, lin {best['ratio_lin']:.3f})")
    (OUT / f"calib_{tag}_ambient.json").write_text(json.dumps({"lit_point": lit, "shadow_point": sh, "rows": rows}, ensure_ascii=False, indent=1), encoding="utf-8")
    ls.sheet(f"calibration — ambient sweep ({tag})", items, OUT / f"calib_{tag}_ambient.png", cols=3)


def sweep_wall(albedos: list[float], extra: list[str], tag: str) -> None:
    items = []
    for a in albedos:
        name = f"calib_{tag}_wall_{a:.2f}"
        path, _ = run(name, [f"wall_albedo={a}", *extra])
        st = analyze(path)
        items.append((f"wall albedo {a:.2f}   p50 {st['L_p50']}  L<40 {st['shadow_fraction']['L<40']:.2f}", path))
        print(f"wall_albedo={a:.2f}  p5/p50/p95 = {st['L_p5']}/{st['L_p50']}/{st['L_p95']}")
    ls.sheet(f"calibration — wall albedo ({tag})", items, OUT / f"calib_{tag}_wall.png", cols=2)
    # 日陰の壁の拡大（右側の建物）
    crops = []
    for label, p in items:
        im = Image.open(p).convert("RGB")
        crops.append((label.split("  ")[0], im.crop((400, 40, 560, 160)).resize((640, 480), Image.NEAREST)))
    W, H, pad, cap = 640, 480, 12, 30
    cols = 2
    rows_n = (len(crops) + 1) // 2
    sheet = Image.new("RGB", (cols * W + (cols + 1) * pad, 60 + rows_n * (H + cap + pad)), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 14), "wall close-up (x4 nearest) — shaded wall, right side", fill=(235, 235, 235), font=ls.font(26))
    for i, (label, im) in enumerate(crops):
        x = pad + (i % cols) * (W + pad)
        y = 60 + (i // cols) * (H + cap + pad)
        sheet.paste(im, (x, y))
        d.text((x, y + H + 4), label, fill=(220, 220, 220), font=ls.font(20))
    ls.save_sheet(sheet, OUT / f"calib_{tag}_wall_closeup.png")


def sweep_tonemap(white: float, extra: list[str], tag: str) -> None:
    hashes = {}
    items = []
    for t in ls.TONEMAP_ORDER if hasattr(ls, "TONEMAP_ORDER") else ["linear", "reinhard", "filmic", "aces", "agx"]:
        name = f"calib_{tag}_tonemap_{t}_w{white:g}"
        path, _ = run(name, [f"tonemap={t}", f"white={white}", *extra])
        h = hashlib.sha256(path.read_bytes()).hexdigest()
        hashes[t] = h
        st = analyze(path)
        items.append((f"{t} white={white:g}", path))
        print(f"{t:9s} sha256={h}  p5/p50/p95={st['L_p5']}/{st['L_p50']}/{st['L_p95']}  L<40={st['shadow_fraction']['L<40']:.2f}")
    print("all different:", len(set(hashes.values())) == len(hashes))
    if ls.REF.exists():
        items.insert(0, ("REFERENCE", ls.REF))
    ls.sheet(f"calibration — tonemap (white={white:g}, {tag})", items, OUT / f"calib_{tag}_tonemap_w{white:g}.png", cols=3)


# ---------------------------------------------------------------------------
# D-1: 3 点（P_sun / P_open / P_core）での較正。固定した点で測る。
# ---------------------------------------------------------------------------
def probe_points(path_probes: list[dict], pts: list[tuple[float, float]]) -> list[dict]:
    out = []
    for x, z in pts:
        m = [p for p in path_probes if abs(p["x"] - x) < 1e-3 and abs(p["z"] - z) < 1e-3]
        if not m:
            sys.exit(f"計測点 ({x},{z}) が画面内にありません")
        out.append(m[0])
    return out


def run_points(name: str, args: list[str], pts: list[tuple[float, float]]) -> tuple[Path, list[dict]]:
    probe_arg = "probe=" + ";".join(f"{x},{z}" for x, z in pts)
    path, probes = run(name, [probe_arg, *args])
    return path, probe_points(probes, pts)


def lum_of(p: dict) -> float:
    return lum_srgb(np.asarray(p["rgb"]) * 255.0)


def lin_of(p: dict) -> float:
    return lum_lin(np.asarray(p["rgb"]) * 255.0)


def sweep_sky(pts: list[tuple[float, float]], amb_mults: list[float], sky_energies: list[float], sky_args: list[str], extra: list[str], tag: str) -> None:
    """手順 1: スカイライト OFF で ambient を振り P_core/P_sun = 0.120 に。
    手順 2: ambient 固定でスカイライト energy を振り P_open/P_sun = 0.26 に。手順 3: P_core の再確認。"""
    rows1 = []
    print("== 手順 1: skylight OFF, ambient_mul sweep (P_core/P_sun -> 0.120)")
    for m in amb_mults:
        path, pr = run_points(f"calib_{tag}_step1_amb{m:.2f}", [f"ambient_mul={m}", "skylight=0", *extra], pts)
        s, o, c = (lum_of(x) for x in pr)
        rows1.append({"mult": m, "P_sun": s, "P_open": o, "P_core": c, "core_ratio": c / s, "open_ratio": o / s, "core_ratio_lin": lin_of(pr[2]) / lin_of(pr[0])})
        print(f"  amb x{m:.2f}  P_sun={s:6.1f} P_open={o:5.1f} P_core={c:5.1f}  core/sun={c / s:.3f} open/sun={o / s:.3f}  shadow flags sun/open/core = {pr[0]['shadow']}/{pr[1]['shadow']}/{pr[2]['shadow']}")
    best1 = min(rows1, key=lambda r: abs(r["core_ratio"] - 0.120))
    m_best = best1["mult"]
    print(f"  -> ambient x{m_best:.2f} (core/sun {best1['core_ratio']:.3f})")

    rows2 = []
    print(f"== 手順 2: ambient x{m_best:.2f} 固定, skylight energy sweep (P_open/P_sun -> 0.26)")
    items = []
    for e in sky_energies:
        path, pr = run_points(f"calib_{tag}_step2_sky{e:.2f}", [f"ambient_mul={m_best}", "skylight=1", f"skylight_energy={e}", *sky_args, *extra], pts)
        s, o, c = (lum_of(x) for x in pr)
        rows2.append({"energy": e, "P_sun": s, "P_open": o, "P_core": c, "core_ratio": c / s, "open_ratio": o / s,
                      "sky_shadow_flags": [x["sky_shadow"] for x in pr]})
        items.append((f"skylight e={e:.2f}  open/sun {o / s:.3f}  core/sun {c / s:.3f}", path))
        print(f"  sky e={e:.2f}  P_sun={s:6.1f} P_open={o:5.1f} P_core={c:5.1f}  core/sun={c / s:.3f} open/sun={o / s:.3f}  sky_shadow sun/open/core = {[x['sky_shadow'] for x in pr]}")
    best2 = min(rows2, key=lambda r: abs(r["open_ratio"] - 0.26))
    print(f"  -> skylight energy {best2['energy']:.2f} (open/sun {best2['open_ratio']:.3f}, core/sun {best2['core_ratio']:.3f}; step1 core/sun was {best1['core_ratio']:.3f})")
    (OUT / f"calib_{tag}_sky.json").write_text(json.dumps({"points": pts, "step1": rows1, "step2": rows2, "adopt": {"ambient_mul": m_best, "skylight_energy": best2["energy"]}}, ensure_ascii=False, indent=1), encoding="utf-8")
    ls.sheet(f"D-1 pseudo skylight sweep ({tag})", items, OUT / f"calib_{tag}_sky.png", cols=3)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep", choices=["ambient", "wall", "tonemap", "sky"])
    ap.add_argument("--points", default="", help="sky: P_sun;P_open;P_core を x,z;x,z;x,z で")
    ap.add_argument("--sky-energies", default="0.1,0.2,0.3,0.45,0.6")
    ap.add_argument("--sky-args", default="", help="skylight_angle= / skylight_pitch= / skylight_yaw=")
    ap.add_argument("--mults", default="1.0,0.6,0.45,0.34,0.26,0.2")
    ap.add_argument("--albedos", default="0.18,0.35,0.50,0.65")
    ap.add_argument("--white", type=float, default=1.0)
    ap.add_argument("--tag", default="p2")
    ap.add_argument("--extra", default="", help="追加の lookdev 引数（空白区切り）例: 'ambient_mul=0.3 white=4'")
    a = ap.parse_args()
    extra = a.extra.split()
    if a.sweep == "sky":
        pts = [tuple(float(v) for v in p.split(",")) for p in a.points.split(";")]
        if len(pts) != 3:
            sys.exit("--points に 3 点（P_sun;P_open;P_core）を指定してください")
        sweep_sky(pts, [float(x) for x in a.mults.split(",")], [float(x) for x in a.sky_energies.split(",")], a.sky_args.split(), extra, a.tag)  # type: ignore[arg-type]
        return
    if a.sweep == "ambient":
        sweep_ambient([float(x) for x in a.mults.split(",")], extra, a.tag)
    elif a.sweep == "wall":
        sweep_wall([float(x) for x in a.albedos.split(",")], extra, a.tag)
    else:
        sweep_tonemap(a.white, extra, a.tag)


if __name__ == "__main__":
    main()
