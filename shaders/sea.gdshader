shader_type spatial;
render_mode cull_disabled, specular_disabled, depth_draw_opaque;
// The sea around the island: toon blue with drifting sparkles and gentle swell.

uniform vec3 deep : source_color = vec3(0.24, 0.62, 0.82);
uniform vec3 shallow : source_color = vec3(0.45, 0.82, 0.9);
uniform vec3 sparkle : source_color = vec3(1.0, 1.0, 1.0);
uniform float night = 0.0;

varying vec3 v_world;

float hsh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hsh(i), hsh(i + vec2(1, 0)), u.x), mix(hsh(i + vec2(0, 1)), hsh(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float t = TIME;
	float n = vn(p * 0.06 + vec2(t * 0.05, t * 0.03)) * 0.6 + vn(p * 0.17 - vec2(t * 0.08, -t * 0.05)) * 0.4;
	vec3 col = mix(deep, shallow, smoothstep(0.35, 0.8, n) * 0.6);
	float sp = smoothstep(0.82, 0.9, vn(p * 0.45 + vec2(t * 0.3, t * 0.21)) * vn(p * 0.31 - vec2(t * 0.2, 0.0)) * 1.9);
	float far_fade = clamp(length(v_world - CAMERA_POSITION_WORLD) / 220.0, 0.0, 1.0);
	col = mix(col, sparkle, sp * 0.55 * (1.0 - far_fade) * (1.0 - night * 0.7));
	ALBEDO = col * (1.0 - night * 0.55);
	ROUGHNESS = 1.0;
	EMISSION = col * 0.18;
}
