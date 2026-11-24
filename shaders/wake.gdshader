shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A boat's wake on the water: a churned white trail straight behind it and two lines of foam spreading out
// in a V, breaking up and fading as they go. UV.x is across (0..1), UV.y along (0 at the stern).
uniform float speed = 10.0;      // (the foam drifts back at the boat's speed)
uniform float night = 0.0;

float hsh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hsh(i), hsh(i + vec2(1, 0)), u.x), mix(hsh(i + vec2(0, 1)), hsh(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float x = UV.x - 0.5;
	float y = UV.y;
	float n = vn(vec2(UV.x * 18.0, (y - TIME * speed * 0.02) * 30.0));
	// the churn behind the stern
	float trail = (1.0 - smoothstep(0.03 + y * 0.12, 0.08 + y * 0.2, abs(x))) * (1.0 - smoothstep(0.1, 0.75, y));
	// the V: two lines spreading out
	float arm = abs(abs(x) - (0.06 + y * 0.42));
	float v = (1.0 - smoothstep(0.0, 0.025 + y * 0.03, arm)) * (1.0 - smoothstep(0.35, 1.0, y));
	float a = max(trail * (0.55 + 0.45 * n), v * (0.4 + 0.6 * n));
	a *= smoothstep(0.0, 0.04, y);
	ALBEDO = vec3(1.0) * (1.0 - night * 0.6);
	ALPHA = clamp(a, 0.0, 1.0) * 0.85;
}
