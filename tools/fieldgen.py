# -*- coding: utf-8 -*-
"""フィールド生成の共通部（フェーズ 12〜14）。歩行可能マスク（唯一の真実）・高さ画像・JSON・シーンを書く。
座標は refs/field/<ID>.png と docs/field/<ID>_spec.md（調べ物・出入口はそのまま）。道は 6 タイル以上に広げる。
規則（Q-1）: 道（walk）を置くと、近景側（西・南）に 2 タイル、遠景側（東・北）に 1 タイルの帯（128）が自動で付く（bands=True のとき）。
帯の 1 列目は歩道、2 列目に生垣・ブロック塀・ガードレール。建物は両側に置く。階数・向きは地図と spec のまま（式は助言。隠れはフェードで解く）。
高さ（T-2）: 1 階調 = 0.15 m、0 = 基準面。坂・階段・橋は terrain の矩形で明示（docs/FIELD_FORMAT.md 第 8 節）。
"""
import json, os
from PIL import Image
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

NEAR_BAND = 2
NEAR_ITEMS = ["obj_bicycle_rack", "obj_air_conditioner_outdoor", "obj_planter_box", "obj_water_tank", "obj_laundry_pole", "obj_traffic_cone", "obj_potted_plant"]
WALK_EDGE = ["obj_utility_pole", "obj_street_light_led", "obj_mailbox", "obj_street_light_led", "obj_utility_pole", "obj_road_mirror"]
FRONT_ITEMS = ["obj_vending_machine", "obj_potted_plant", "obj_signboard_shutter", "obj_bicycle_rack", "obj_planter_box", "obj_flag_pole", "obj_air_conditioner_outdoor", "obj_mailbox", "obj_signboard_pole"]


class F:
    def __init__(self, fid, name, w, h, biome, elevation, scene_name):
        self.fid, self.name, self.w, self.h = fid, name, w, h
        self.biome, self.elevation, self.scene_name = biome, elevation, scene_name
        self.g = [[0] * w for _ in range(h)]          # 0 blocked / 255 walk / 192 narrow / 128 open
        self.hgt = [[0] * w for _ in range(h)]        # 高さ（階調）
        self.tex = {}
        self.patches, self.buildings, self.barriers, self.props, self.points, self.exits, self.areas = [], [], [], [], [], [], []
        self.trects = []
        self.twall = "retaining_wall"
        self.edge_fill = [{"rect": [0, 0, w, h], "kind": "fence_block"}]
        self.ground = {"walk": "asphalt", "narrow": "alley", "open": "lot_ground", "default": "lot_ground"}
        self.manual = set()
        self.bands = True
        self.note = ""

    # ---- マスク ----
    def inb(self, x, y): return 0 <= x < self.w and 0 <= y < self.h
    def fill(self, x0, y0, w, h, v, tex=None):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                if self.inb(x, y):
                    self.g[y][x] = v
                    if tex: self.tex[(x, y)] = tex
                    else: self.tex.pop((x, y), None)   # 上書きで前の模様（水田など）を残さない
                    self.manual.add((x, y))
    def walk(self, x0, y0, w, h, tex=None): self.fill(x0, y0, w, h, 255, tex)
    def narrow(self, x0, y0, w, h, tex=None): self.fill(x0, y0, w, h, 192, tex)
    def open(self, x0, y0, w, h, tex="asphalt"): self.fill(x0, y0, w, h, 128, tex)
    def block(self, x0, y0, w, h): self.fill(x0, y0, w, h, 0)
    def is_walk(self, x, y): return self.inb(x, y) and self.g[y][x] in (255, 192)

    # ---- 高さ（T-2）----
    def height(self, x0, y0, w, h, v):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                if self.inb(x, y): self.hgt[y][x] = max(0, min(255, int(v)))
    def ramp(self, x0, y0, w, h, axis, v0, v1, kind="slope", **kw):
        """axis の先頭のタイルが v0、末尾が v1 になるよう線形に。kind は slope / stairs"""
        n = (w if axis == "x" else h)
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                i = (x - x0) if axis == "x" else (y - y0)
                v = v0 + (v1 - v0) * (i + 0.5) / n if n > 1 else (v0 + v1) / 2
                if self.inb(x, y): self.hgt[y][x] = max(0, min(255, int(round(v))))
        e = {"kind": kind, "rect": [x0, y0, w, h]}; e.update(kw); self.trects.append(e)
    def stairs(self, x0, y0, w, h, axis, v0, v1, **kw): self.ramp(x0, y0, w, h, axis, v0, v1, "stairs", **kw)
    def bridge(self, x0, y0, w, h, deck="concrete_slab", **kw):
        e = {"kind": "bridge", "rect": [x0, y0, w, h], "deck": deck}; e.update(kw); self.trects.append(e)
    def wallzone(self, x0, y0, w, h, wall):
        self.trects.append({"kind": "wall", "rect": [x0, y0, w, h], "wall": wall})

    # ---- 近景の帯（Q-1、市街地）----
    def auto_bands(self):
        """歩けるタイルの西・南に 2、東・北に 1 の帯（open）。手動で置いたタイルは触らない"""
        add = {}
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x] != 0 or (x, y) in self.manual: continue
                d = None
                for k in range(1, NEAR_BAND + 1):
                    if self.is_walk(x + k, y) or self.is_walk(x, y - k):
                        d = k; break
                far = self.is_walk(x - 1, y) or self.is_walk(x, y + 1)
                if d is not None: add[(x, y)] = ("sidewalk", d)
                elif far: add[(x, y)] = ("sidewalk", 0)
        for (x, y), (tex, d) in add.items():
            self.g[y][x] = 128; self.tex[(x, y)] = tex
            # 帯の高さは隣の道に合わせる
            for dx, dy in ((1, 0), (0, -1), (-1, 0), (0, 1), (2, 0), (0, -2)):
                if self.is_walk(x + dx, y + dy):
                    self.hgt[y][x] = self.hgt[y + dy][x + dx]; break
        cells = sorted([c for c, (t, d) in add.items() if d == 2]); used = set()
        for (x, y) in cells:
            if (x, y) in used: continue
            if self.is_walk(x + 2, y):
                y1 = y
                while (x, y1 + 1) in add and add[(x, y1 + 1)][1] == 2 and self.is_walk(x + 2, y1 + 1): y1 += 1
                if y1 - y >= 2:
                    self.barriers.append({"kind": ["hedge", "fence_block", "wire_fence"][(y // 6) % 3], "rect": [x, y, 1, y1 - y + 1]})
                    for yy in range(y, y1 + 1): used.add((x, yy))
                    continue
            if self.is_walk(x, y - 2):
                x1 = x
                while (x1 + 1, y) in add and add[(x1 + 1, y)][1] == 2 and self.is_walk(x1 + 1, y - 2): x1 += 1
                if x1 - x >= 2:
                    self.barriers.append({"kind": ["guardrail", "hedge", "fence_block"][(x // 6) % 3], "rect": [x, y, x1 - x + 1, 1]})
                    for xx in range(x, x1 + 1): used.add((xx, y))
        n = [0, 0]
        for (x, y), (tex, d) in sorted(add.items(), key=lambda c: (c[0][1], c[0][0])):
            if d == 1 and (x + y) % 3 == 0:
                self.prop(WALK_EDGE[n[0] % len(WALK_EDGE)], x + 0.5, y + 0.5, "E" if self.is_walk(x + 1, y) else "N"); n[0] += 1
            elif d == 0 and (x + y) % 3 == 1:
                self.prop(FRONT_ITEMS[n[1] % len(FRONT_ITEMS)], x + 0.5, y + 0.5, "W" if self.is_walk(x - 1, y) else "S"); n[1] += 1

    # ---- 建物・塀・配置物 ----
    def b(self, kind, width, floors=2, wall="mortar", near=None, **kw):
        e = {"id": kw.pop("id", "b%02d" % len(self.buildings)), "kind": kind, "width": width, "floors": floors, "wall": wall}
        if near: e["near"] = near
        e.update(kw); self.buildings.append(e)
    def houses(self, n, kinds=("house", "house", "shop_wood", "house", "shop_shutter", "house"), floors=(2, 2, 2, 2, 2, 2), widths=(4, 3, 4, 4, 3, 4)):
        for i in range(n):
            self.b(kinds[i % len(kinds)], widths[i % len(widths)], floors[i % len(floors)], ["mortar", "weatherboard", "namako", "mortar"][i % 4], depth=3)
    def bar(self, kind, x0, y0, w, h, **kw):
        e = {"kind": kind, "rect": [x0, y0, w, h]}; e.update(kw); self.barriers.append(e)
    def prop(self, asset, x, y, facing=None, blocking=None, pid=None):
        e = {"id": pid or "o%03d" % len(self.props), "asset": asset, "at": [x, y]}
        if facing: e["facing"] = facing
        if blocking is not None: e["blocking"] = blocking
        self.props.append(e)
    def cars(self, cells):
        for (x, y) in cells: self.prop("obj_kei_car", x + 1.0, y + 0.5, "N")
    def trees(self, x0, y0, w, h, kind="ph_tree_conifer", step=2, seed=1, only_blocked=True):
        """矩形の中に step タイルごとに木（乱れあり）。既定は塞がれたタイルだけ"""
        import random
        rnd = random.Random(seed)
        for y in range(y0, y0 + h, step):
            for x in range(x0, x0 + w, step):
                xx, yy = x + rnd.randint(0, step - 1), y + rnd.randint(0, step - 1)
                if not self.inb(xx, yy): continue
                if only_blocked and self.g[yy][xx] != 0: continue
                self.prop(kind, xx + 0.5, yy + 0.5, "E")
    def point(self, pid, x, y, kind, label, when=None):
        e = {"id": pid, "at": [x, y], "kind": kind, "label": label}
        if when: e["when"] = when
        self.points.append(e)
    def exit(self, d, x, y, to, label, when=None):
        sp = {"N": (x, y + 1), "S": (x, y - 1), "W": (x + 1, y), "E": (x - 1, y)}[d]
        e = {"dir": d, "at": [x, y], "to": to, "spawn": [sp[0], sp[1]], "label": label}
        if when: e["when"] = when
        self.exits.append(e)

    # ---- 出力 ----
    def save(self, field_yaw=50, sun_evening=145):
        if self.bands: self.auto_bands()
        m = Image.new("L", (self.w, self.h), 0); px = m.load()
        for y in range(self.h):
            for x in range(self.w): px[x, y] = self.g[y][x]
        m.save("data/fields/%s_walkable.png" % self.fid)
        has_h = any(v for row in self.hgt for v in row)
        hp = "data/fields/%s_height.png" % self.fid
        if has_h:
            hm = Image.new("L", (self.w, self.h), 0); hpx = hm.load()
            for y in range(self.h):
                for x in range(self.w): hpx[x, y] = self.hgt[y][x]
            hm.save(hp)
        elif os.path.exists(hp):
            os.remove(hp)
        pid = 0
        for y in range(self.h):
            x = 0
            while x < self.w:
                t = self.tex.get((x, y))
                if t is None: x += 1; continue
                x1 = x
                while x1 + 1 < self.w and self.tex.get((x1 + 1, y)) == t: x1 += 1
                self.patches.append({"id": "p%03d" % pid, "rect": [x, y, x1 - x + 1, 1], "tex": t}); pid += 1
                x = x1 + 1
        note = "歩ける範囲は %s_walkable.png（唯一の真実）。座標は refs/field/%s.png と docs/field/%s_spec.md（調べ物・出入口はそのまま）。道は 6 タイル以上に広げた。" % (self.fid, self.fid, self.fid)
        if has_h: note += " 高さは %s_height.png（1 階調 = 0.15 m）。" % self.fid
        note += " tools/gen_fields_*.py が生成（フェーズ 12〜14）。" + self.note
        d = {"format": 2, "id": self.fid, "name": self.name, "size": [self.w, self.h], "elevation": self.elevation, "biome": self.biome,
             "scene": "res://scenes/fields/%s.tscn" % self.scene_name, "field_yaw": field_yaw, "sun_az": {"evening": sun_evening},
             "note": note, "walkable": "res://data/fields/%s_walkable.png" % self.fid}
        if has_h:
            d["height"] = "res://" + hp
            d["terrain"] = {"wall": self.twall, "rects": self.trects}
        d.update({"ground": dict(self.ground, patches=self.patches),
                  "edge_fill": self.edge_fill, "buildings": self.buildings, "barriers": self.barriers, "props": self.props,
                  "collision": {"extra_blocked": [], "extra_open": []}, "points": self.points, "exits": self.exits, "areas": self.areas})
        json.dump(d, open("data/fields/%s.json" % self.fid.lower(), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        tscn = '[gd_scene load_steps=2 format=3 uid="uid://c1game1field%s"]\n\n[ext_resource type="Script" path="res://scripts/field/field_scene.gd" id="1_field"]\n\n[node name="%s" type="Node3D"]\nscript = ExtResource("1_field")\nfield_id = "%s"\n' % (self.fid.lower(), self.fid, self.fid)
        open("scenes/fields/%s.tscn" % self.scene_name, "w", encoding="utf-8").write(tscn)
        print(self.fid, "buildings", len(self.buildings), "barriers", len(self.barriers), "props", len(self.props), "points", len(self.points), "exits", len(self.exits), "height" if has_h else "flat", "terrain", len(self.trects))
