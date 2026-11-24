shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Underglow: a soft oval of coloured light on the ground under the car (it lies on the ground, whatever
// the car's doing), brighter after dark, fading out as the car leaves the ground or tips over.
uniform vec4 col : source_color = vec4(1.0, 0.25, 0.8, 1.0);
uniform float night = 0.0;
uniform float k = 1.0;

void fragment() {
	float r = length((UV - 0.5) * 2.0);
	float f = 1.0 - smoothstep(0.15, 1.0, r);
	ALBEDO = col.rgb * f * (0.42 + 0.7 * night) * k;
}
