shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// The abyss far below the floating islands: a deep galaxy void with drifting nebula auras, aurora
// ribbons and star fields. Layers slide at different rates as you drive (depth without perspective).
uniform vec3 deep_color : source_color = vec3(0.02, 0.01, 0.06);
uniform vec3 aura_a : source_color = vec3(0.2, 0.9, 0.7);
uniform vec3 aura_b : source_color = vec3(0.6, 0.3, 1.0);
uniform vec3 aura_c : source_color = vec3(1.0, 0.45, 0.6);
uniform float aura_amount = 1.0;
uniform float star_amount = 1.0;
uniform float glow = 1.0;
uniform vec2 cam_xz = vec2(0.0);

varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

vec3 stars(vec2 p, float density, float size, float tw) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell);
	if (h < 1.0 - density) return vec3(0.0);
	vec2 o = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(f - o * 0.6);
	float core = smoothstep(size, 0.0, d);
	float flare = smoothstep(size * 4.0, 0.0, abs(f.x - o.x * 0.6)) * smoothstep(size * 0.6, 0.0, abs(f.y - o.y * 0.6))
		+ smoothstep(size * 4.0, 0.0, abs(f.y - o.y * 0.6)) * smoothstep(size * 0.6, 0.0, abs(f.x - o.x * 0.6));
	float twk = 0.65 + 0.35 * sin(TIME * (1.5 + h * 3.0) * tw + h * 60.0);
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), hash(cell + 1.3));
	return tint * (core + flare * 0.35 * step(0.985, h)) * twk;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	// farthest: big slow nebula, barely moving as you drive
	vec2 pn = (wp.xz - cam_xz * 0.86) * 0.038;
	vec2 q = vec2(fbm(pn + vec2(0.0, t * 0.012)), fbm(pn + vec2(5.2, 1.3) - t * 0.01));
	vec2 r = vec2(fbm(pn + q * 1.8 + vec2(1.7, 9.2) + t * 0.015), fbm(pn + q * 1.8 + vec2(8.3, 2.8)));
	float neb = fbm(pn + r * 2.2);
	vec3 col = deep_color;
	vec3 aura = mix(aura_a, aura_b, smoothstep(0.25, 0.75, r.x));
	aura = mix(aura, aura_c, smoothstep(0.55, 0.9, q.y) * 0.8);
	float dens = smoothstep(0.3, 0.78, neb);
	col += aura * pow(dens, 1.4) * 1.25 * aura_amount;
	col += aura_b * smoothstep(0.2, 0.6, neb) * 0.12 * aura_amount;
	// bright filaments where the swirls fold
	float fil = smoothstep(0.03, 0.0, abs(neb - 0.62)) * smoothstep(0.4, 0.8, r.y);
	col += mix(aura, vec3(1.0), 0.35) * fil * 0.35 * aura_amount;
	// aurora ribbons, a little closer
	vec2 pa = (wp.xz - cam_xz * 0.78) * 0.03;
	float rib = sin(pa.x * 1.3 + pa.y * 0.6 + fbm(pa * 0.7 + t * 0.03) * 5.0 + t * 0.05);
	float band = smoothstep(0.92, 1.0, rib) * smoothstep(0.3, 0.7, fbm(pa * 1.3 - t * 0.02));
	col += mix(aura_a, aura_c, 0.5 + 0.5 * sin(pa.y * 0.4 + t * 0.07)) * band * 0.45 * aura_amount;
	// glowing motes drifting far below (closest layer)
	vec2 pm = (wp.xz - cam_xz * 0.6) * 0.18 + vec2(0.0, t * 0.08);
	col += aura_c * stars(pm, 0.03, 0.08, 0.3) * 0.5;
	// star fields at three depths
	col += stars((wp.xz - cam_xz * 0.93) * 0.55, 0.06, 0.05, 1.0) * 0.9 * star_amount;
	col += stars((wp.xz - cam_xz * 0.88) * 0.28, 0.05, 0.06, 0.7) * 1.1 * star_amount;
	col += stars((wp.xz - cam_xz * 0.82) * 0.12, 0.03, 0.05, 0.5) * 1.4 * star_amount;
	ALBEDO = col * glow;
}
