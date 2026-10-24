// Character shader for soldiers and enemies (see view/model_kit.gd).
// Flat role colours from the generated models, plus:
//   grime    procedural dirt blotches and scuffs, mud creeping up from the boots
//   rim      a cool rim light so silhouettes read against the night map
//   infection teal veins that spread over the surface as the value rises (0..1)
//   flash    hit / heal flash driven by the unit view
// Skinned characters (assets/characters) also have a textured body: rest positions in
// the vertex colour keep the noise stuck to the skin, and UV2.x marks bare skin
// (head, hands) versus the rest, which takes the role colour as a fitted undersuit.
shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float pulse = 0.0;            // emission breathing amount
uniform float grime = 0.6;
uniform float rim = 0.25;
uniform vec3 rim_color : source_color = vec3(0.45, 0.62, 0.68);
uniform float infection = 0.0;
uniform vec3 vein_color : source_color = vec3(0.18, 0.95, 0.78);
uniform float vein_energy = 2.6;
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform bool rest_from_color = false;
uniform bool textured = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec3 skin_tint : source_color = vec3(1.0);
uniform float skin_all = 0.0;
uniform float camo = 0.0;             // two-tone disruptive pattern on uniforms         // 1 = the whole body is bare (infected)

varying vec3 obj_pos;
varying float height;
varying float skin;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
				mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise3(p) * 0.55 + noise3(p * 2.1) * 0.3 + noise3(p * 4.3) * 0.15;
}

void vertex() {
	obj_pos = VERTEX;
	skin = 0.0;
	if (rest_from_color) {
		obj_pos = (COLOR.rgb - vec3(0.5, 0.5, 0.0)) * vec3(2.0, 2.0, 2.5);
		skin = UV2.x;
	}
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - NODE_POSITION_WORLD.y;
}

void fragment() {
	vec3 p = obj_pos;
	vec3 col = albedo;
	if (textured) {
		vec3 tex = texture(albedo_tex, UV).rgb;
		float lum = dot(tex, vec3(0.3, 0.55, 0.15));
		tex = mix(tex, vec3(lum), 0.35);   // the stock skin is warm; mute it to the palette
		float bare = max(skin, skin_all);
		// the undersuit keeps only a hint of the painted shading, and none of the muscle normals
		vec3 suit = albedo * (0.8 + lum * 0.45);
		col = mix(suit, tex * skin_tint, bare);
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, UV).rgb, bare);
	}
	if (camo > 0.0) {
		float c1 = smoothstep(0.5, 0.56, fbm(p * vec3(5.0, 3.0, 5.0) + 7.3));
		float c2 = smoothstep(0.55, 0.6, fbm(p * vec3(6.0, 4.0, 6.0) - 2.1));
		col = mix(col, col * vec3(0.62, 0.66, 0.6), c1 * camo);
		col = mix(col, col * 1.25 + vec3(0.02), c2 * camo * 0.6);
	}
	// dirt blotches, fine scuffs (lighter on metal edges), mud near the ground
	float blotch = smoothstep(0.42, 0.78, fbm(p * 7.0 + 3.1));
	col *= 1.0 - blotch * 0.38 * grime;
	float scuff = step(0.955, noise3(p * 95.0)) * grime;
	col = mix(col, col * 1.7 + vec3(0.04), scuff * (0.25 + metallic * 0.5));
	float mud = (1.0 - smoothstep(0.02, 0.38, height)) * grime;
	col = mix(col, vec3(0.11, 0.095, 0.075), mud * 0.6);
	float rough = clamp(roughness + blotch * 0.1 * grime, 0.0, 1.0);

	vec3 emit = emission_color * emission_energy * (1.0 + pulse * sin(TIME * 3.0 + p.y * 4.0));
	// infection: a spreading mask reveals thin glowing veins and sickly skin
	if (infection > 0.0) {
		float spread = fbm(p * 2.6 + 11.0);
		float mask = smoothstep(spread - 0.1, spread + 0.05, infection * 1.1 - 0.2);
		float n = noise3(p * 13.0) * 0.7 + noise3(p * 27.0) * 0.3;
		float vein = pow(1.0 - abs(n * 2.0 - 1.0), 26.0) * mask;
		col = mix(col, col * vec3(0.55, 0.78, 0.72), mask * 0.45);
		emit += vein_color * vein * vein_energy * (0.8 + 0.2 * sin(TIME * 2.4 + p.y * 9.0));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += rim_color * fres * rim;
	emit += flash_color * flash;
	EMISSION = emit;
}
