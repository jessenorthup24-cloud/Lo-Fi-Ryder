shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The backdrop behind the floating islands. Lives on a quad parented to the camera.
uniform vec3 top_color : source_color = vec3(0.55, 0.8, 1.0);
uniform vec3 bottom_color : source_color = vec3(1.0, 0.9, 0.78);
uniform vec3 haze_color : source_color = vec3(1.0, 0.95, 0.9);
uniform float stars = 0.0;
uniform vec2 scroll = vec2(0.0);
uniform float cloud_amount = 0.5;
uniform vec3 cloud_color : source_color = vec3(1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = smoothstep(0.0, 1.0, uv.y);
	vec3 col = mix(top_color, bottom_color, t);
	col = mix(col, haze_color, smoothstep(0.55, 1.0, uv.y) * 0.35);
	// soft cloud sea, scrolling slower than the ground (fake depth)
	vec2 cp = vec2(uv.x * 2.2, uv.y * 3.6) + scroll;
	float c = fbm(cp * 1.4 + vec2(TIME * 0.01, 0.0));
	float cl = smoothstep(0.6 - cloud_amount * 0.2, 0.85, c) * (0.25 + 0.75 * t);
	col = mix(col, cloud_color, cl * 0.5);
	// stars at night
	vec2 sp = uv * vec2(90.0, 160.0) + scroll * 6.0;
	vec2 cell = floor(sp);
	float h = hash(cell);
	vec2 f = fract(sp) - 0.5;
	float star = step(0.985, h) * smoothstep(0.18, 0.0, length(f)) * (0.6 + 0.4 * sin(TIME * 2.0 + h * 40.0));
	col += vec3(star) * stars * (1.0 - t * 0.7);
	ALBEDO = col;
}
