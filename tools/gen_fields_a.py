# -*- coding: utf-8 -*-
"""A 群 5 枚（F01, F06, F12, F13, F02）の歩行可能マスクと JSON を生成する（フェーズ 13 R-5）。
座標は refs/field/<ID>.png と docs/field/<ID>_spec.md（調べ物・出入口はそのまま）。道は 6 タイル以上に広げる。
規則（Q-1）: 道（walk）を置くと、近景側（西・南）に 2 タイル、遠景側（東・北）に 1 タイルの帯（128）が自動で付く。
帯の 1 列目は歩道、2 列目に生垣・ブロック塀・ガードレール。建物は両側に置く。階数・向きは地図と spec のまま（式は助言。隠れはフェードで解く）。
地面は市街地なので舗装（Q-2）。実行: python tools/gen_fields_a.py
"""
from fieldgen import F

# =============================================================== F01 国道281号 沿道商業地区 32×48（refs/field/F01.png）
f = F("F01", "国道281号 沿道商業地区", 32, 48, "roadside_commercial", 1, "f01_kokudo")
f.walk(10, 0, 9, 48)                                   # 国道 + 両側の歩道（x 10..18）。出入口 N (13,0) / S (13,47)
f.walk(1, 11, 9, 21, "asphalt")                        # 西の巨大駐車場（歩ける。x 9 で国道の歩道につながる）
f.walk(19, 8, 13, 6)                                   # コンビニ前の路地（→ F06 E (31,10)）
f.walk(20, 12, 12, 8, "asphalt")                       # 東の駐車場
f.walk(19, 33, 13, 6)                                  # 駐車場の裏口の路地（→ F05 E (31,34)）
f.open(19, 20, 13, 13, "lot_ground")                   # 空き地（土。金網で囲む）
f.bar("wire_fence", 19, 20, 13, 1); f.bar("wire_fence", 19, 32, 13, 1); f.bar("wire_fence", 19, 21, 1, 11)
f.bar("overpass", 9, 21, 11, 2)                        # 歩道橋（国道をまたぐ）
f.b("store", 8, 1, "concrete", near=[4, 10], id="supermarket", height_m=5.0, roof="flat", sign="red", depth=9, note="いわとマート")
f.b("store", 8, 1, "concrete", near=[8, 36], id="sushi", height_m=4.6, roof="flat", sign="blue", depth=8, note="回転寿司（正面は国道側）")
f.b("store", 6, 1, "concrete", near=[8, 44], id="drugstore", height_m=4.6, roof="flat", sign="yellow", depth=8, note="ドラッグストア（正面は国道側）")
f.b("store", 10, 1, "concrete", near=[24, 7], id="conbini", height_m=4.2, roof="flat", sign="white", depth=6, note="深夜のコンビニ")
f.b("store", 8, 1, "concrete", near=[25, 39], id="backstore", height_m=5.0, roof="flat", sign="red", depth=6, note="裏口側の店舗")
f.houses(10)
f.cars([(1, 15), (3, 15), (5, 15), (1, 20), (3, 20), (5, 20), (1, 25), (3, 25), (1, 29), (21, 14), (23, 14), (27, 17), (29, 17)])
f.prop("obj_vending_machine", 19.5, 9.5, "W", pid="vending_w"); f.prop("obj_vending_machine", 29.5, 9.5, "S", pid="vending_e")
f.prop("obj_bulletin_board", 19.5, 7.5, "S", pid="bulletin"); f.prop("obj_water_tank", 22.5, 9.5, "S", pid="trash")
f.prop("obj_bicycle_rack", 8.5, 14.5, "E", pid="cart1"); f.prop("obj_bicycle_rack", 8.5, 16.5, "E", pid="cart2"); f.prop("obj_traffic_cone", 8.5, 12.5, "E")
f.prop("obj_bus_stop_pole", 10.5, 18.5, "E"); f.prop("obj_bus_stop_pole", 18.5, 26.5, "W"); f.prop("obj_public_phone", 18.5, 30.5, "W")
for y in range(3, 46, 6): f.prop("obj_street_light_led", 10.5, y + 0.5, "E"); f.prop("obj_street_light_led", 18.5, y + 3.5, "W")
for y in range(1, 47, 8): f.prop("obj_guardrail", 11.5, y + 0.5, "E"); f.prop("obj_guardrail", 17.5, y + 4.5, "W")
f.exit("N", 13, 0, "F02", "国道の歩道をそのまま北へ"); f.exit("E", 31, 10, "F06", "ドラッグストア脇の路地→市民センター前")
f.exit("E", 31, 34, "F05", "駐車場の裏口→旧街道の商店街"); f.exit("S", 13, 47, "F12", "国道の歩道を南へ→木平団地")
for pid, x, y, kd, lab in [("store_door", 23, 8, "door", "コンビニ"), ("vending_w", 19, 9, "item", "自販機"), ("vending_e", 29, 9, "item", "自販機"), ("bulletin", 19, 7, "board", "店先の掲示板"),
                            ("receipt_box", 25, 9, "item", "レシート箱"), ("trash", 22, 9, "item", "ゴミ箱"), ("car_lot", 2, 21, "item", "駐車場の車"), ("cart", 8, 14, "item", "カート置き場"),
                            ("bridge_w", 10, 22, "board", "歩道橋の落書き"), ("super_door", 6, 10, "door", "スーパー"), ("sushi_door", 9, 38, "door", "回転寿司"), ("drug_door", 9, 45, "door", "ドラッグストア")]:
    f.point(pid, x, y, kd, lab)
f.point("mio_npc", 21, 10, "npc", "澪", when="mio_present")
f.save(sun_evening=235)

# =============================================================== F06 磐戸市民センター・交番前広場 40×32（refs/field/F06.png）
f = F("F06", "磐戸市民センター・交番前広場", 40, 32, "civic_plaza", 2, "f06_civic_center")
f.walk(8, 11, 27, 13, "tile")                          # 交番前広場（タイル舗装、x 8..34）
f.walk(0, 11, 8, 6)                                    # 西の路地（→ F01 W (0,13)）
f.walk(6, 0, 6, 11)                                    # 旧街道を北へ（→ F02 N (10,0)）
f.walk(24, 0, 6, 11)                                   # 法面の階段へ（→ F03 N (27,0)）
f.walk(4, 24, 6, 8); f.walk(28, 24, 6, 8)              # 南へ（→ F05 S (5,31)、→ F07 S (30,31)）
f.fill(20, 15, 1, 2, 0)                                # 時計塔の区画（広場の中、塞ぐ）
f.b("civic", 12, 2, "concrete", near=[18, 9], id="civic_center", height_m=7.0, roof="flat", depth=7, note="市民センター（図書室・遺失物箱）")
f.b("civic", 5, 1, "concrete", near=[31, 9], id="koban", height_m=3.6, roof="flat", depth=4, note="交番（無人）")
f.b("civic", 1, 1, "concrete", near=[20, 16], id="clock_tower", height_m=9.0, roof="flat", depth=2, note="広場の時計塔")
f.houses(30)
f.prop("obj_bulletin_board", 14.5, 12.5, "S", pid="bulletin_board"); f.prop("obj_signboard_pole", 8.5, 15.5, "E", pid="map_sign"); f.prop("obj_public_phone", 34.5, 12.5, "W", pid="phone_box")
for (x, y) in [(13.5, 12.5), (22.5, 12.5), (11.5, 20.5), (11.5, 22.5), (24.5, 20.5), (24.5, 22.5), (28.5, 16.5), (30.5, 12.5)]: f.prop("obj_potted_plant", x, y, "S")
for (x, y) in [(15.5, 20.5), (19.5, 21.5), (23.5, 20.5), (17.5, 17.5)]: f.prop("obj_bench", x, y, "S")
for (x, y) in [(10.5, 12.5), (26.5, 12.5), (10.5, 20.5), (26.5, 20.5), (33.5, 20.5)]: f.prop("obj_street_light_led", x, y, "S")
f.prop("obj_bicycle_rack", 30.5, 20.5, "W"); f.prop("obj_bicycle_rack", 30.5, 21.5, "W"); f.prop("obj_signboard_shutter", 28.5, 2.5, "S", pid="slope_notice_board"); f.prop("obj_vending_machine", 33.5, 15.5, "W")
f.exit("W", 0, 13, "F01", "路地→国道"); f.exit("N", 10, 0, "F02", "旧街道を北へ→住宅地"); f.exit("N", 27, 0, "F03", "法面の階段を上ってバスストップ")
f.exit("S", 5, 31, "F05", "旧街道を南へ→商店街"); f.exit("S", 30, 31, "F07", "寺町の路地→光明院")
for pid, x, y, kd, lab in [("library", 18, 10, "door", "図書室"), ("lost_and_found", 22, 10, "door", "遺失物箱"), ("police_log", 30, 10, "door", "交番"), ("bulletin", 14, 12, "board", "掲示板"),
                            ("map_sign", 8, 15, "board", "町の地図"), ("phone", 34, 12, "save", "公衆電話"), ("clock", 20, 16, "item", "時計塔"), ("slope_notice", 28, 2, "board", "法面階段の張り紙")]:
    f.point(pid, x, y, kd, lab)
f.save()

# =============================================================== F12 木平団地・支所前 40×32（refs/field/F12.png）
f = F("F12", "木平団地・支所前", 40, 32, "housing_estate", 1, "f12_kihira")
f.walk(6, 0, 6, 19)                                    # 国道の歩道から（→ F01 N (8,0)）
f.walk(23, 0, 6, 19)                                   # 旧街道から（→ F05 N (25,0)）
f.walk(0, 19, 40, 6)                                   # 東西の道
f.walk(28, 12, 12, 6)                                  # 西門へ（→ F11 E (39,14)）
f.walk(28, 25, 6, 7)                                   # 南へ（→ F13 S (30,31)）
f.walk(12, 0, 11, 19, "lot_ground")                    # 団地の敷地（歩ける）。A 棟・B 棟の区画だけ塞ぐ
f.fill(12, 2, 10, 4, 0); f.fill(12, 9, 10, 4, 0)
f.walk(0, 25, 28, 7, "lot_ground")                     # 南の敷地。C 棟・D 棟
f.fill(3, 25, 10, 4, 0); f.fill(17, 25, 10, 4, 0)
f.walk(29, 0, 11, 12, "lot_ground"); f.fill(29, 1, 10, 8, 0)   # 支所とその周り（受付 (32,7) は入口の縁）
f.walk(1, 0, 5, 10, "lot_ground"); f.fill(2, 2, 3, 3, 0)       # 給水塔
f.walk(1, 10, 6, 9, "lot_ground")                      # 小さな公園（象の滑り台）
f.open(34, 25, 5, 6, "asphalt"); f.cars([(34, 25), (36, 25), (34, 28), (36, 28)])   # 駐車場
f.b("apartment", 10, 4, "concrete", near=[16, 5], id="danchi_a", height_m=11.5, roof="flat", depth=4, note="A 棟（4 階）")
f.b("apartment", 10, 4, "concrete", near=[16, 12], id="danchi_b", height_m=11.5, roof="flat", depth=4, note="B 棟（4 階）")
f.b("apartment", 10, 4, "concrete", near=[8, 28], id="danchi_c", height_m=11.5, roof="flat", depth=4, note="C 棟（4 階）")
f.b("apartment", 10, 4, "concrete", near=[21, 28], id="danchi_d", height_m=11.5, roof="flat", depth=4, note="D 棟（4 階）")
f.b("civic", 10, 2, "concrete", near=[33, 8], id="shisho", height_m=6.8, roof="flat", depth=8, note="市役所支所")
f.b("civic", 3, 3, "concrete", near=[3, 4], id="water_tower", height_m=9.0, roof="flat", depth=3, note="給水塔（仮）")
f.houses(12)
f.prop("obj_mailbox", 4.5, 28.5, "N", pid="post"); f.prop("obj_bulletin_board", 12.5, 17.5, "S", pid="estate_board")
f.prop("obj_bicycle_rack", 19.5, 29.5, "N", pid="bike1"); f.prop("obj_bicycle_rack", 21.5, 29.5, "N", pid="bike2"); f.prop("obj_bench", 3.5, 12.5, "S"); f.prop("obj_bench", 4.5, 16.5, "S")
for (x, y) in [(10.5, 8.5), (10.5, 15.5), (19.5, 8.5), (19.5, 15.5), (26.5, 20.5), (30.5, 22.5), (13.5, 26.5)]: f.prop("obj_potted_plant", x, y, "S")
for (x, y) in [(7.5, 3.5), (26.5, 13.5), (30.5, 5.5), (12.5, 20.5), (24.5, 20.5), (35.5, 20.5)]: f.prop("obj_street_light_led", x, y, "S")
f.exit("N", 8, 0, "F01", "国道の歩道"); f.exit("N", 25, 0, "F05", "旧街道を北へ→商店街"); f.exit("E", 39, 14, "F11", "西門→小学校"); f.exit("S", 30, 31, "F13", "旧街道を南へ→ニュータウン")
for pid, x, y, kd, lab in [("home_door", 8, 27, "door", "自宅（C 棟 3 階）"), ("stairwell_c_notice", 9, 27, "board", "C 棟 階段室の掲示"), ("stairwell_a", 16, 5, "door", "A 棟 階段室"), ("stairwell_b", 16, 12, "door", "B 棟 階段室"),
                            ("stairwell_d", 21, 27, "door", "D 棟 階段室"), ("mailbox", 4, 28, "item", "集合ポスト"), ("office_desk", 32, 7, "door", "支所の受付"), ("office_board", 36, 9, "board", "支所の掲示板"),
                            ("slide_inside", 3, 13, "item", "象の滑り台"), ("tower_hatch", 3, 5, "door", "給水塔の点検扉"), ("estate_board", 12, 17, "board", "団地の案内板"), ("bike_shed", 19, 29, "item", "駐輪場")]:
    f.point(pid, x, y, kd, lab)
f.save()

# =============================================================== F13 倉ノ前ニュータウン 48×32（refs/field/F13.png）。道の間隔は地図どおり
f = F("F13", "倉ノ前ニュータウン", 48, 32, "newtown_residential", 1, "f13_newtown")
f.walk(9, 0, 6, 32)                                    # 南北の道（→ F12 N (12,0)）
f.walk(0, 7, 48, 6)                                    # 東西の道（北、地図 y 8..9 を 6 幅に）
f.walk(34, 0, 6, 13)                                   # → F11 N (36,0)
f.walk(36, 12, 12, 4)                                  # 堤防道路へ（→ F10 E (47,14)）
f.walk(4, 19, 44, 6)                                   # 東西の道（南、地図 y 20..21 を 6 幅に）
f.walk(4, 25, 6, 7)                                    # → F15 S (6,31)
f.narrow(15, 26, 17, 2)                                # 袋小路（行き止まり）。地図どおり 2 幅。調べ物あり
f.open(38, 24, 9, 7, "water"); f.bar("wire_fence", 38, 24, 9, 1); f.bar("wire_fence", 38, 25, 1, 6)   # 調整池と柵
f.b("house", 4, 2, "namako", near=[26, 12], id="odd_house", note="瓦屋根の家（一軒だけ違う）")
f.b("house", 4, 2, "weatherboard", near=[32, 27], id="deadend_house", note="袋小路の奥の家")
f.houses(56, kinds=("house", "house", "house", "house"), floors=(2, 2, 2, 2), widths=(4, 4, 4, 4))
f.prop("obj_stone_marker", 9.5, 10.5, "E", pid="monument"); f.prop("obj_block_wall", 14.5, 10.5, "S", pid="trash_station"); f.prop("obj_signboard_pole", 41.5, 17.5, "S", pid="sale_sign")
for (x, y) in [(12.5, 2.5), (12.5, 16.5), (12.5, 29.5), (36.5, 4.5), (20.5, 8.5), (30.5, 8.5), (40.5, 8.5), (20.5, 20.5), (30.5, 20.5), (40.5, 20.5)]: f.prop("obj_street_light_led", x, y, "S")
f.exit("N", 12, 0, "F12", "旧街道を北へ→団地"); f.exit("N", 36, 0, "F11", "南門→小学校"); f.exit("E", 47, 14, "F10", "堤防道路→運動広場"); f.exit("S", 6, 31, "F15", "旧街道の末端→渡し場跡・河畔")
for pid, x, y, kd, lab in [("monument", 9, 10, "board", "区画整理記念碑"), ("nameplate_a", 3, 6, "board", "表札"), ("nameplate_b", 16, 6, "board", "表札"), ("nameplate_c", 21, 6, "board", "表札"),
                            ("odd_house", 26, 11, "door", "瓦屋根の家"), ("sale_sign", 41, 17, "board", "売地の看板"), ("pond_fence", 38, 25, "item", "調整池の柵"), ("deadend_window", 31, 26, "item", "袋小路の奥の家"),
                            ("trash_station", 14, 10, "item", "ゴミステーション")]:
    f.point(pid, x, y, kd, lab)
f.point("extra_nameplate", 30, 28, "board", "表札（空欄）", when="extra_house")
f.save()

# =============================================================== F02 於御所住宅地 48×32（refs/field/F02.png）。道の間隔は地図どおり
f = F("F02", "於御所住宅地", 48, 32, "suburban_residential", 2, "f02_ogoso")
f.walk(8, 0, 6, 32)                                    # 南北の道（→ F01 S (10,31)）
f.walk(0, 13, 48, 6)                                   # 東西の道（中央、地図 y 14..16 を 6 幅に）
f.walk(34, 0, 6, 32)                                   # 南北の道（→ F06 S (36,31)）
f.walk(40, 18, 8, 6)                                   # 法面沿いの生活道路（→ F03 E (47,20)）
f.walk(0, 23, 48, 6)                                   # 東西の道（南、地図 y 24..26 を 6 幅に）
f.walk(20, 3, 3, 10, "alley")                          # 蓮の家の脇の細道（歩ける）
f.walk(13, 19, 9, 4, "lot_ground")                     # 児童公園（歩ける。周りの生垣は帯に自動で付く）
f.open(38, 0, 10, 4, "gravel"); f.bar("wire_fence", 38, 3, 10, 1)   # 高速の法面（北東角）
f.b("house", 5, 2, "weatherboard", near=[17, 11], id="ren_house", note="蓮の家")
f.b("house", 5, 2, "mortar", near=[5, 11], id="nameplate_house", note="表札の名前が消えている家")
f.b("temple_hall", 4, 1, "plaster", near=[42, 11], id="hermitage", height_m=3.6, depth=4, note="浄土宗の小さな庵")
f.houses(56, kinds=("house", "house", "house", "shop_wood", "house", "house"), floors=(2, 2, 2, 2, 2, 2), widths=(4, 4, 3, 4, 4, 4))
f.prop("obj_laundry_pole", 22.5, 7.5, "S", pid="laundry"); f.prop("obj_mailbox", 16.5, 12.5, "S", pid="mailbox_ren"); f.prop("obj_mailbox", 3.5, 12.5, "S", pid="mailbox_a")
f.prop("obj_bench", 15.5, 20.5, "S", pid="swing"); f.prop("obj_water_tank", 24.5, 19.5, "S", pid="trash_net"); f.prop("obj_bulletin_board", 12.5, 19.5, "S", pid="kairanban")
for (x, y) in [(7.5, 5.5), (7.5, 20.5), (33.5, 5.5), (33.5, 20.5), (20.5, 13.5), (28.5, 13.5), (44.5, 13.5), (20.5, 23.5), (28.5, 23.5)]: f.prop("obj_street_light_led", x, y, "S")
f.exit("S", 10, 31, "F01", "国道へ下る"); f.exit("S", 36, 31, "F06", "旧街道を南へ→市民センター"); f.exit("E", 47, 20, "F03", "法面沿いの生活道路→バスストップ")
for pid, x, y, kd, lab in [("ren_door", 17, 13, "door", "蓮の家"), ("ren_window", 19, 13, "item", "蓮の部屋の窓"), ("laundry", 22, 7, "item", "物干し"), ("mailbox_ren", 16, 13, "item", "郵便受け"),
                            ("nameplate", 5, 13, "board", "表札"), ("mailbox_a", 3, 13, "item", "郵便受け"), ("hermitage", 42, 12, "door", "庵"), ("park_swing", 15, 20, "item", "ブランコ"),
                            ("trash_net", 24, 17, "item", "ゴミ集積所"), ("kairanban", 12, 17, "board", "回覧板"), ("slope", 39, 3, "item", "高速の法面")]:
    f.point(pid, x, y, kd, lab)
f.save()
