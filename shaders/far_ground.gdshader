shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// The land far below the floating islands. Fades between patterns as you change region:
// x countryside patchwork fields, y seaside ocean, z forest canopy, w sky (just haze).
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float season = 0.0;
uniform vec4 biome_w = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec2 offset = vec2(0.0);
uniform vec3 haze_color : source_color = vec3(0.9, 0.92, 1.0);
uniform float haze = 0.5;
uniform float night = 0.0;

varying vec3 wp;

vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
vec3 pal(float idx) {
	float s = mod(season, 4.0);
	float r0 = floor(s);
	float r1 = mod(r0 + 1.0, 4.0);
	float f = smoothstep(0.6, 1.0, fract(s));
	float u = (idx + 0.5) / 48.0;
	return mix(textureLod(palette, vec2(u, (r0 + 0.5) / 4.0), 0.0).rgb, textureLod(palette, vec2(u, (r1 + 0.5) / 4.0), 0.0).rgb, f);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz - offset;
	vec3 col = vec3(0.0);
	if (biome_w.x > 0.01) {
		vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071 / 7.5;
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float h = hash(cell);
		vec3 fields = h < 0.3 ? pal(0.0) : (h < 0.55 ? pal(32.0) : (h < 0.78 ? pal(43.0) : pal(1.0)));
		float rows = step(0.5, fract((h < 0.55 && h >= 0.3 ? q.x : q.y) * 9.0)) * 0.06;
		fields *= 1.0 - rows;
		float hedge = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.05, f.y) * smoothstep(0.0, 0.05, 1.0 - f.x) * smoothstep(0.0, 0.05, 1.0 - f.y);
		fields = mix(pal(9.0) * 0.85, fields, hedge);
		if (hash(cell + 7.0) > 0.9) { fields = mix(fields, lin(vec3(0.45, 0.72, 0.85)), smoothstep(0.42, 0.38, length(f - 0.5))); }
		col += fields * biome_w.x;
	}
	if (biome_w.y > 0.01) {
		float wv = sin((p.x - p.y) * 0.3 + TIME * 0.7) * 0.5 + 0.5;
		vec3 ocean = mix(lin(vec3(0.30, 0.60, 0.84)), lin(vec3(0.42, 0.74, 0.92)), wv * 0.5 + noise(p * 0.12 + TIME * 0.05) * 0.3);
		float sp = step(0.992, hash(floor(p * 1.2) + floor(TIME * 1.5)));
		ocean += vec3(sp * 0.5);
		col += ocean * biome_w.y;
	}
	if (biome_w.z > 0.01) {
		float n = noise(p * 0.22) * 0.6 + noise(p * 0.6) * 0.4;
		vec3 forest = mix(pal(9.0) * 0.8, pal(1.0), smoothstep(0.35, 0.65, n));
		forest = mix(forest, pal(38.0), smoothstep(0.78, 0.85, noise(p * 0.05 + 3.0)));
		col += forest * biome_w.z;
	}
	col += haze_color * biome_w.w;
	col *= mix(1.0, 0.42, night);
	ALBEDO = mix(col, haze_color, haze);
}
