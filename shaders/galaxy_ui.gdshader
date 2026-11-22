shader_type canvas_item;

// A slow galaxy backdrop for full-screen menus (the garage): the same nebula and stars as the abyss.
uniform vec4 deep_color : source_color = vec4(0.07, 0.04, 0.16, 1.0);
uniform vec4 aura_a : source_color = vec4(0.24, 0.95, 0.65, 1.0);
uniform vec4 aura_b : source_color = vec4(0.54, 0.36, 1.0, 1.0);
uniform vec4 aura_c : source_color = vec4(1.0, 0.6, 0.42, 1.0);
uniform vec2 aspect = vec2(1.0, 2.0);

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
	float twk = 0.6 + 0.4 * sin(TIME * (1.2 + h * 2.5) + h * 60.0);
	return mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.86, 0.72), hash(cell + 1.3)) * smoothstep(size, 0.0, d) * twk;
}

void fragment() {
	vec2 uv = UV * aspect;
	float t = TIME * 0.6;
	vec2 pn = uv * 1.6;
	vec2 q = vec2(fbm(pn + vec2(0.0, t * 0.02)), fbm(pn + vec2(5.2, 1.3) - t * 0.015));
	vec2 r = vec2(fbm(pn + q * 1.8 + vec2(1.7, 9.2) + t * 0.02), fbm(pn + q * 1.8 + vec2(8.3, 2.8)));
	float neb = fbm(pn + r * 2.2);
	vec3 col = deep_color.rgb * (0.75 + 0.5 * (1.0 - UV.y));
	vec3 aura = mix(aura_a.rgb, aura_b.rgb, smoothstep(0.25, 0.75, r.x));
	aura = mix(aura, aura_c.rgb, smoothstep(0.55, 0.9, q.y) * 0.8);
	float dens = smoothstep(0.3, 0.78, neb);
	col += aura * pow(dens, 1.4) * 1.1;
	col += aura_b.rgb * smoothstep(0.2, 0.6, neb) * 0.1;
	col += stars(uv * 60.0, 0.06, 0.12) * 0.9;
	col += stars(uv * 26.0 + 3.0, 0.05, 0.14) * 1.2;
	COLOR = vec4(col, 1.0);
}
