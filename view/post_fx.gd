extends RefCounted
## Full-screen finishing pass drawn over the 3D view and under the HUD: vignette,
## film grain and faint scanline grime. Pure overlay (no screen read), so it costs
## almost nothing and works on both renderers.

const SHADER := """
shader_type canvas_item;
uniform float vignette = 0.62;
uniform float grain = 0.045;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	c.x *= 1.25;
	float v = smoothstep(0.35, 0.95, length(c)) * vignette;
	float n = hash(floor(FRAGCOORD.xy / 2.0) + floor(TIME * 24.0) * 1.37) - 0.5;
	float lines = sin(FRAGCOORD.y * 1.6) * 0.012;
	float a = clamp(v + abs(n) * grain + lines, 0.0, 1.0);
	COLOR = vec4(vec3(0.01, 0.015, 0.015) + vec3(step(0.0, n) * grain * 0.6), a);
}
"""


static func make() -> ColorRect:
	var r := ColorRect.new()
	r.name = "Vignette"
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	return r
