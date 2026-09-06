class_name AoBaker
extends RefCounted
## 街区スケールの AO ベイク（ART_SPEC 第 6 節）。lookdev.gd の実装を独立させたもの。
## 半球のコサイン重みサンプル（Hammersley 列、決定的）を AABB 群と地面に当て、空の可視率を焼く。
## 面ごとに UV2 0..1 のテクスチャを作り、StandardMaterial3D の ao_texture（ao_on_uv2、ao_light_affect 0）に入れる。

var occluders: Array[AABB] = []
var ray_len := 18.0
var rays := 24
var texel_per_m := 2.0
var upscale := 4
var power := 1.0
var _dirs: Array[Vector3] = []


func _init(p_occluders: Array[AABB] = [], p_ray_len := 18.0, p_rays := 24) -> void:
	occluders = p_occluders
	ray_len = p_ray_len
	rays = p_rays
	_dirs = _hemi_dirs(rays)


static func _hemi_dirs(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var u := (float(i) + 0.5) / float(n)
		var v := 0.0
		var f := 0.5
		var k := i
		while k > 0:
			if k & 1:
				v += f
			f *= 0.5
			k >>= 1
		var r := sqrt(u)
		var th := TAU * v
		out.append(Vector3(r * cos(th), r * sin(th), sqrt(maxf(1.0 - u, 0.0))))
	return out


## 点 p・法線 n の空の可視率（0..1）。
func sky_visibility(p: Vector3, n: Vector3, tangent: Vector3, bitangent: Vector3, skip_ground: bool) -> float:
	var open := 0
	for dl in _dirs:
		var d := (tangent * dl.x + bitangent * dl.y + n * dl.z).normalized()
		var blocked := false
		if not skip_ground and d.y < -1e-4:
			if -p.y / d.y <= ray_len:
				blocked = true
		if not blocked:
			for bb in occluders:
				if bb.grow(0.01).has_point(p):
					continue   # 自分を囲む AABB（切妻屋根の外接箱など）は無視する
				var hit = bb.intersects_ray(p, d)
				if hit != null and (hit as Vector3).distance_to(p) <= ray_len:
					blocked = true
					break
		if not blocked:
			open += 1
	return float(open) / float(_dirs.size())


## 四角形の面（origin から u_axis, v_axis に張る）の AO を焼く。
func bake_face(origin: Vector3, u_axis: Vector3, v_axis: Vector3, normal: Vector3, skip_ground: bool = false) -> Image:
	var nu := maxi(int(ceil(u_axis.length() * texel_per_m)), 2)
	var nv := maxi(int(ceil(v_axis.length() * texel_per_m)), 2)
	var img := Image.create(nu, nv, false, Image.FORMAT_RF)
	var tangent := u_axis.normalized()
	var bitangent := v_axis.normalized()
	for iy in nv:
		for ix in nu:
			var p := origin + u_axis * ((float(ix) + 0.5) / nu) + v_axis * ((float(iy) + 0.5) / nv) + normal * 0.02
			var a := sky_visibility(p, normal, _dirs_tangent(tangent, normal), _dirs_bitangent(bitangent, normal), skip_ground)
			img.set_pixel(ix, iy, Color(a, a, a))
	return img


func _dirs_tangent(t: Vector3, _n: Vector3) -> Vector3:
	return t


func _dirs_bitangent(b: Vector3, _n: Vector3) -> Vector3:
	return b


## ベイク結果を表示用テクスチャに（power を掛け、バイリニアで拡大、ミップマップ付き）。
func to_texture(img: Image) -> ImageTexture:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := pow(img.get_pixel(x, y).r, power)
			out.set_pixel(x, y, Color(a, a, a, 1.0))
	out.resize(out.get_width() * upscale, out.get_height() * upscale, Image.INTERPOLATE_BILINEAR)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


## 材質に AO を付ける（複製して返す）。
static func apply_to(mat: StandardMaterial3D, tex: ImageTexture) -> StandardMaterial3D:
	var m := mat.duplicate() as StandardMaterial3D
	m.ao_enabled = true
	m.ao_texture = tex
	m.ao_on_uv2 = true
	m.ao_light_affect = 0.0
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m
