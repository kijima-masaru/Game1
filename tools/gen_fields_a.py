# -*- coding: utf-8 -*-
"""A 群 5 枚（F01, F06, F12, F13, F02）の生成器 v2（フェーズ 11 P-4）。
規則を自動化する:
  - 道（walk）を置くと、近景側（西・南、カメラ = 西南西）に 6 タイル、遠景側（東・北）に 1 タイルの帯（128）が自動で付く
  - 近景の帯: 1 列目は歩道、2 列目に生垣/塀、3 列目以降は草地と配置物。屋根は帯の外（≥ 8 タイル ≒ 9 m）にしか来ない
  - 遠景の帯の裏に 2 階建てを隙間なく並べる（正面が画面に出る側）
  - 配置物は帯と正面の前に自動で寄せる。調べ物は仕様 md 未受領のため個数だけ合わせた仮の点
"""
import json, os
from PIL import Image
os.chdir(r"C:\Users\PC_User\Desktop\Game1")

NEAR_BAND = 11     # 西側（視線に沿う）。画面下 1/3 に屋根が入らない距離
NEAR_BAND_S = 4    # 南側（視線に対して斜め）
FAR_BAND = 1
NEAR_ITEMS = ["obj_bicycle_rack", "obj_air_conditioner_outdoor", "obj_planter_box", "obj_water_tank", "obj_laundry_pole", "obj_traffic_cone", "obj_potted_plant"]
WALK_EDGE = ["obj_utility_pole", "obj_street_light_led", "obj_mailbox", "obj_street_light_led", "obj_utility_pole", "obj_bus_stop_pole"]
FRONT_ITEMS = ["obj_vending_machine", "obj_potted_plant", "obj_signboard_shutter", "obj_bicycle_rack", "obj_planter_box", "obj_flag_pole", "obj_air_conditioner_outdoor", "obj_mailbox", "obj_signboard_pole"]

class F:
    def __init__(self, fid, name, w, h, biome, elevation, scene_name):
        self.fid, self.name, self.w, self.h = fid, name, w, h
        self.biome, self.elevation, self.scene_name = biome, elevation, scene_name
        self.g = [[0] * w for _ in range(h)]          # 0 blocked / 255 walk / 192 narrow / 128 open
        self.tex = {}                                  # (x,y) -> patch tex（open の質感）
        self.patches, self.buildings, self.barriers, self.props, self.points, self.exits, self.areas = [], [], [], [], [], [], []
        self.edge_fill = [{"rect": [0, 0, w, h], "kind": "fence_block"}]
        self.ground = {"walk": "asphalt", "narrow": "alley", "open": "grass", "default": "lot_ground"}
        self.keep_open = set()                          # 手動の open（駐車場など）
    def inb(self, x, y): return 0 <= x < self.w and 0 <= y < self.h
    def fill(self, x0, y0, w, h, v, tex=None):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                if self.inb(x, y):
                    self.g[y][x] = v
                    if tex: self.tex[(x, y)] = tex
                    if v == 128: self.keep_open.add((x, y))
    def walk(self, x0, y0, w, h): self.fill(x0, y0, w, h, 255)
    def narrow(self, x0, y0, w, h): self.fill(x0, y0, w, h, 192)
    def open(self, x0, y0, w, h, tex="asphalt"): self.fill(x0, y0, w, h, 128, tex)
    def is_walk(self, x, y): return self.inb(x, y) and self.g[y][x] in (255, 192)
    # ---- 自動の帯・塀・配置物 ----
    def auto_bands(self):
        """歩けるタイルの西・南に 6、東・北に 1 の帯（open）を付ける。既に歩ける/手動 open のタイルは触らない"""
        add = {}
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x] != 0: continue
                d = None
                for k in range(1, NEAR_BAND + 1):
                    if self.is_walk(x + k, y) or (k <= NEAR_BAND_S and self.is_walk(x, y - k)):
                        d = k if d is None else min(d, k); break
                far = self.is_walk(x - FAR_BAND, y) or self.is_walk(x, y + FAR_BAND)
                if d is not None:
                    add[(x, y)] = ("sidewalk" if d == 1 else "grass", d)
                elif far:
                    add[(x, y)] = ("sidewalk", 0)
        for (x, y), (tex, d) in add.items():
            self.g[y][x] = 128
            self.tex[(x, y)] = tex
            self.band_d = getattr(self, "band_d", {})
            self.band_d[(x, y)] = d
        # 塀・生垣: 近景の帯の 2 列目（d == 2）の連続区間
        cells = sorted([c for c, (t, d) in add.items() if d == 2])
        used = set()
        for (x, y) in cells:
            if (x, y) in used: continue
            # 縦の連続（西側の帯）
            if self.is_walk(x + 2, y):
                y1 = y
                while (x, y1 + 1) in add and add[(x, y1 + 1)][1] == 2 and self.is_walk(x + 2, y1 + 1): y1 += 1
                if y1 - y >= 2:
                    self.barriers.append({"kind": "hedge" if (y // 8) % 2 == 0 else "fence_block", "rect": [x, y, 1, y1 - y + 1]})
                    for yy in range(y, y1 + 1): used.add((x, yy))
                    continue
            if self.is_walk(x, y - 2):
                x1 = x
                while (x1 + 1, y) in add and add[(x1 + 1, y)][1] == 2 and self.is_walk(x1 + 1, y - 2): x1 += 1
                if x1 - x >= 2:
                    self.barriers.append({"kind": "guardrail" if (x // 8) % 2 == 0 else "hedge", "rect": [x, y, x1 - x + 1, 1]})
                    for xx in range(x, x1 + 1): used.add((xx, y))
        # 配置物: 歩道（d == 1）の縁に 3 タイルごと、草地（d == 4）に 4 タイルごと、遠景の帯（d == 0）に 3 タイルごと
        n = [0, 0, 0]
        for (x, y), (tex, d) in sorted(add.items(), key=lambda c: (c[0][1], c[0][0])):
            if d == 1 and (x + y) % 3 == 0:
                self.prop(WALK_EDGE[n[0] % len(WALK_EDGE)], x + 0.5, y + 0.5, "E" if self.is_walk(x + 1, y) else "N"); n[0] += 1
            elif d in (4, 7) and (x + y) % 4 == 0:
                self.prop(NEAR_ITEMS[n[1] % len(NEAR_ITEMS)], x + 0.5, y + 0.5, "E"); n[1] += 1
            elif d == 0 and (x + y) % 3 == 1:
                self.prop(FRONT_ITEMS[n[2] % len(FRONT_ITEMS)], x + 0.5, y + 0.5, "W" if self.is_walk(x - 1, y) else "S"); n[2] += 1
    def b(self, kind, width, floors=2, wall="mortar", near=None, **kw):
        e = {"id": kw.pop("id", "b%02d" % len(self.buildings)), "kind": kind, "width": width, "floors": floors, "wall": wall}
        if near: e["near"] = near
        e.update(kw); self.buildings.append(e)
    def houses(self, n, kinds=("house", "house", "shop_wood", "house", "shop_shutter", "house"), floors=(2, 2, 1, 2, 2, 1)):
        for i in range(n):
            self.b(kinds[i % len(kinds)], 3 if i % 3 else 4, floors[i % len(floors)], ["mortar", "weatherboard", "namako", "mortar"][i % 4])
    def prop(self, asset, x, y, facing=None, blocking=None):
        e = {"id": "o%03d" % len(self.props), "asset": asset, "at": [x, y]}
        if facing: e["facing"] = facing
        if blocking is not None: e["blocking"] = blocking
        self.props.append(e)
    def cars(self, cells):
        for (x, y) in cells: self.prop("obj_kei_car", x + 1.0, y + 0.5, "N")
    def point(self, x, y, kind, label): self.points.append({"id": "pt%02d" % len(self.points), "at": [x, y], "kind": kind, "label": label})
    def exit(self, d, x, y, to, label):
        sp = {"N": (x, y + 1), "S": (x, y - 1), "W": (x + 1, y), "E": (x - 1, y)}[d]
        self.exits.append({"dir": d, "at": [x, y], "to": to, "spawn": [sp[0], sp[1]], "label": label})
    def save(self, field_yaw=50, sun_evening=235):
        self.auto_bands()
        m = Image.new("L", (self.w, self.h), 0); px = m.load()
        for y in range(self.h):
            for x in range(self.w): px[x, y] = self.g[y][x]
        m.save("data/fields/%s_walkable.png" % self.fid)
        # 質感: 同じ tex の行の連続区間を patch に
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
        d = {"format": 2, "id": self.fid, "name": self.name, "size": [self.w, self.h], "elevation": self.elevation, "biome": self.biome,
             "scene": "res://scenes/fields/%s.tscn" % self.scene_name, "field_yaw": field_yaw, "sun_az": {"evening": sun_evening},
             "note": "歩ける範囲は %s_walkable.png（唯一の真実）。帯・塀・配置物は生成器 v2 が規則から自動配置。仕様 md 未受領のため調べ物は個数だけ合わせた仮の点（フェーズ 11 P-4）。" % self.fid,
             "walkable": "res://data/fields/%s_walkable.png" % self.fid, "ground": dict(self.ground, patches=self.patches),
             "edge_fill": self.edge_fill, "buildings": self.buildings, "barriers": self.barriers, "props": self.props,
             "collision": {"extra_blocked": [], "extra_open": []}, "points": self.points, "exits": self.exits, "areas": self.areas}
        json.dump(d, open("data/fields/%s.json" % self.fid.lower(), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        tscn = '[gd_scene load_steps=2 format=3 uid="uid://c1game1field%s"]\n\n[ext_resource type="Script" path="res://scripts/field/field_scene.gd" id="1_field"]\n\n[node name="%s" type="Node3D"]\nscript = ExtResource("1_field")\nfield_id = "%s"\n' % (self.fid.lower(), self.fid, self.fid)
        open("scenes/fields/%s.tscn" % self.scene_name, "w", encoding="utf-8").write(tscn)
        print(self.fid, "buildings", len(self.buildings), "barriers", len(self.barriers), "props", len(self.props), "points", len(self.points), "exits", len(self.exits))


# =============================================================== F01 国道281号 沿道商業地区 32×48
f = F("F01", "国道281号 沿道商業地区", 32, 48, "roadside_commercial", 1, "f01_kokudo")
f.walk(12, 0, 8, 48)                                   # 国道（8 タイル）。西側は帯（町の西端）
f.walk(20, 6, 12, 6); f.walk(20, 36, 12, 6)            # 東へ抜ける道（→ F06 / → F05）
f.open(21, 12, 4, 4, "asphalt"); f.cars([(21, 12), (23, 12), (21, 14), (23, 14)])   # 側道の南の駐車場
f.b("store", 6, 1, "concrete", near=[21, 18], id="sushi", height_m=4.6, roof="flat", sign="blue", depth=5)
f.b("store", 7, 1, "concrete", near=[21, 27], id="supermarket", height_m=5.0, roof="flat", sign="red", depth=5)
f.b("store", 5, 1, "concrete", near=[23, 34], id="conbini", height_m=4.2, roof="flat", sign="white", depth=3)
f.b("store", 5, 1, "concrete", near=[21, 2], id="drugstore", height_m=4.6, roof="flat", sign="yellow", depth=5)
f.houses(24)
f.prop("obj_road_mirror", 20.5, 12.5, "W"); f.prop("obj_road_mirror", 20.5, 42.5, "W"); f.prop("obj_public_phone", 19.5, 23.5, "W")
f.prop("obj_bus_stop_pole", 12.5, 20.5, "E"); f.prop("obj_bus_stop_pole", 19.5, 32.5, "W")
f.exit("N", 16, 0, "F02", "国道を北へ（於御所住宅地）"); f.exit("S", 16, 47, "F12", "国道を南へ（木平団地）")
f.exit("E", 31, 8, "F06", "市民センターへ"); f.exit("E", 31, 38, "F05", "旧街道の商店街へ")
for k, (x, y, kd) in enumerate([(19, 18, "door"), (19, 27, "door"), (19, 2, "door"), (25, 36, "door"), (12, 20, "sign"), (19, 32, "sign"), (19, 23, "item"),
                                (20, 13, "item"), (13, 4, "board"), (25, 7, "board"), (25, 37, "board"), (13, 44, "item"), (19, 12, "item")]):
    f.point(x, y, kd, "調べ物（仮）%d" % (k + 1))
f.save()

# =============================================================== F06 磐戸市民センター・交番前広場 40×32
f = F("F06", "磐戸市民センター・交番前広場", 40, 32, "civic_plaza", 2, "f06_civic")
f.walk(0, 24, 40, 6)                                   # 東西の主道路（→ F01 は西端 (0,26)）
f.walk(6, 0, 6, 24); f.walk(30, 0, 6, 24)              # 北へ（→ F02、→ F03）
f.walk(6, 30, 6, 2); f.walk(30, 30, 6, 2)              # 南へ（→ F05、→ F07）
f.walk(12, 14, 18, 10)                                 # 交番前広場（主道路と両方の道に接続）
f.b("civic", 9, 2, "concrete", near=[19, 12], id="civic_center", height_m=7.0, roof="flat", depth=5)
f.b("civic", 3, 1, "concrete", near=[12, 12], id="koban", height_m=3.6, roof="flat", depth=2)
f.b("civic", 4, 1, "concrete", near=[37, 10], id="post_office", height_m=4.0, roof="flat", depth=3)
f.houses(22)
f.prop("obj_bench", 15.5, 15.5, "S"); f.prop("obj_bench", 21.5, 15.5, "S"); f.prop("obj_bulletin_board", 18.5, 14.5, "S"); f.prop("obj_flag_pole", 24.5, 14.5, "S")
f.prop("obj_vending_machine", 13.5, 14.5, "S"); f.prop("obj_public_phone", 27.5, 22.5, "S"); f.prop("obj_bus_stop_pole", 13.5, 24.5, "S")
f.prop("obj_road_mirror", 12.5, 23.5, "W"); f.prop("obj_road_mirror", 36.5, 23.5, "W")
f.exit("W", 0, 26, "F01", "国道へ"); f.exit("N", 8, 0, "F02", "於御所住宅地へ"); f.exit("N", 32, 0, "F03", "バスストップ・高架下へ")
f.exit("S", 8, 31, "F05", "旧街道の商店街へ"); f.exit("S", 32, 31, "F07", "光明院 門前へ")
for k, (x, y, kd) in enumerate([(19, 14, "door"), (13, 14, "door"), (18, 15, "board"), (27, 22, "item"), (13, 24, "sign"), (36, 10, "door"), (8, 4, "sign"), (32, 28, "item")]):
    f.point(x, y, kd, "調べ物（仮）%d" % (k + 1))
f.save()

# =============================================================== F12 木平団地・支所前 40×32
f = F("F12", "木平団地・支所前", 40, 32, "housing_estate", 1, "f12_danchi")
f.walk(0, 18, 40, 6)                                   # 東西の道（→ F11 は東端 (39,20)）
f.walk(6, 0, 6, 18); f.walk(24, 0, 6, 18)              # 北へ（→ F01、→ F05）
f.walk(18, 24, 6, 8)                                   # 南へ（→ F13）
f.open(31, 11, 9, 3, "asphalt"); f.cars([(32, 11), (34, 11), (36, 11), (32, 12), (35, 12)])   # 団地の駐車場（奥側）
f.b("apartment", 8, 4, "concrete", near=[31, 6], id="danchi_a", height_m=11.5, roof="flat", depth=3)
f.b("apartment", 5, 4, "concrete", near=[32, 17], id="danchi_b", height_m=11.5, roof="flat", depth=3)
f.b("civic", 4, 2, "concrete", near=[38, 17], id="shisho", height_m=6.8, roof="flat", depth=3)
f.b("store", 4, 1, "concrete", near=[25, 25], id="shop_front", height_m=4.0, roof="flat", sign="white", depth=3)
f.houses(20)
f.prop("obj_public_phone", 13.5, 18.5, "S"); f.prop("obj_bus_stop_pole", 31.5, 18.5, "S"); f.prop("obj_road_mirror", 12.5, 17.5, "W"); f.prop("obj_road_mirror", 24.5, 23.5, "W")
f.exit("N", 8, 0, "F01", "国道へ"); f.exit("N", 26, 0, "F05", "旧街道の商店街へ"); f.exit("E", 39, 20, "F11", "小学校へ"); f.exit("S", 20, 31, "F13", "倉ノ前ニュータウンへ")
for k, (x, y, kd) in enumerate([(37, 18, "door"), (29, 6, "door"), (33, 18, "door"), (24, 26, "door"), (8, 3, "sign"), (26, 3, "sign"), (13, 19, "board"),
                                (30, 18, "item"), (20, 26, "sign"), (16, 19, "item"), (2, 20, "item"), (36, 19, "board")]):
    f.point(x, y, kd, "調べ物（仮）%d" % (k + 1))
f.save()

# =============================================================== F13 倉ノ前ニュータウン 48×32
f = F("F13", "倉ノ前ニュータウン", 48, 32, "newtown_residential", 1, "f13_newtown")
f.walk(0, 24, 48, 6)                                   # 東西の主道路（→ F10 は東端 (47,26)）
f.walk(8, 0, 6, 24); f.walk(8, 30, 6, 2)               # 南北の道（→ F12 / F15）
f.walk(34, 0, 6, 24)                                   # 北へ（→ F11）
f.open(24, 14, 8, 3, "grass"); f.prop("obj_bench", 26.5, 15.5, "S"); f.prop("obj_bench", 29.5, 15.5, "S")   # 小公園（帯の中）
f.houses(44, kinds=("house", "house", "house", "shop_wood", "house", "house"), floors=(2, 2, 1, 2, 2, 2))
f.prop("obj_bus_stop_pole", 15.5, 24.5, "S"); f.prop("obj_road_mirror", 14.5, 23.5, "W"); f.prop("obj_road_mirror", 40.5, 23.5, "W"); f.prop("obj_public_phone", 15.5, 4.5, "W")
f.exit("N", 10, 0, "F12", "木平団地へ"); f.exit("N", 36, 0, "F11", "小学校へ"); f.exit("E", 47, 26, "F10", "運動広場・河川敷へ"); f.exit("S", 10, 31, "F15", "蒼籠川の河畔へ")
for k, (x, y, kd) in enumerate([(9, 3, "sign"), (15, 24, "board"), (30, 25, "item"), (25, 23, "item"), (13, 15, "door"), (40, 8, "door"), (25, 25, "item"), (9, 30, "sign"), (44, 25, "board"), (36, 3, "item")]):
    f.point(x, y, kd, "調べ物（仮）%d" % (k + 1))
f.save()

# =============================================================== F02 於御所住宅地 48×32
f = F("F02", "於御所住宅地", 48, 32, "suburban_residential", 2, "f02_ogosho")
f.walk(0, 24, 48, 6)                                   # 東西の主道路（→ F03 は東端 (47,26)）
f.walk(6, 0, 6, 24); f.walk(6, 30, 6, 2)               # 南北の住宅街の道（→ F01）
f.walk(28, 12, 6, 12); f.walk(28, 30, 6, 2)            # 南北の道（→ F06）
f.narrow(13, 2, 11, 2)                                 # 裏路地（袋小路）
f.houses(44, kinds=("house", "house", "shop_wood", "house", "house", "house", "house", "shop_shutter"), floors=(2, 1, 2, 2, 2, 1, 2, 2))
f.prop("obj_public_phone", 27.5, 24.5, "S"); f.prop("obj_road_mirror", 12.5, 23.5, "W"); f.prop("obj_road_mirror", 34.5, 23.5, "W"); f.prop("obj_bus_stop_pole", 13.5, 24.5, "S")
f.exit("S", 8, 31, "F01", "国道へ"); f.exit("S", 30, 31, "F06", "市民センターへ"); f.exit("E", 47, 26, "F03", "バスストップ・高架下へ")
for k, (x, y, kd) in enumerate([(8, 3, "sign"), (13, 25, "door"), (30, 14, "item"), (36, 25, "board"), (13, 15, "door"), (30, 20, "item"), (20, 25, "item"), (40, 25, "door"), (8, 22, "sign"), (27, 24, "item"), (13, 5, "board")]):
    f.point(x, y, kd, "調べ物（仮）%d" % (k + 1))
f.save()
