shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Underglow: a soft pool of coloured light on the ground under the car (brighter after dark).
uniform vec4 col : source_color = vec4(1.0, 0.25, 0.8, 1.0);
uniform float night = 0.0;

void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;                  // 0 middle .. 1 edge
	float d = length(max(q - vec2(0.55, 0.7), 0.0)) / 0.45;   // a rounded rectangle, soft round the edge
	float f = 1.0 - smoothstep(0.0, 1.0, d);
	ALBEDO = col.rgb * f * f * (0.35 + 0.65 * night);
}
