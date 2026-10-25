extends SceneTree
## Art direction study (exploration only, not wired into the game): renders the same fight and
## model lineup under alternative stylized looks by swapping every lit material for a style
## shader at capture time and adding a full-screen finishing pass.
## godot -s tools/shot_styles.gd -- OUT_DIR STYLE [scene|lineup]
## STYLE: current, facet, ink, mini, paint, noir, lofi. Needs a real renderer (Forward+).

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")
const CHAR_SHADER := preload("res://view/character.gdshader")

const ROWS := [
	"..................",
	"...####.......^^^^",
	"...#..........^^^^",
	"...#....=.....^^%^",
	"................s.",
	".......!..........",
	".....=...==.......",
	"..................",
	"............H.....",
	"..................",
	"..................",
	"..................",
]

var _out := ""
var _style := "current"
var _what := "scene"
var _view: MissionView
var _lineup: Node3D
var _cam: Camera3D
var _frames := 0
var _soldiers: Array = []
var _enemies: Array = []
var _char_shaders := {}
var _env_shader: Shader
var _mat_cache := {}
var _shape := ""

## Body proportion presets: bone name prefix -> uniform scale. A bone's scale carries down to its
## children, so "head" also resizes helmets, masks and growths. Shapes are mock-ups of what a
## rebuilt model would be proportioned like; the mesh itself is stretched, not re-modelled.
const SHAPES := {
	"chunky": {"Head": 1.3, "neck_01": 0.8, "hand_": 1.55, "foot_": 1.35, "thigh_": 0.8, "calf_": 0.9, "spine_01": 0.95,
		"upperarm_": 1.1, "clavicle_": 1.05},
	"squat": {"Head": 1.5, "neck_01": 0.7, "hand_": 1.4, "foot_": 1.3, "thigh_": 0.68, "calf_": 0.78, "spine_01": 0.88,
		"upperarm_": 0.95, "lowerarm_": 0.9},
	"heroic": {"Head": 0.82, "neck_01": 1.0, "thigh_": 1.14, "calf_": 1.12, "spine_01": 0.92, "spine_02": 1.0,
		"clavicle_": 1.18, "upperarm_": 1.05, "hand_": 0.92},
	"hulk": {"Head": 0.75, "neck_01": 0.8, "spine_01": 1.12, "spine_02": 1.15, "clavicle_": 1.3, "upperarm_": 1.28,
		"lowerarm_": 1.15, "hand_": 1.3, "thigh_": 1.02, "calf_": 0.98, "foot_": 1.2},
	"gaunt": {"Head": 0.85, "neck_01": 1.2, "spine_01": 1.05, "spine_02": 1.05, "clavicle_": 0.9, "upperarm_": 1.28,
		"lowerarm_": 1.32, "hand_": 1.45, "thigh_": 1.08, "calf_": 1.1, "foot_": 1.1},
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	_style = args[1]
	_what = args[2] if args.size() > 2 else "scene"
	_shape = args[3] if args.size() > 3 else ""
	if _shape != "":
		RenderingServer.frame_pre_draw.connect(_shape_pass)
	root.size = Vector2i(1600, 900)
	if _what == "lineup":
		_lineup = preload("res://view/lineup.gd").new()
		root.add_child(_lineup)
		return
	var s := GameState.new()
	s.rng.seed = 7
	s.grid = Grid.from_rows(PackedStringArray(ROWS))
	s.grid.biome = "port"
	s.players.assign([0, 1])
	Vision.disable(s)
	for k in [["trooper", Vector2i(9, 7), 0], ["medic", Vector2i(5, 7), 1], ["marksman", Vector2i(15, 2), 0],
			["breacher", Vector2i(11, 8), 1]]:
		var u := s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = k[2]
		_soldiers.append(u)
	for k in [["runner", Vector2i(6, 3)], ["runner", Vector2i(10, 4)], ["brute", Vector2i(9, 2)]]:
		_enemies.append(s.add_unit(EnemyRoster.make(k[0]), k[1]))
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.state = s
	_view = MAIN.instantiate()
	_view.auto_start = false
	_view.session = l
	root.add_child(_view)
	_view.start(s, true)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_setup()
	if _frames == 30:
		_pose()
	if _frames == 50:
		_apply_style()
	if _frames == 70:
		_shots()
	return false


func _shots() -> void:
	if _what == "lineup":
		await _save("lineup")
		quit()
		return
	_place(Vector3(15.5, 12.5, 15.0), Vector3(8.6, 0.0, 4.6), 38.0)
	for i in 12:
		await process_frame
	await _save("tactical")
	_place(Vector3(9.9, 2.05, 10.6), Vector3(8.4, 1.05, 3.4), 40.0)
	for i in 12:
		await process_frame
	await _save("close")
	quit()


func _setup() -> void:
	if _what == "lineup":
		for v in _lineup.views:
			v.set_yaw(deg_to_rad(200.0))
		_cam = _lineup._cam
		_cam.position = Vector3(0, 1.35, 5.4)
		_cam.look_at(Vector3(0, 0.95, 0))
		for we in _lineup.find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.ambient_light_energy *= 3.0
			(we as WorldEnvironment).environment.tonemap_exposure = 1.6
		return
	for we in _view.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.ambient_light_energy *= 6.0
		(we as WorldEnvironment).environment.tonemap_exposure = 1.8
	if _view.fog != null:
		_view.fog.visible = false
	for c in _view.find_children("*", "CanvasLayer", true, false):
		if c.name != "PostFx":
			(c as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_view.add_child(_cam)
	_cam.current = true
	for u in _soldiers + _enemies:
		var uv = _view.view_for(u.id)
		if uv != null:
			uv.set_overlays_visible(false)


func _pose() -> void:
	if _what == "lineup":
		for v in _lineup.views:
			if v.is_soldier:
				v.aim_now(1.0)
		return
	var brute := _view.view_for(_enemies[2].id)
	for u in _soldiers:
		var uv = _view.view_for(u.id)
		uv.face_towards(brute.position if u.kind != "medic" else _view.view_for(_enemies[0].id).position, true)
		uv.aim_now(1.0)
	for u in _enemies:
		var uv = _view.view_for(u.id)
		uv.face_towards(_view.view_for(_soldiers[0].id).position, true)
	_view.view_for(_enemies[1].id).set_lunge(0.55)


func _place(pos: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = pos
	_cam.fov = fov
	_cam.look_at(at)


func _save(tag: String) -> void:
	if _view != null:
		_view.board.clear_overlays()
		await process_frame
		await process_frame
	var path := "%s/%s-%s.png" % [_out, _style if _shape == "" else _shape, tag]
	root.get_texture().get_image().save_png(path)
	print("[shot_styles] ", path)


# --- style swap ---------------------------------------------------------------------------

func _apply_style() -> void:
	if _style == "current":
		return
	var top: Node = _lineup if _lineup != null else _view
	for n in top.find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D:
			_restyle_mesh(n as MeshInstance3D)
	_tune_lights(top)
	_add_post()
	if _style == "mini":
		_add_bases(top)


func _restyle_mesh(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	if mi.material_override != null:
		var r := _convert(mi.material_override)
		if r != null:
			mi.material_override = r
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m == null:
			continue
		var r := _convert(m)
		if r != null:
			mi.set_surface_override_material(i, r)


func _convert(m: Material) -> Material:
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		if sm.shader == CHAR_SHADER or sm.has_meta("styled_char"):
			sm.shader = _char_shader()
			sm.set_meta("styled_char", true)
			var g: float = sm.get_shader_parameter("grime") if sm.get_shader_parameter("grime") != null else 0.5
			sm.set_shader_parameter("grime", g * float(GRIME[_style]))
		return null
	if not (m is BaseMaterial3D):
		return null
	var b := m as BaseMaterial3D
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return null
	if _mat_cache.has(b):
		return _mat_cache[b]
	var e := ShaderMaterial.new()
	e.shader = _env()
	e.set_shader_parameter("albedo", b.albedo_color)
	e.set_shader_parameter("roughness", b.roughness)
	e.set_shader_parameter("metallic", b.metallic)
	if b.albedo_texture != null:
		e.set_shader_parameter("tex", b.albedo_texture)
		e.set_shader_parameter("has_tex", true)
		e.set_shader_parameter("triplanar", b.uv1_triplanar)
		e.set_shader_parameter("uv_scale", b.uv1_scale)
	if b.emission_enabled:
		e.set_shader_parameter("emission_color", b.emission)
		e.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
	_mat_cache[b] = e
	return e


func _char_shader() -> Shader:
	if _char_shaders.has(_style):
		return _char_shaders[_style]
	var code := CHAR_SHADER.code
	code = code.replace("shader_type spatial;", "shader_type spatial;\n" + _common())
	code = code.replace("vec3 tex = texture(albedo_tex, UV).rgb;", "vec3 tex = textureLod(albedo_tex, UV, TEX_LOD).rgb;")
	code = code.replace("texture(normal_tex, UV).rgb, bare);", "texture(normal_tex, UV).rgb, bare * NORMAL_MAP_ON);")
	code = code.replace("\tALBEDO = col;", "\tcol = style_albedo(col, p);\n\tSTYLE_NORMAL;\n\tALBEDO = col;\n\tSTYLE_FRAG;")
	code = code.replace("\theight = (MODEL_MATRIX", "\tSTYLE_VERTEX;\n\theight = (MODEL_MATRIX")
	code += "\n" + LIGHT[_style]
	var sh := Shader.new()
	sh.code = code
	_char_shaders[_style] = sh
	return sh


func _env() -> Shader:
	if _env_shader == null:
		_env_shader = Shader.new()
		_env_shader.code = "shader_type spatial;\n" + _common() + ENV_BODY + "\n" + LIGHT[_style]
	return _env_shader


func _common() -> String:
	return DEFINES[_style] + "\n" + HELPERS


## Light changes per style (the mini look wants a brighter, warmer table light; noir wants
## the fill gone so shadows fall to ink).
func _tune_lights(top: Node) -> void:
	for we in top.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		match _style:
			"noir":
				env.ambient_light_energy *= 0.25
				env.ambient_light_color = Color("1a2440")
				env.ssil_enabled = false
				env.volumetric_fog_enabled = false
				env.fog_density *= 0.5
				env.adjustment_saturation = 0.9
				env.adjustment_contrast = 1.25
			"mini":
				env.ambient_light_energy *= 1.5
				env.ambient_light_color = Color("4a5058")
				env.volumetric_fog_enabled = false
				env.fog_density *= 0.3
				env.adjustment_saturation = 1.15
			"facet":
				env.adjustment_saturation = 1.0
				env.adjustment_brightness = 1.1
				env.volumetric_fog_density *= 0.6
			"ink":
				env.adjustment_saturation = 1.15
				env.volumetric_fog_density *= 0.5
				env.ssao_intensity = 1.0
			"paint":
				env.adjustment_saturation = 1.05
				env.adjustment_brightness = 1.2
				env.tonemap_exposure *= 1.15
			"lofi":
				env.glow_intensity *= 0.6
				env.tonemap_exposure *= 1.3
				env.adjustment_saturation = 0.9
	for l in top.find_children("*", "DirectionalLight3D", true, false):
		var dl := l as DirectionalLight3D
		if _style == "mini" and dl.shadow_enabled:
			dl.light_color = Color("ffe2b8")
			dl.light_energy *= 2.4
		if _style == "noir" and dl.shadow_enabled:
			dl.light_energy *= 2.0
			dl.light_color = Color("dfe6ee")


## Round, bevelled bases under every unit for the tabletop look.
func _add_bases(top: Node) -> void:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color("15171a")
	base_mat.roughness = 0.35
	var flock := StandardMaterial3D.new()
	flock.albedo_color = Color("4a4434")
	flock.roughness = 1.0
	for uv in top.find_children("*", "Node3D", true, false):
		if not uv.has_method("aim_now"):
			continue
		var big := 1.3 if uv.get("kind") == "brute" else 1.0
		var rim := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.36 * big
		cm.bottom_radius = 0.4 * big
		cm.height = 0.07
		rim.mesh = cm
		rim.material_override = base_mat
		rim.position.y = 0.035
		uv.add_child(rim)
		var top_m := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.34 * big
		tm.bottom_radius = 0.34 * big
		tm.height = 0.01
		top_m.mesh = tm
		top_m.material_override = flock
		top_m.position.y = 0.072
		uv.add_child(top_m)


func _add_post() -> void:
	if not POST.has(_style):
		return
	# depth / normal reads need the non-MSAA path; FXAA smooths the ink instead
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	q.mesh = qm
	q.extra_cull_margin = 16384.0
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = POST_HEAD + POST[_style]
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 100
	q.material_override = m
	_cam.add_child(q)


# --- shader source ------------------------------------------------------------------------

const GRIME := {"facet": 0.15, "ink": 0.3, "mini": 0.35, "paint": 0.8, "noir": 0.25, "lofi": 1.0}

## Per-style switches, used by both the character and the environment shaders.
const DEFINES := {
	"facet": "#define TEX_LOD 7.0\n#define NORMAL_MAP_ON 0.0\n#define STYLE_FACET\n#define STYLE_VERTEX\n#define STYLE_FRAG\n#define STYLE_NORMAL NORMAL = st_facet(VERTEX, VIEW)",
	"ink": "#define TEX_LOD 4.0\n#define NORMAL_MAP_ON 0.4\n#define STYLE_INK\n#define STYLE_VERTEX\n#define STYLE_FRAG\n#define STYLE_NORMAL",
	"mini": "#define TEX_LOD 2.0\n#define NORMAL_MAP_ON 1.0\n#define STYLE_MINI\n#define STYLE_VERTEX\n#define STYLE_FRAG ROUGHNESS = 0.55\n#define STYLE_NORMAL",
	"paint": "#define TEX_LOD 3.0\n#define NORMAL_MAP_ON 0.5\n#define STYLE_PAINT\n#define STYLE_VERTEX\n#define STYLE_FRAG\n#define STYLE_NORMAL",
	"noir": "#define TEX_LOD 5.0\n#define NORMAL_MAP_ON 0.2\n#define STYLE_NOIR\n#define STYLE_VERTEX\n#define STYLE_FRAG\n#define STYLE_NORMAL",
	"lofi": "#define TEX_LOD 1.0\n#define NORMAL_MAP_ON 0.0\n#define STYLE_LOFI\n#define STYLE_VERTEX POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0); POSITION.xy = floor(POSITION.xy / POSITION.w * vec2(240.0, 135.0)) / vec2(240.0, 135.0) * POSITION.w\n#define STYLE_FRAG\n#define STYLE_NORMAL",
}

const HELPERS := """
float st_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float st_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(st_hash(i), st_hash(i + vec3(1, 0, 0)), f.x),
				mix(st_hash(i + vec3(0, 1, 0)), st_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(st_hash(i + vec3(0, 0, 1)), st_hash(i + vec3(1, 0, 1)), f.x),
				mix(st_hash(i + vec3(0, 1, 1)), st_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
vec3 st_sat(vec3 c, float s) {
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	return max(mix(vec3(l), c, s), vec3(0.0));
}
vec3 st_facet(vec3 v, vec3 view) {
	vec3 n = normalize(cross(dFdx(v), dFdy(v)));
	return dot(n, view) < 0.0 ? -n : n;
}
vec3 style_albedo(vec3 c, vec3 p) {
#ifdef STYLE_FACET
	c = st_sat(c, 1.1) * 1.08;
#endif
#ifdef STYLE_INK
	c = st_sat(c, 1.15) * 1.1;
#endif
#ifdef STYLE_MINI
	c = st_sat(c, 1.3) * 1.15;
#endif
#ifdef STYLE_PAINT
	// broad strokes: stretched noise varies value and nudges hue warm/cool
	float s1 = st_noise(p * vec3(3.0, 14.0, 3.0));
	float s2 = st_noise(p * vec3(16.0, 4.0, 16.0) + 5.0);
	c *= 0.82 + 0.36 * s1;
	c = mix(c, c * vec3(1.08, 0.98, 0.86), s2 * 0.5);
	c = st_sat(c, 1.15);
#endif
#ifdef STYLE_NOIR
	c = st_sat(c, 0.75) * 1.05 + 0.02;
#endif
	return c;
}
"""

const LIGHT := {
	"facet": """
void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += (nl * 1.1 + 0.15 * step(0.0, dot(NORMAL, LIGHT))) * ATTENUATION * LIGHT_COLOR / PI;
}
""",
	"ink": """
void light() {
	float nl = dot(NORMAL, LIGHT) * ATTENUATION;
	float band = smoothstep(0.02, 0.06, nl) * 0.55 + smoothstep(0.45, 0.5, nl) * 0.45;
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI * 1.3;
	vec3 h = normalize(LIGHT + VIEW);
	float sp = smoothstep(0.975, 0.985, dot(NORMAL, h)) * step(0.3, ATTENUATION) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += sp * LIGHT_COLOR / PI * 0.4;
}
""",
	"mini": """
void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += nl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 40.0) * ATTENUATION * LIGHT_COLOR / PI * 0.35;
}
""",
	"paint": """
void light() {
	float w = clamp((dot(NORMAL, LIGHT) + 0.45) / 1.45, 0.0, 1.0);
	w = smoothstep(0.0, 1.0, w);
	vec3 warm = LIGHT_COLOR * vec3(1.08, 0.98, 0.86);
	DIFFUSE_LIGHT += w * ATTENUATION * warm / PI;
	DIFFUSE_LIGHT += (1.0 - w) * ATTENUATION * LIGHT_COLOR * vec3(0.10, 0.08, 0.22) / PI;
}
""",
	"noir": """
void light() {
	float nl = dot(NORMAL, LIGHT) * ATTENUATION;
	DIFFUSE_LIGHT += step(0.12, nl) * min(LIGHT_COLOR / PI, vec3(0.55)) * 1.2;
}
""",
	"lofi": """
void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += nl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 24.0) * ATTENUATION * LIGHT_COLOR / PI * 0.25 * (1.0 - ROUGHNESS);
}
""",
}

const ENV_BODY := """
uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform bool triplanar = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = albedo;
	if (has_tex) {
		vec3 t;
		if (triplanar) {
			vec3 bw = pow(abs(wnorm), vec3(4.0));
			bw /= bw.x + bw.y + bw.z;
			vec3 q = wpos * uv_scale;
			t = textureLod(tex, q.zy, TEX_LOD).rgb * bw.x + textureLod(tex, q.xz, TEX_LOD).rgb * bw.y
				+ textureLod(tex, q.xy, TEX_LOD).rgb * bw.z;
		} else {
			t = textureLod(tex, UV * uv_scale.xy, TEX_LOD).rgb;
		}
		col *= t;
	}
	col = style_albedo(col, wpos * 0.6);
	STYLE_NORMAL;
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission_color * emission_energy;
	STYLE_FRAG;
}
"""

const POST_HEAD := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 nrm(vec2 uv) {
	return normalize(texture(nr_tex, uv).xyz * 2.0 - 1.0);
}

// 0..1 ink line where depth or normals jump, `w` pixels wide
float edges(vec2 uv, vec2 px, float w, mat4 inv_proj, float dk, float nk) {
	float d = lin_depth(uv, inv_proj);
	vec3 n = nrm(uv);
	float e = 0.0;
	vec2 o[4] = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1));
	for (int i = 0; i < 4; i++) {
		vec2 u2 = uv + o[i] * px * w;
		float d2 = lin_depth(u2, inv_proj);
		vec3 n2 = nrm(u2);
		e = max(e, smoothstep(dk, dk * 2.0, (d2 - d) / d));
		e = max(e, smoothstep(nk, nk + 0.15, 1.0 - dot(n, n2)) * step(d, 60.0));
	}
	return e;
}

float phash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
"""

const POST := {
	"ink": """
void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float e = edges(SCREEN_UV, px, 2.0, INV_PROJECTION_MATRIX, 0.035, 0.35);
	// hatching in the shadows
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	float hatch = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / 6.0)) * (1.0 - smoothstep(0.03, 0.09, l));
	c *= 1.0 - hatch * 0.55;
	c = mix(c, vec3(0.02, 0.02, 0.03), e * 0.92);
	ALBEDO = c;
}
""",
	"noir": """
void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float e = edges(SCREEN_UV, px, 2.2, INV_PROJECTION_MATRIX, 0.03, 0.3);
	float grain = phash(floor(FRAGCOORD.xy / 2.0)) - 0.5;
	c += grain * 0.025;
	c = mix(c, vec3(0.0, 0.0, 0.01), e);
	ALBEDO = c;
}
""",
	"mini": """
void fragment() {
	// tilt-shift: a sharp band through the middle, soft lens blur above and below
	float b = smoothstep(0.12, 0.42, abs(SCREEN_UV.y - 0.55));
	vec3 c = textureLod(screen_tex, SCREEN_UV, b * 3.2).rgb;
	ALBEDO = c;
}
""",
	"paint": """
void fragment() {
	// Kuwahara: each pixel takes the mean of whichever neighbouring quadrant is flattest,
	// which turns detail into flat brush dabs while keeping edges
	vec2 px = 1.0 / VIEWPORT_SIZE;
	const int R = 6;
	vec3 m[4];
	vec3 s[4];
	for (int k = 0; k < 4; k++) { m[k] = vec3(0.0); s[k] = vec3(0.0); }
	vec2 dirs[4] = vec2[](vec2(-1, -1), vec2(1, -1), vec2(-1, 1), vec2(1, 1));
	for (int k = 0; k < 4; k++) {
		for (int j = 0; j <= R; j++) {
			for (int i = 0; i <= R; i++) {
				vec3 c = textureLod(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * dirs[k] * px * 1.4, 0.0).rgb;
				m[k] += c;
				s[k] += c * c;
			}
		}
	}
	float n = float((R + 1) * (R + 1));
	float best = 1e9;
	vec3 outc = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		vec3 mu = m[k] / n;
		vec3 v = abs(s[k] / n - mu * mu);
		float sig = v.r + v.g + v.b;
		if (sig < best) { best = sig; outc = mu; }
	}
	// canvas tooth
	float t = phash(floor(FRAGCOORD.xy / 1.5)) * 0.5 + phash(floor(FRAGCOORD.xy / 5.0) + 3.0) * 0.5;
	outc *= 0.95 + t * 0.1;
	float e = edges(SCREEN_UV, px, 1.2, INV_PROJECTION_MATRIX, 0.06, 0.5);
	outc = mix(outc, outc * 0.35, e * 0.75);
	ALBEDO = outc;
}
""",
	"lofi": """
void fragment() {
	// low internal resolution, 15-bit colour with ordered dithering
	vec2 res = vec2(480.0, 270.0);
	vec2 cell = floor(SCREEN_UV * res);
	vec2 uv = (cell + 0.5) / res;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	int bx = int(mod(cell.x, 4.0));
	int by = int(mod(cell.y, 4.0));
	float bayer[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
	float d = (bayer[by * 4 + bx] / 16.0 - 0.5) / 32.0;
	c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
	c = floor((c + d) * 32.0 + 0.5) / 32.0;
	c = pow(c, vec3(2.2));
	ALBEDO = c;
}
""",
	"facet": """
void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float e = edges(SCREEN_UV, px, 1.0, INV_PROJECTION_MATRIX, 0.08, 0.9);
	ALBEDO = mix(c, c * 0.6, e * 0.5);
}
""",
}


func _shape_pass() -> void:
	if not SHAPES.has(_shape):
		return
	var top: Node = _lineup if _lineup != null else _view
	if top == null:
		return
	var sc: Dictionary = SHAPES[_shape]
	for sk in top.find_children("*", "Skeleton3D", true, false):
		var skel := sk as Skeleton3D
		var eff := PackedFloat32Array()
		eff.resize(skel.get_bone_count())
		for i in skel.get_bone_count():
			var nm := skel.get_bone_name(i)
			var par := skel.get_bone_parent(i)
			var pe := 1.0 if par < 0 else eff[par]
			var want := pe
			for pre in sc:
				if nm == pre or nm.begins_with(pre):
					want = sc[pre]
					break
			eff[i] = want
			skel.set_bone_pose_scale(i, Vector3.ONE * (want / pe))
