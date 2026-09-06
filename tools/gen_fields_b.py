# -*- coding: utf-8 -*-
"""フェーズ 14 T-3: 残り 10 枚（F07, F14, F11, F03, F10, F15, F04, F08, F09, F16）の歩行可能マスク・高さ・JSON を生成する。
座標は refs/field/<ID>.png と docs/field/<ID>_spec.md（調べ物・出入口はそのまま）。資料との食い違いは docs/field/DEVIATIONS.md。
素材はプレースホルダ（assets/placeholder/、tools/gen_placeholders.py）。実行: python tools/gen_fields_b.py [F03 ...]
"""
import sys
from fieldgen import F

ONLY = set(a.upper() for a in sys.argv[1:])
def want(fid): return not ONLY or fid in ONLY

# =============================================================== F03 磐戸バスストップ・高架下 48×28（refs/field/F03.png）
# 高さ: 道 20（3.0 m）、高速 60（9.0 m）、南の法面の下（F06 側）0。段差 1 段 + 坂の最初の検証（T-2b）
if want("F03"):
    f = F("F03", "磐戸バスストップ・高架下", 48, 28, "highway_underpass", 2, "f03_bus_stop")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 48, 28], "kind": "none"}]
    f.ground = {"walk": "asphalt", "narrow": "alley", "open": "grass", "default": "grass"}
    f.twall = "retaining_wall"
    f.height(0, 0, 48, 28, 20)
    f.walk(0, 18, 48, 6)                                   # バス停の道（y 18〜23）。出入口 W (0,18)
    f.fill(0, 18, 48, 1, 255, "sidewalk"); f.fill(0, 23, 30, 1, 255, "sidewalk")   # 両側の歩道（歩ける）
    f.walk(30, 23, 18, 4, "dirt")                          # 高速北側の法面下の道（東へ → F09 E (47,26)）
    f.walk(30, 7, 18, 3, "dirt")                           # 北の農道（→ F04 E (47,8)）
    f.walk(34, 9, 5, 3, "dirt")                            # 農道から隧道へ
    f.walk(34, 12, 5, 6, "concrete_slab")                  # 隧道（高架の下）
    f.open(0, 12, 34, 5, "asphalt"); f.open(39, 12, 9, 5, "asphalt")   # 高速の路面（歩けない）
    f.height(0, 12, 34, 5, 60); f.height(39, 12, 9, 5, 60)
    f.bar("sound_wall", 1, 12, 33, 1); f.bar("sound_wall", 39, 12, 9, 1)
    f.bar("sound_wall", 1, 16, 33, 1); f.bar("sound_wall", 39, 16, 9, 1)
    f.bar("overpass", 34, 12, 5, 5, height_m=5.7, width_m=5.7)   # 隧道の上の高速の桁
    # 南の法面（x 0〜29）: 道 20 → 0。法面の階段（x 8〜9、20 段・3 m）で F06 へ下る
    f.open(0, 24, 30, 3, "grass")
    f.stairs(8, 24, 2, 4, "y", 15, 0, wall="stone_wall")
    f.fill(8, 24, 2, 4, 255, "stone_step")
    f.ramp(0, 24, 30, 3, "y", 15, 5)
    f.height(0, 27, 30, 1, 0)
    f.height(8, 27, 2, 1, 0)
    f.b("shelter", 3, 1, "concrete", near=[12, 17], id="bus_shelter", depth=1, front="S", note="高速バス停の待合")
    f.prop("obj_bus_stop_pole", 11.5, 18.5, "S", pid="bus_pole")
    f.prop("obj_bulletin_board", 10.5, 18.5, "S", pid="timetable"); f.prop("obj_bench", 13.5, 18.5, "S", pid="bench")
    f.prop("obj_vending_machine", 15.5, 18.5, "S", pid="vending")
    for x in (4.5, 20.5, 26.5, 32.5, 44.5): f.prop("obj_street_light_led", x, 18.5, "S")
    for x in (2.5, 18.5, 28.5, 40.5): f.prop("obj_utility_pole", x, 23.5, "N")
    f.prop("obj_utility_pole", 43.5, 6.5, "S"); f.prop("obj_road_mirror", 38.5, 10.5, "S")
    f.prop("obj_wire_fence", 45.5, 23.5, "S", pid="fence1"); f.prop("obj_wire_fence", 45.5, 24.5, "S", pid="fence2")
    f.prop("obj_road_closure_sign", 46.5, 24.5, "W", pid="fence_notice")
    f.prop("obj_guardrail", 30.5, 24.5, "E"); f.prop("obj_guardrail", 30.5, 26.5, "E")
    f.trees(0, 26, 30, 2, "ph_tree_conifer", step=2, seed=3); f.trees(30, 27, 18, 1, "ph_tree_conifer", step=2, seed=4)
    f.trees(0, 0, 48, 2, "ph_tree_broadleaf", step=6, seed=5); f.trees(0, 2, 30, 9, "ph_tree_kaki", step=5, seed=6)
    f.exit("W", 0, 18, "F02", "法面下の生活道路"); f.exit("S", 8, 27, "F06", "法面の階段を下りて市民センターへ")
    f.exit("E", 47, 8, "F04", "隧道を抜けた北側から農道へ"); f.exit("E", 47, 26, "F09", "隧道を抜け、高速北側の法面下を東へ。城址の搦手口。フェンス施錠", when="key_tunnel_fence")
    for pid, x, y, kd, lab in [("timetable", 10, 20, "board", "時刻表（欠便の張り紙）"), ("bench_item", 13, 21, "item", "待合ベンチの忘れ物"), ("vending_broken", 15, 20, "item", "自販機（故障）"),
                                ("graffiti", 35, 14, "board", "隧道内の落書き"), ("fence_notice", 46, 25, "board", "施錠フェンスの掲示")]:
        f.point(pid, x, y, kd, lab)
    f.note = "高さ: 道 3.0 m、高速 9.0 m、南の法面の下 0。法面の階段は 20 段（資料に高低差の記載なし、DEVIATIONS.md）。"
    f.save(sun_evening=145)

# =============================================================== F07 光明院 門前 48×36（refs/field/F07.png）。地形は裏手の石段の登り口だけ
if want("F07"):
    f = F("F07", "光明院 門前", 48, 36, "temple_precinct", 3, "f07_komyoin")
    f.bands = False
    f.edge_fill = [{"rect": [6, 6, 40, 28], "kind": "fence_wall"}, {"rect": [0, 0, 48, 36], "kind": "none"}]
    f.ground = {"walk": "gravel", "narrow": "alley", "open": "grass", "default": "grass"}
    f.twall = "stone_wall"
    f.walk(8, 8, 36, 24)                                   # 境内（砂利、x 8〜43・y 8〜31）
    f.walk(12, 0, 4, 8, "stone_path"); f.fill(12, 8, 4, 14, 255, "stone_path")   # 参道（北の出入口 (12,0) から）
    f.fill(12, 20, 21, 3, 255, "stone_path"); f.fill(22, 22, 4, 10, 255, "stone_path")   # 参道の折れ、南へ
    f.walk(22, 32, 4, 4, "stone_path")                     # 南門から小学校へ（S (22,35)）
    f.narrow(2, 1, 3, 20, "alley"); f.narrow(0, 20, 5, 2, "alley"); f.narrow(5, 1, 7, 2, "alley")   # 寺町の路地（W (0,20)）。北で参道につながる
    f.fill(18, 14, 13, 7, 255, "tile")                     # 本堂跡の礎石（石敷き）
    f.block(34, 12, 7, 7)                                  # 観音堂の区画
    f.b("temple_hall", 6, 1, "plaster", near=[33, 15], depth=7, id="kannondo", height_m=4.5, note="観音堂（格子から灯明）")
    f.b("temple_gate", 4, 1, "wood", at=[14, 7], depth=2, front="S", id="sanmon", note="山門")
    f.block(8, 30, 14, 2); f.block(26, 30, 18, 2)          # 南の縁の木立
    f.narrow(44, 11, 4, 3, "stone_step")                   # 裏手の石段の登り口（E (47,12) → F08）
    f.stairs(44, 11, 4, 3, "x", 2, 14, wall="stone_wall")
    f.height(44, 10, 4, 1, 8); f.height(44, 14, 4, 1, 8)
    f.prop("obj_bulletin_board", 9.5, 10.5, "E", pid="history_board"); f.prop("obj_water_basin", 15.5, 11.5, "S", pid="basin")
    f.prop("obj_stone_lantern", 32.5, 12.5, "W"); f.prop("obj_stone_lantern", 32.5, 17.5, "W"); f.prop("obj_offering_box", 32.5, 15.5, "W")
    for y in (24, 26, 28):
        for x in (10, 12, 14, 16): f.prop("obj_stone_marker", x + 0.5, y + 0.5, "S")
    f.prop("ph_tree_broadleaf", 30.5, 23.5, "E", pid="ginkgo"); f.prop("ph_tree_broadleaf", 32.5, 25.5, "E")
    f.prop("obj_stone_marker", 20.5, 17.5, "S"); f.prop("obj_stone_marker", 24.5, 16.5, "S"); f.prop("obj_stone_marker", 27.5, 18.5, "S")
    f.prop("obj_stone_lantern", 11.5, 9.5, "E"); f.prop("obj_stone_lantern", 16.5, 9.5, "W")
    f.trees(8, 30, 36, 2, "ph_tree_conifer", step=2, seed=7); f.trees(5, 0, 7, 6, "ph_tree_conifer", step=2, seed=8)
    f.trees(0, 22, 6, 14, "ph_tree_conifer", step=3, seed=9); f.trees(44, 0, 4, 10, "ph_tree_conifer", step=2, seed=10); f.trees(44, 15, 4, 21, "ph_tree_conifer", step=2, seed=11)
    f.trees(0, 0, 2, 20, "ph_tree_broadleaf", step=4, seed=12); f.trees(16, 0, 28, 6, "ph_tree_broadleaf", step=5, seed=13)
    f.exit("W", 0, 20, "F05", "寺町の路地→商店街"); f.exit("N", 12, 0, "F06", "路地→市民センター前")
    f.exit("S", 22, 35, "F11", "墓域脇の坂→小学校"); f.exit("E", 47, 12, "F08", "本堂跡の裏手の石段。天神社への唯一の道")
    for pid, x, y, kd, lab in [("kannon_lattice", 33, 14, "item", "観音堂の格子"), ("foundation", 23, 16, "item", "本堂の礎石"), ("muen_grave", 10, 24, "item", "無縁墓"),
                                ("history_board", 9, 10, "board", "寺の由来書き"), ("basin", 15, 11, "item", "手水鉢"), ("ginkgo", 30, 25, "item", "イチョウの幹")]:
        f.point(pid, x, y, kd, lab)
    f.note = "境内は砂利で歩ける。裏手の石段は登り口 4 タイル（16 段・2.4 m）だけ。"
    f.save(sun_evening=235)

# =============================================================== F14 朝和の里 56×36（refs/field/F14.png）。地形なし（水田は歩けない空き地）
if want("F14"):
    f = F("F14", "朝和の里", 56, 36, "paddy_shrine", 2, "f14_asawa")
    f.bands = False
    f.edge_fill = [{"rect": [20, 1, 13, 8], "kind": "fence_wall"}, {"rect": [0, 0, 56, 36], "kind": "none"}]
    f.ground = {"walk": "dirt", "narrow": "dirt", "open": "paddy", "default": "grass"}
    f.open(1, 2, 52, 30, "paddy")                          # 水田（歩けない）
    f.walk(0, 16, 53, 6)                                   # 集落の道（東西、→ F11 W (0,18)）
    f.narrow(1, 9, 52, 2); f.narrow(1, 27, 52, 2)          # 畦道（東西）
    f.narrow(12, 9, 2, 20); f.narrow(24, 9, 2, 20); f.narrow(36, 9, 2, 20)   # 畦道（南北）
    f.walk(17, 27, 6, 9)                                   # 農道→運動広場（S (19,35)）
    f.open(1, 8, 52, 1, "water"); f.walk(24, 8, 4, 1, "concrete_slab")   # 水路と、参道の小さな橋
    f.walk(21, 2, 12, 6, "gravel")                         # 式内社の境内
    f.block(23, 2, 8, 2)
    f.b("temple_hall", 8, 1, "plaster", near=[27, 4], depth=2, id="shikinaisha", height_m=3.8, note="式内社（小さな社の列）")
    f.b("temple_gate", 3, 1, "wood", at=[27, 7], depth=1, front="S", id="torii", note="鳥居")
    f.walk(38, 10, 15, 18, "grass")                        # 東の草地（古墳・石室）
    f.walk(44, 0, 4, 9, "dirt")                            # 薬師谷への林道（N (44,0)、序盤は落石で封鎖）
    f.walk(3, 25, 10, 2, "grass"); f.block(4, 21, 8, 4)    # 朝和家の前庭と区画
    f.b("house", 7, 2, "namako", near=[8, 25], depth=4, id="shige_house", note="朝和家（茅葺きの旧家）")
    f.prop("obj_bulletin_board", 21.5, 3.5, "E", pid="shrine_board"); f.prop("obj_offering_box", 26.5, 5.5, "S", pid="visitor_book")
    f.prop("obj_stone_lantern", 22.5, 6.5, "S"); f.prop("obj_stone_lantern", 31.5, 6.5, "S"); f.prop("obj_komainu", 25.5, 7.5, "S"); f.prop("obj_komainu", 29.5, 7.5, "S")
    f.prop("obj_block_wall", 30.5, 8.5, "S", pid="sluice")
    for (x, y) in [(42.5, 12.5), (43.5, 11.5), (44.5, 12.5), (43.5, 13.5), (47.5, 15.5), (48.5, 16.5), (49.5, 15.5), (43.5, 22.5), (44.5, 23.5), (45.5, 22.5)]: f.prop("ph_stone_pillar", x, y, "S")
    f.prop("ph_fire_tower", 13.5, 28.5, "S", pid="tower_bell"); f.prop("obj_signboard_pole", 42.5, 9.5, "S", pid="rock_sign")
    f.prop("obj_stone_marker", 30.5, 26.5, "S", pid="offering"); f.prop("obj_mailbox", 6.5, 25.5, "S")
    f.prop("ph_rock", 44.5, 5.5, "S", pid="rock1"); f.prop("ph_rock", 46.5, 6.5, "S", pid="rock2"); f.prop("ph_rock", 45.5, 7.5, "S", pid="rock3")
    for (x, y) in [(2.5, 15.5), (14.5, 15.5), (26.5, 15.5), (38.5, 15.5), (50.5, 15.5)]: f.prop("obj_utility_pole", x, y, "S")
    f.trees(0, 32, 56, 4, "ph_tree_conifer", step=2, seed=14); f.trees(53, 0, 3, 32, "ph_tree_conifer", step=2, seed=15); f.trees(0, 0, 20, 2, "ph_tree_broadleaf", step=4, seed=16)
    f.trees(33, 0, 11, 2, "ph_tree_broadleaf", step=3, seed=17); f.trees(48, 0, 5, 8, "ph_tree_conifer", step=2, seed=18); f.trees(38, 10, 15, 18, "ph_tree_broadleaf", step=6, seed=19, only_blocked=False)
    f.exit("W", 0, 18, "F11", "通用口→小学校"); f.exit("S", 19, 35, "F10", "農道→運動広場"); f.exit("N", 44, 0, "F16", "薬師谷への林道。序盤は落石で封鎖", when="flag_yakushi_open")
    for pid, x, y, kd, lab in [("shrine_board", 21, 3, "board", "式内社の由緒書き"), ("visitor_book", 26, 6, "item", "奉納帳"), ("kofun", 43, 13, "item", "古墳の石室入口"), ("sluice", 30, 8, "item", "水路の水門"),
                                ("tower_bell", 13, 28, "item", "火の見櫓"), ("rock_sign", 42, 8, "board", "落石の看板"), ("offering", 30, 26, "item", "畦の供え物"), ("shige_door", 7, 25, "door", "朝和家")]:
        f.point(pid, x, y, kd, lab)
    f.point("shige_npc", 8, 26, "npc", "シゲ", when="shige_present")
    f.note = "水田は空き地（歩けない）、畦道は narrow。林道の落石はプレースホルダの岩。"
    f.save(sun_evening=145)

# =============================================================== F11 磐戸第一小学校 48×40（refs/field/F11.png）。屋外のみ。屋内（F11_1f/2f）は作らない
if want("F11"):
    f = F("F11", "磐戸第一小学校", 48, 40, "school_dungeon", 2, "f11_school")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 48, 40], "kind": "none"}]
    f.ground = {"walk": "dirt", "narrow": "alley", "open": "grass", "default": "grass"}
    f.walk(2, 2, 44, 36)                                   # 校庭
    f.open(1, 1, 46, 1, "grass"); f.open(1, 38, 46, 1, "grass"); f.open(1, 1, 1, 38, "grass"); f.open(46, 1, 1, 38, "grass")   # 金網の帯
    f.bar("wire_fence", 1, 1, 20, 1); f.bar("wire_fence", 25, 1, 22, 1); f.bar("wire_fence", 1, 38, 9, 1); f.bar("wire_fence", 16, 38, 16, 1); f.bar("wire_fence", 38, 38, 9, 1)
    f.bar("wire_fence", 1, 1, 1, 15); f.bar("wire_fence", 1, 22, 1, 17); f.bar("wire_fence", 46, 1, 1, 17); f.bar("wire_fence", 46, 24, 1, 15)
    f.narrow(21, 0, 4, 2, "asphalt"); f.walk(0, 16, 2, 6, "asphalt"); f.walk(10, 38, 6, 2, "asphalt"); f.walk(32, 38, 6, 2, "asphalt"); f.walk(46, 18, 2, 6, "asphalt")   # 校門
    f.block(8, 3, 33, 7)
    f.b("school", 30, 3, "concrete", near=[24, 10], depth=7, id="new_school", height_m=10.5, roof="flat", note="新校舎（RC 3 階）")
    f.block(36, 15, 8, 12)
    f.b("school", 9, 2, "weatherboard", near=[35, 20], depth=8, id="old_school", height_m=7.2, roof="gable", note="旧校舎（木造 2 階）。屋内は作らない")
    f.block(3, 24, 9, 11)
    f.b("gym", 9, 1, "concrete", near=[7, 23], depth=11, id="gym", height_m=9.0, roof="flat", note="体育館")
    f.block(4, 12, 3, 2)
    f.b("house", 3, 1, "weatherboard", near=[5, 14], depth=2, id="hutch", height_m=2.2, note="飼育小屋")
    f.prop("obj_stone_marker", 14.5, 11.5, "S", pid="pedestal"); f.prop("obj_bench", 24.5, 14.5, "S", pid="platform"); f.prop("obj_water_tank", 9.5, 14.5, "S", pid="weather_box")
    f.fill(10, 18, 24, 1, 255, "sidewalk"); f.fill(10, 30, 24, 1, 255, "sidewalk")   # 白線の代わりの帯
    for x in (12, 18, 24, 30): f.prop("obj_hedge", x + 0.5, 36.5, "S")
    for (x, y) in [(3.5, 3.5), (44.5, 3.5), (3.5, 21.5), (44.5, 12.5), (20.5, 36.5), (40.5, 36.5)]: f.prop("obj_street_light_led", x, y, "S")
    f.prop("obj_flag_pole", 22.5, 11.5, "S"); f.prop("obj_bicycle_rack", 42.5, 29.5, "N"); f.prop("obj_bicycle_rack", 42.5, 31.5, "N"); f.prop("obj_water_basin", 13.5, 24.5, "S")
    f.trees(0, 0, 48, 1, "ph_tree_broadleaf", step=4, seed=20); f.trees(0, 39, 48, 1, "ph_tree_broadleaf", step=4, seed=21); f.trees(0, 1, 1, 38, "ph_tree_broadleaf", step=4, seed=22); f.trees(47, 1, 1, 38, "ph_tree_broadleaf", step=4, seed=23)
    f.exit("N", 22, 0, "F07", "正門→坂→光明院"); f.exit("W", 0, 18, "F12", "西門→団地"); f.exit("S", 12, 39, "F13", "南門→ニュータウン"); f.exit("S", 34, 39, "F10", "裏門→運動広場"); f.exit("E", 47, 20, "F14", "東の通用口→朝和の里")
    for pid, x, y, kd, lab in [("staff_room", 24, 8, "door", "新校舎 職員室"), ("old_entrance", 36, 20, "door", "旧校舎の昇降口"), ("pedestal", 14, 11, "item", "像の台座"), ("platform", 24, 14, "item", "朝礼台"),
                                ("gym_door", 7, 24, "door", "体育館"), ("hutch", 5, 13, "item", "飼育小屋"), ("weather_box", 9, 14, "item", "百葉箱")]:
        f.point(pid, x, y, kd, lab)
    f.note = "屋外のみ。校舎の階数は地図の窓の段数から（新校舎 3、旧校舎 2）。"
    f.save(sun_evening=145)

# =============================================================== F10 磐戸運動広場・河川敷 48×32（refs/field/F10.png）。堤防 3.0 m
if want("F10"):
    f = F("F10", "磐戸運動広場・河川敷", 48, 32, "riverside_ground", 1, "f10_ground")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 48, 32], "kind": "none"}]
    f.ground = {"walk": "grass", "narrow": "alley", "open": "grass", "default": "grass"}
    f.twall = "concrete_slab"
    f.walk(0, 0, 48, 2, "asphalt")                         # 北の道（N (10,0)・(40,0)）
    f.walk(0, 2, 47, 21, "grass")                          # 草地（歩ける）
    f.fill(7, 7, 35, 16, 255, "dirt")                      # グラウンド
    f.fill(24, 5, 1, 18, 255, "sidewalk")                  # 白線（途中で消える）
    f.open(0, 23, 48, 3, "grass"); f.ramp(0, 23, 48, 3, "y", 3, 17)          # 堤防の北の法面
    f.walk(10, 23, 6, 3, "grass"); f.walk(30, 23, 6, 3, "grass")             # 法面を上る道（坂の中）
    f.walk(0, 26, 48, 2, "asphalt"); f.height(0, 26, 48, 2, 20)              # 堤防道路
    f.open(0, 28, 48, 3, "grass"); f.ramp(0, 28, 48, 3, "y", 17, 3)          # 南の法面（河畔へ）
    f.walk(10, 28, 6, 4, "dirt"); f.height(10, 31, 6, 1, 0); f.height(0, 31, 10, 1, 0); f.height(16, 31, 32, 1, 0)   # 堤防を下る道（S (12,31)）
    f.block(42, 8, 4, 3)
    f.b("house", 4, 1, "concrete", near=[44, 11], depth=3, id="shed", roof="flat", height_m=2.8, note="用具倉庫")
    for (x, y) in [(7.5, 8.0), (7.5, 10.0), (7.5, 12.0)]: f.prop("ph_backnet", x, y, "E")
    for (x, y) in [(9.0, 6.5), (11.0, 6.5)]: f.prop("ph_backnet", x, y, "S")
    for (x, y) in [(5.5, 4.5), (5.5, 22.5), (43.5, 4.5), (43.5, 22.5)]: f.prop("ph_light_tower", x, y, "S")
    for (x, y) in [(11.5, 23.0), (13.5, 23.0), (16.5, 23.0), (18.5, 23.0)]: f.prop("obj_bench", x, y, "N")
    f.prop("obj_water_tank", 5.5, 23.5, "S", pid="panel"); f.prop("obj_stone_marker", 24.5, 5.5, "S", pid="line_stake"); f.prop("obj_stone_marker", 30.5, 26.5, "S", pid="marker")
    for x in (2, 8, 20, 32, 44): f.prop("obj_guardrail", x + 0.5, 26.5, "S")
    f.trees(0, 30, 10, 2, "ph_tree_conifer", step=2, seed=24); f.trees(16, 30, 32, 2, "ph_tree_conifer", step=2, seed=25); f.trees(0, 2, 48, 1, "ph_tree_broadleaf", step=8, seed=26, only_blocked=False)
    f.exit("W", 0, 14, "F13", "堤防道路→ニュータウン"); f.exit("N", 10, 0, "F11", "小学校の裏門"); f.exit("N", 40, 0, "F14", "農道→朝和の里"); f.exit("S", 12, 31, "F15", "堤防を下って河畔")
    for pid, x, y, kd, lab in [("shed", 44, 10, "door", "用具倉庫"), ("dugout", 11, 22, "item", "ダッグアウト"), ("panel", 5, 23, "item", "照明塔の配電盤"), ("line_stake", 24, 5, "item", "白線の起点"),
                                ("marker", 30, 26, "item", "堤防の距離標"), ("backnet", 8, 6, "item", "バックネット")]:
        f.point(pid, x, y, kd, lab)
    f.note = "堤防は 3.0 m（資料に高さの記載なし）。法面は坂、上り下りの道は坂の中の歩けるタイル。"
    f.save(sun_evening=145)

# =============================================================== F15 蒼籠川 河畔・御渡橋 64×24（refs/field/F15.png）。堤防 3.6 m、河原 1.2 m、川面 0
if want("F15"):
    f = F("F15", "蒼籠川 河畔・御渡橋", 64, 24, "riverbank_bridge", 0, "f15_riverbank")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 64, 24], "kind": "none"}]
    f.ground = {"walk": "sand", "narrow": "alley", "open": "grass", "default": "grass"}
    f.twall = "concrete_slab"
    f.height(0, 0, 64, 4, 24)
    f.walk(0, 1, 64, 3, "asphalt"); f.walk(3, 0, 6, 1, "asphalt"); f.walk(51, 0, 6, 1, "asphalt")   # 堤防道路（N (5,0)・(53,0)）
    f.open(0, 4, 64, 3, "grass"); f.ramp(0, 4, 64, 3, "y", 21, 11)            # 堤防の法面
    f.height(0, 7, 64, 6, 8); f.walk(0, 7, 64, 6, "sand")                     # 河原
    f.narrow(8, 4, 4, 3, "stone_step"); f.stairs(8, 4, 4, 3, "y", 21, 11, wall="concrete_slab")   # 渡し場跡の段（堤防↔河原）
    f.narrow(44, 4, 4, 3, "stone_step"); f.stairs(44, 4, 4, 3, "y", 21, 11, wall="concrete_slab")   # 東の段（橋で河原が分かれるため。DEVIATIONS.md）
    f.open(0, 13, 64, 6, "water"); f.height(0, 13, 64, 6, 0)                  # 川
    f.open(0, 19, 64, 4, "sand"); f.height(0, 19, 64, 4, 8)                   # 対岸（霧で見えない、歩けない）
    f.height(0, 23, 64, 1, 8)
    f.walk(31, 4, 5, 19, "concrete_slab"); f.height(31, 4, 5, 19, 24); f.bridge(31, 4, 5, 19, "concrete_slab", bottom=0)   # 御渡橋
    f.prop("obj_road_closure_sign", 31.5, 16.5, "N", pid="barricade1"); f.prop("obj_road_closure_sign", 33.5, 16.5, "N", pid="barricade2"); f.prop("obj_road_closure_sign", 35.5, 16.5, "N", pid="barricade3")
    f.prop("obj_street_light_mercury", 31.5, 9.5, "E", pid="bridge_lamp_w"); f.prop("obj_street_light_mercury", 35.5, 9.5, "W", pid="bridge_lamp_e")
    f.prop("obj_stone_marker", 12.5, 8.5, "S", pid="stele"); f.prop("obj_signboard_pole", 40.5, 12.5, "S", pid="gauge"); f.prop("ph_rock", 48.5, 11.5, "S", pid="driftwood"); f.prop("obj_bench", 20.5, 2.5, "S", pid="bench")
    for x in range(1, 63, 4):
        if not (3 <= x <= 8 or 51 <= x <= 56): f.prop("ph_tree_broadleaf", x + 0.5, 0.5, "S")
    f.trees(0, 23, 64, 1, "ph_tree_conifer", step=2, seed=27)
    f.exit("N", 5, 0, "F13", "旧街道の渡し場跡→ニュータウン"); f.exit("N", 53, 0, "F10", "堤防→運動広場")
    for pid, x, y, kd, lab in [("stele", 12, 8, "board", "渡し場跡の石碑"), ("barricade", 31, 16, "item", "橋のバリケード"), ("gauge", 40, 12, "item", "水位標"), ("driftwood", 48, 11, "item", "流れ着いた物"), ("bench", 20, 2, "item", "桜並木のベンチ")]:
        f.point(pid, x, y, kd, lab)
    f.point("yu_npc", 31, 20, "npc", "悠", when="yu_present")
    f.note = "川面 0、河原 1.2 m、堤防と橋 3.6 m（資料に高さの記載なし）。橋はバリケードで中ほどまで。対岸は歩けない。"
    f.save(sun_evening=145)

# =============================================================== F04 八柱の谷戸 48×32（refs/field/F04.png）。谷戸の緩い坂（西 0.6 m → 東 3.6 m）と南の崖
if want("F04"):
    f = F("F04", "八柱の谷戸", 48, 32, "orchard_valley", 4, "f04_yahashira")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 48, 32], "kind": "none"}]
    f.ground = {"walk": "grass", "narrow": "dirt", "open": "grass", "default": "grass"}
    f.twall = "rock"
    f.ramp(0, 0, 48, 30, "x", 4, 24)                       # 谷戸全体が東へ上る緩い坂
    f.height(0, 30, 48, 2, 0)                              # 南の崖の下（F09 側、通行不能）
    f.walk(0, 4, 31, 6, "dirt")                            # 農道（W (0,7)）
    f.walk(4, 10, 20, 16, "grass")                         # 柿畑（歩ける、農道に続く）
    f.open(24, 10, 1, 16, "grass"); f.bar("wire_fence", 24, 10, 1, 16)        # 電気柵（切れている）
    f.walk(25, 10, 22, 18, "grass")                        # 小屋の周りと石柱の跡の草地
    f.narrow(40, 10, 2, 16, "dirt"); f.narrow(30, 10, 12, 1, "dirt"); f.narrow(34, 25, 8, 3, "dirt")   # 獣道（行き止まり）
    f.block(27, 12, 6, 5)
    f.b("house", 5, 1, "weatherboard", near=[29, 17], depth=5, id="shed", height_m=3.0, note="放棄された農機具小屋（裸電球）")
    for y in (12, 16, 20, 24):
        for x in (6, 10, 14, 18, 22): f.prop("ph_tree_kaki", x + 0.5, y + 0.5, "E")
    f.prop("obj_water_tank", 23.5, 10.5, "S", pid="battery")
    for (x, y) in [(39.5, 20.5), (34.5, 16.5), (36.5, 18.5), (38.5, 22.5), (40.5, 24.5), (33.5, 24.5), (36.5, 21.5), (42.5, 18.5)]: f.prop("ph_stone_pillar", x, y, "S")
    f.prop("obj_signboard_pole", 41.5, 26.5, "S", pid="trail_sign")
    f.trees(28, 0, 14, 4, "ph_tree_broadleaf", step=3, seed=28); f.trees(0, 28, 48, 2, "ph_tree_conifer", step=2, seed=29); f.trees(0, 0, 28, 4, "ph_tree_broadleaf", step=6, seed=30)
    f.trees(0, 10, 4, 18, "ph_tree_conifer", step=3, seed=31); f.trees(42, 0, 6, 10, "ph_tree_conifer", step=3, seed=32)
    f.exit("W", 0, 7, "F03", "農道→隧道の北口へ")
    for pid, x, y, kd, lab in [("shed_door", 28, 15, "door", "農機具小屋の日誌"), ("battery", 24, 10, "item", "電気柵のバッテリー"), ("cloth_tree", 14, 15, "item", "柿の木に結ばれた布"),
                                ("footprints", 36, 12, "item", "獣の足跡"), ("pillar", 39, 20, "item", "石柱の刻字"), ("trail_sign", 41, 26, "board", "獣道の行き止まり")]:
        f.point(pid, x, y, kd, lab)
    f.note = "谷戸の坂と崖の高さは資料に無いので仮（西 0.6 m → 東 3.6 m、南の崖は最大 3.6 m）。"
    f.save(sun_evening=145)

# =============================================================== F08 臥牛山 天神社 40×48（refs/field/F08.png）。石段 56 段（8.4 m）、境内と梅林は山上
if want("F08"):
    f = F("F08", "臥牛山 天神社", 40, 48, "hilltop_shrine", 5, "f08_tenjin")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 40, 48], "kind": "none"}]
    f.ground = {"walk": "grass", "narrow": "stone_step", "open": "grass", "default": "grass"}
    f.twall = "rock"
    f.height(7, 0, 33, 48, 56)                             # 山上（x 7〜39）
    f.ramp(7, 3, 4, 14, "y", 54, 2); f.trects.pop()        # 石段の両脇（x 7・10）は同じ勾配の段々
    f.narrow(8, 3, 2, 14, "stone_step"); f.stairs(8, 3, 2, 14, "y", 54, 2, wall="stone_wall")
    f.height(0, 16, 10, 3, 0); f.walk(0, 16, 8, 3, "stone_path")             # 麓（W (0,16)）
    f.height(0, 0, 7, 16, 0); f.height(0, 19, 7, 29, 0)
    f.walk(11, 4, 13, 8, "gravel"); f.narrow(11, 2, 13, 2, "gravel"); f.narrow(8, 2, 3, 1, "gravel")   # 境内（北の 2 列は社の脇の細道）
    f.block(14, 5, 7, 4); f.block(15, 2, 5, 2)
    f.b("temple_hall", 7, 1, "plaster", near=[17, 9], depth=4, id="haiden", height_m=4.6, note="拝殿")
    f.b("temple_hall", 5, 1, "plaster", near=[17, 4], depth=2, id="honden", height_m=3.6, note="本殿")
    f.b("temple_gate", 3, 1, "wood", at=[9, 1], depth=1, front="S", id="torii", note="鳥居")
    f.prop("ph_cow_statue", 11.5, 4.5, "E", pid="cow"); f.prop("obj_bulletin_board", 19.5, 4.5, "S", pid="ema")
    f.prop("obj_water_basin", 11.5, 9.5, "E", pid="basin"); f.prop("obj_offering_box", 19.5, 9.5, "S", pid="mask_box")
    f.prop("obj_stone_lantern", 13.5, 10.5, "S"); f.prop("obj_stone_lantern", 18.5, 10.5, "S"); f.prop("obj_block_wall", 12.0, 8.5, "S"); f.prop("obj_block_wall", 21.0, 8.5, "S")
    f.walk(11, 12, 28, 33, "grass")                        # 梅林（歩ける。木は 3 タイルごと）
    for y in range(13, 44, 3):
        for x in range(11, 38, 3):
            if (x, y) not in [(23, 28), (26, 28)]: f.prop("ph_tree_ume", x + 0.5 + ((y // 3) % 2) * 0.5, y + 0.5, "E")
    f.prop("obj_stone_marker", 24.5, 27.5, "S", pid="small_shrine")
    f.walk(31, 45, 8, 3, "stone_path")                     # 展望所
    f.prop("obj_bench", 33.5, 45.5, "S"); f.prop("obj_bulletin_board", 36.5, 45.5, "S", pid="lookout")
    for x in range(10, 23, 2):
        if x not in (16, 18): f.prop("ph_tree_conifer", x + 0.5, 11.5, "E")
    f.trees(0, 0, 7, 16, "ph_tree_conifer", step=2, seed=33); f.trees(0, 19, 7, 29, "ph_tree_conifer", step=2, seed=34); f.trees(10, 0, 30, 2, "ph_tree_conifer", step=2, seed=35)
    f.trees(24, 2, 16, 10, "ph_tree_conifer", step=2, seed=36); f.trees(7, 19, 3, 29, "ph_tree_conifer", step=2, seed=37); f.trees(39, 12, 1, 36, "ph_tree_conifer", step=2, seed=38)
    f.trees(10, 44, 21, 4, "ph_tree_conifer", step=2, seed=39); f.trees(31, 44, 9, 1, "ph_tree_conifer", step=2, seed=40)
    f.exit("W", 0, 16, "F07", "長い石段を下って光明院の裏手へ")
    for pid, x, y, kd, lab in [("cow", 9, 4, "item", "撫で牛"), ("ema", 19, 4, "board", "絵馬掛け"), ("haiden", 14, 6, "door", "拝殿"), ("basin", 10, 9, "item", "手水舎"),
                                ("mask_box", 19, 9, "item", "面掛け所の保管箱"), ("small_shrine", 24, 27, "item", "梅林の祠"), ("lookout", 33, 46, "item", "展望所からの町の眺め")]:
        f.point(pid, x, y, kd, lab)
    f.note = "石段は地図の 14 タイルに 56 段（8.4 m）。資料の約 200 段は F07 側と画面外の登りとして扱う（DEVIATIONS.md）。"
    f.save(sun_evening=235)

# =============================================================== F09 磐戸城址 56×44（refs/field/F09.png）。地面 3.0 m、空堀 0、土塁 6.0 m、曲輪 3.6 m、主郭 4.8 m
if want("F09"):
    f = F("F09", "磐戸城址", 56, 44, "castle_ruins", 5, "f09_castle_ruins")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 56, 44], "kind": "none"}]
    f.ground = {"walk": "grass", "narrow": "dirt", "open": "grass", "default": "grass"}
    f.twall = "earth"
    f.height(0, 0, 56, 44, 20)
    f.walk(0, 4, 10, 6, "dirt")                            # 搦手口からの道（W (0,6)）
    f.narrow(8, 10, 2, 8, "dirt"); f.walk(5, 17, 9, 6, "grass")               # 案内板の草地
    f.narrow(12, 12, 40, 24, "dirt"); f.height(12, 12, 40, 24, 0)              # 空堀の輪（底は歩ける）
    f.narrow(14, 14, 36, 20, "grass"); f.height(14, 14, 36, 20, 40)            # 土塁（上を歩ける）
    f.walk(17, 17, 30, 14, "grass"); f.height(17, 17, 30, 14, 24)              # 曲輪
    f.narrow(12, 20, 2, 2, "dirt"); f.height(12, 20, 2, 2, 20)                 # 土橋（空堀をまたぐ）
    f.narrow(14, 19, 4, 4, "dirt"); f.ramp(14, 19, 4, 4, "x", 20, 24)          # 虎口（土塁の切れ目、坂。法面より先に）
    f.ramp(15, 15, 34, 2, "y", 36, 28); f.ramp(15, 30, 34, 2, "y", 28, 36); f.ramp(15, 17, 2, 13, "x", 36, 28); f.ramp(47, 17, 2, 13, "x", 28, 36)   # 土塁の内側の法面（2 列）
    f.narrow(15, 15, 34, 2, "grass"); f.narrow(15, 30, 34, 2, "grass"); f.narrow(15, 17, 2, 13, "grass"); f.narrow(47, 17, 2, 13, "grass")
    f.narrow(14, 19, 4, 4, "dirt")
    f.wallzone(12, 12, 40, 24, "earth")
    f.walk(27, 22, 9, 4, "tile"); f.height(27, 22, 9, 4, 32); f.wallzone(27, 22, 9, 4, "stone_wall")   # 主郭の礎石の台
    f.narrow(30, 26, 3, 2, "stone_step"); f.stairs(30, 26, 3, 2, "y", 30, 26, wall="stone_wall")
    f.open(16, 36, 4, 3, "grass"); f.ramp(16, 36, 4, 3, "y", 3, 17); f.narrow(16, 36, 4, 3, "dirt")   # 空堀へ下りる坂（南西）
    f.open(0, 40, 56, 4, "water"); f.height(0, 40, 56, 4, 0)                   # 川
    f.block(52, 0, 4, 40); f.height(52, 0, 4, 40, 44); f.wallzone(52, 0, 4, 40, "rock")   # F04 側の断崖
    f.prop("obj_bulletin_board", 6.5, 17.5, "E", pid="map_board"); f.prop("obj_stone_marker", 12.5, 19.5, "S", pid="bridge_marker")
    for (x, y) in [(28.5, 23.5), (31.5, 22.5), (34.5, 24.5), (29.5, 25.5)]: f.prop("obj_stone_marker", x, y, "S")
    f.prop("ph_rock", 20.5, 33.5, "S", pid="moat_item"); f.prop("obj_signboard_pole", 28.5, 30.5, "N", pid="hidden_exit")
    for (x, y) in [(20.5, 18.5), (38.5, 22.5), (24.5, 27.5), (41.5, 27.5), (30.5, 19.5)]: f.prop("ph_tree_conifer", x, y, "E")
    f.trees(0, 0, 52, 4, "ph_tree_conifer", step=2, seed=41); f.trees(0, 10, 8, 30, "ph_tree_conifer", step=3, seed=42); f.trees(12, 36, 40, 4, "ph_tree_conifer", step=2, seed=43)
    f.trees(0, 41, 56, 3, "ph_tree_conifer", step=3, seed=44); f.trees(0, 23, 12, 17, "ph_tree_conifer", step=3, seed=45)
    f.exit("W", 0, 6, "F03", "搦手口→高速北側の法面下→隧道", when="key_tunnel_fence")
    for pid, x, y, kd, lab in [("map_board", 6, 17, "board", "崩れた案内板"), ("bridge_marker", 12, 19, "item", "土橋の目印"), ("keep_stones", 27, 22, "item", "主郭の礎石"),
                                ("moat_item", 20, 33, "item", "空堀の底の落とし物"), ("hidden_exit", 28, 30, "item", "馬出しの隠し口")]:
        f.point(pid, x, y, kd, lab)
    f.note = "地形の高さは資料に無いので仮（空堀 3 m 下、土塁 3 m 上、主郭の台 1.2 m）。空堀の底へは南西の坂から下りる。"
    f.save(sun_evening=145)

# =============================================================== F16 薬師谷 32×48（refs/field/F16.png）。林道 0 → 崩れた石段 32 段 → 谷の底 4.8 m → 奥の台座 6.0 m。岩壁 9.6 m
if want("F16"):
    f = F("F16", "薬師谷", 32, 48, "forbidden_valley_temple", 5, "f16_yakushidani")
    f.bands = False
    f.edge_fill = [{"rect": [0, 0, 32, 48], "kind": "none"}]
    f.ground = {"walk": "grass", "narrow": "dirt", "open": "grass", "default": "rock"}
    f.twall = "rock"
    f.height(0, 0, 32, 48, 64)                             # 岩壁（北と東は 9.6 m）
    f.height(0, 0, 5, 48, 44)                              # 西の縁（カメラ側）は谷底 + 1.8 m の低い岩
    f.height(0, 32, 32, 16, 32)                            # 南は谷底と同じ高さの斜面（石段の脇）
    f.walk(16, 40, 6, 8, "dirt"); f.height(16, 40, 6, 8, 0)                    # 林道（S (18,47)）
    f.height(14, 40, 2, 8, 0); f.height(22, 40, 2, 8, 0)
    f.walk(17, 32, 4, 8, "stone_step"); f.stairs(17, 32, 4, 8, "y", 30, 2, wall="stone_wall")   # 崩れた石段
    f.ramp(16, 32, 1, 8, "y", 30, 2); f.trects.pop(); f.ramp(21, 32, 1, 8, "y", 30, 2); f.trects.pop()
    f.walk(5, 17, 23, 15, "grass"); f.height(5, 17, 23, 15, 32)                # 谷の底
    f.height(5, 15, 23, 2, 32)
    f.block(13, 19, 10, 7)
    f.b("temple_hall", 9, 1, "plaster", near=[17, 26], depth=7, id="yakushido", height_m=5.0, note="廃寺の薬師堂")
    f.narrow(16, 14, 3, 3, "dirt"); f.ramp(16, 14, 3, 3, "y", 38, 34)         # 堂の裏の通路（落石）
    f.narrow(14, 8, 5, 6, "dirt"); f.height(14, 8, 5, 6, 40)                   # 奥の台座の間
    f.narrow(17, 7, 1, 1, "dirt"); f.height(17, 7, 1, 1, 40)                   # 岩壁の裂け目
    f.prop("ph_rock", 17.5, 15.5, "S", pid="inner_gate"); f.prop("ph_rock", 18.5, 16.5, "S", pid="rock_b"); f.prop("ph_rock", 24.5, 30.5, "S", pid="rockfall")
    f.prop("obj_stone_marker", 23.5, 24.5, "S", pid="masks"); f.prop("obj_water_basin", 8.5, 27.5, "S", pid="spring"); f.prop("obj_stone_marker", 19.5, 27.5, "S", pid="salt_spot")
    f.prop("ph_stone_pillar", 18.5, 11.5, "S", pid="pedestal_e"); f.prop("ph_stone_pillar", 16.5, 13.5, "S", pid="pedestal_s"); f.prop("ph_stone_pillar", 14.5, 11.5, "S", pid="pedestal_w"); f.prop("ph_stone_pillar", 16.5, 10.5, "S", pid="pedestal_n")
    for x in range(5, 16, 2): f.prop("ph_tree_conifer", x + 0.5, 16.5, "E")
    for x in range(19, 28, 2): f.prop("ph_tree_conifer", x + 0.5, 16.5, "E")
    for x in range(5, 17, 2): f.prop("ph_tree_conifer", x + 0.5, 32.5, "E")
    for x in range(21, 28, 2): f.prop("ph_tree_conifer", x + 0.5, 32.5, "E")
    f.trees(14, 40, 2, 8, "ph_tree_conifer", step=2, seed=46); f.trees(22, 40, 2, 8, "ph_tree_conifer", step=2, seed=47)
    f.exit("S", 18, 47, "F14", "林道を下って朝和の里へ", when="flag_yakushi_open")
    for pid, x, y, kd, lab in [("zushi", 16, 25, "item", "薬師堂の厨子"), ("masks", 23, 24, "item", "積まれた面"), ("spring", 8, 27, "item", "湧水"), ("rockfall", 24, 30, "item", "落石の跡"),
                                ("salt_spot", 19, 27, "item", "堂の前の石"), ("inner_gate", 16, 15, "item", "堂の裏の落石")]:
        f.point(pid, x, y, kd, lab)
    for pid, x, y, lab in [("pedestal_e", 18, 11, "東の台座"), ("pedestal_s", 16, 13, "南の台座"), ("pedestal_w", 14, 11, "西の台座"), ("pedestal_n", 16, 10, "北の台座")]:
        f.point(pid, x, y, "item", lab, when="pedestals_appear")
    f.note = "岩壁は北・東 9.6 m、西の縁は谷底 + 1.8 m（カメラ側を低く）。谷の底 4.8 m、奥の間 6.0 m、石段 32 段（資料に高さの記載なし）。台座 4 点の出現条件（when）は物語側の名前で置き換える。"
    f.save(sun_evening=235)
