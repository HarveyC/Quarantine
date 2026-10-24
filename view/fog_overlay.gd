extends MeshInstance3D
## Fog of war on screen. A full-screen pass rebuilds each pixel's world position from the depth
## buffer and looks its cell up in a small fog texture (one texel per map cell, linear filtered
## so the edge of vision is soft):
##   visible     the scene as it is
##   explored    dimmed, cold and mostly desaturated (you remember the layout)
##   unexplored  near black with a slow drifting haze
## Drawn first in the transparent pass, so move tiles, intent labels and rings stay readable on
## top of it. Changes cross-fade over FADE seconds as soldiers move.
##
## Also holds the view-side helpers for hidden enemies: `annotate` snapshots what the squad sees
## when a rules event happens (the event player applies it when the beat plays), and
## `set_ghost` draws Spore Sense contacts as see-through outlines.
## Reads GameState through Vision; never mutates it.

const Palette := preload("res://view/palette.gd")

const FADE := 0.35
## Events after which the fog picture is re-taken (a squad move adds the move's own check).
const FOG_EVENTS := ["start", "team_phase", "enemy_phase", "died", "spawned", "deployed",
	"deployable_end", "cover_destroyed", "level_changed", "ability", "gear", "mutation", "turned",
	"lapse", "recover", "revealed_area", "fell", "mission_end"]
## Events of an unseen enemy that still play (you hear it die).
const ALWAYS_SHOWN := ["died", "concealment_lost", "move", "telegraph", "reinforcements_incoming", "boss_phase", "boss_defeated"]

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform float blend = 1.0;
uniform vec2 map_size = vec2(16.0, 16.0);
uniform float enabled = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * ndc;
	world.xyz /= world.w;
	vec2 uv = (world.xz + 0.5) / map_size;
	float f = mix(texture(prev_tex, uv).r, texture(fog_tex, uv).r, blend);
	f = mix(1.0, f, enabled);
	float seen = smoothstep(0.62, 0.95, f);
	float known = smoothstep(0.08, 0.45, f);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 remembered = mix(vec3(lum), col, 0.3) * vec3(0.36, 0.40, 0.44);
	float haze = noise(world.xz * 0.45 + vec2(TIME * 0.07, TIME * 0.04)) * 0.5
		+ noise(world.xz * 1.1 - vec2(TIME * 0.05, 0.0)) * 0.25;
	vec3 dark = vec3(lum) * 0.13 + vec3(0.010, 0.014, 0.016) * (0.6 + haze);
	vec3 outc = mix(dark, remembered, known);
	ALBEDO = mix(outc, col, seen);
}
"""

var _mat: ShaderMaterial
var _size := Vector2i(1, 1)
var _cur := PackedByteArray()
var _tex_cur: ImageTexture
var _tex_prev: ImageTexture
var _blend := 1.0


func setup(grid: Grid) -> void:
	name = "FogOverlay"
	_size = Vector2i(grid.width, grid.height)
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mesh = q
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = -100
	_mat.set_shader_parameter("map_size", Vector2(_size))
	material_override = _mat
	var full := PackedByteArray()
	full.resize(_size.x * _size.y)
	full.fill(Vision.VISIBLE)
	_tex_cur = ImageTexture.create_from_image(_image(full))
	_tex_prev = ImageTexture.create_from_image(_image(full))
	_cur = full
	_bind()


func _image(cells: PackedByteArray) -> Image:
	var px := PackedByteArray()
	px.resize(_size.x * _size.y)
	for i in px.size():
		px[i] = clampi(int(cells[i]) * 127 + (1 if cells[i] == Vision.VISIBLE else 0), 0, 255) if i < cells.size() else 255
	return Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_L8, px)


func _bind() -> void:
	_mat.set_shader_parameter("fog_tex", _tex_cur)
	_mat.set_shader_parameter("prev_tex", _tex_prev)
	_mat.set_shader_parameter("blend", _blend)


## Shows a Vision.fog_grid picture, cross-fading from the current one.
func show_fog(cells: PackedByteArray, instant := false) -> void:
	if cells.size() != _size.x * _size.y or cells == _cur:
		return
	if instant:
		_tex_prev.update(_image(cells))
		_blend = 1.0
	else:
		_tex_prev.update(_image(_cur))
		_blend = 0.0
	_tex_cur.update(_image(cells))
	_cur = cells
	_bind()


## The fog picture on screen (tests).
func shown() -> PackedByteArray:
	return _cur


func _process(delta: float) -> void:
	if _blend < 1.0 and _mat != null:
		_blend = minf(1.0, _blend + delta / FADE)
		_mat.set_shader_parameter("blend", _blend)


# --- View-side helpers --------------------------------------------------------------------

## A copy of rules event `ev` with what the squad sees right now, taken when the event fires:
##   _unseen: living enemy ids the squad can't see; _sensed: ids shown as ghosts (Spore Sense);
##            _alive: living ids (the dead keep how they looked when they fell)
##   _fog:    Vision.fog_grid, after events that change what the squad sees
##   _seen:   for an enemy move, one bool per path cell (is it in sight there)
##   _hidden: true when the event belongs to an unseen enemy (no beat, no log line)
static func annotate(s: GameState, ev: Dictionary) -> Dictionary:
	var e := ev.duplicate()
	var unseen: Array[int] = []
	var alive: Array[int] = []
	for u in s.living():
		alive.append(u.id)
		if u.team != Types.Team.PLAYER and not Vision.sees_unit(s, Types.Team.PLAYER, u):
			unseen.append(u.id)
	e["_unseen"] = unseen
	e["_alive"] = alive
	e["_sensed"] = Vision.sensed(s)
	var type := str(ev.get("type", ""))
	var u := s.get_unit(int(ev.get("unit", -1))) if ev.get("unit") is int else null
	if type == "move" and u != null and u.team != Types.Team.PLAYER:
		var seen: Array[bool] = []
		var exposed: bool = Vision.is_exposed(s, u) and not u.status.get("hidden", false)
		for c in ev.get("path", []):
			seen.append(exposed or (not u.status.get("hidden", false) and Vision.cell_visible(s, Types.Team.PLAYER, c)))
		e["_seen"] = seen
	elif u != null and unseen.has(u.id) and not ALWAYS_SHOWN.has(type):
		e["_hidden"] = true
	if FOG_EVENTS.has(type) or (type == "move" and u != null and u.team == Types.Team.PLAYER):
		e["_fog"] = Vision.fog_grid(s)
	return e


## Spore Sense contact: a see-through body with a teal ring under it.
static func set_ghost(uv: Node3D, on: bool) -> void:
	if bool(uv.get_meta("ghost", false)) == on:
		return
	uv.set_meta("ghost", on)
	for g in uv.find_children("*", "GeometryInstance3D", true, false):
		if g.name != "GhostRing":
			(g as GeometryInstance3D).transparency = 0.7 if on else 0.0
	var ring := uv.get_node_or_null("GhostRing")
	if on and ring == null:
		ring = Palette.ring(0.38, 0.48, Palette.overlay(Color(Palette.TEAL, 0.6)))
		ring.name = "GhostRing"
		ring.position.y = 0.03
		uv.add_child(ring)
	elif ring != null:
		ring.visible = on
