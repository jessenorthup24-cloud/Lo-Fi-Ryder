shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The backdrop behind everything (a quad parented to the camera): the same galaxy as the abyss below,
// so the floating islands hang in space. Matches far_ground.gdshader's colors.
uniform vec3 deep_color : source_color = vec3(0.02, 0.01, 0.06);
uniform vec3 aura_a : source_color = vec3(0.2, 0.9, 0.7);
uniform vec3 aura_b : source_color = vec3(0.6, 0.3, 1.0);
uniform vec3 aura_c : source_color = vec3(1.0, 0.45, 0.6);
uniform float aura_amount = 1.0;
uniform float star_amount = 1.0;
uniform float glow = 1.0;
uniform vec2 scroll = vec2(0.0);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.8, 0.5);
uniform float sun_amount = 0.0;

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
vec3 stars(vec2 p, float density, float size) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell);
	if (h < 1.0 - density) return vec3(0.0);
	vec2 o = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(f - o * 0.6);
	float twk = 0.65 + 0.35 * sin(TIME * (1.5 + h * 3.0) + h * 60.0);
	return mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), hash(cell + 1.3)) * smoothstep(size, 0.0, d) * twk;
}

void fragment() {
	vec2 uv = UV * vec2(1.0, 1.6);
	float t = TIME;
	vec2 pn = uv * 2.4 + scroll * 0.6;
	vec2 q = vec2(fbm(pn + vec2(0.0, t * 0.012)), fbm(pn + vec2(5.2, 1.3) - t * 0.01));
	vec2 r = vec2(fbm(pn + q * 1.8 + vec2(1.7, 9.2) + t * 0.015), fbm(pn + q * 1.8 + vec2(8.3, 2.8)));
	float neb = fbm(pn + r * 2.2);
	vec3 col = deep_color * (0.8 + 0.4 * UV.y);
	vec3 aura = mix(aura_a, aura_b, smoothstep(0.25, 0.75, r.x));
	aura = mix(aura, aura_c, smoothstep(0.55, 0.9, q.y) * 0.8);
	float dens = smoothstep(0.3, 0.78, neb);
	col += aura * pow(dens, 1.4) * 1.25 * aura_amount;
	col += aura_b * smoothstep(0.2, 0.6, neb) * 0.12 * aura_amount;
	col += mix(aura, vec3(1.0), 0.35) * smoothstep(0.03, 0.0, abs(neb - 0.62)) * smoothstep(0.4, 0.8, r.y) * 0.35 * aura_amount;
	// a broad galaxy band across the top
	float gb = exp(-pow((uv.y - 0.35 - 0.15 * uv.x + fbm(uv * 3.0 + scroll) * 0.2) * 3.2, 2.0));
	col += mix(aura_b, vec3(1.0, 0.9, 0.8), 0.4) * gb * 0.25 * aura_amount;
	// the distant star that lights the islands
	vec2 sp = vec2(0.78, 0.12);
	float sd = length((UV - sp) * vec2(1.0, 1.3));
	col += sun_glow * (smoothstep(0.5, 0.0, sd) * 0.35 + smoothstep(0.05, 0.0, sd) * 1.2) * sun_amount;
	col += stars(uv * vec2(110.0, 110.0) + scroll * 8.0, 0.07, 0.12) * 0.9 * star_amount;
	col += stars(uv * vec2(45.0, 45.0) + scroll * 4.0, 0.05, 0.14) * 1.2 * star_amount;
	ALBEDO = col * glow;
}
