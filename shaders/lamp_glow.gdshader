shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// The pool of warm light a street lamp throws on the road below it (fades in after dusk).
uniform float night = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float f = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = tint.rgb * f * f * night * 0.6;
}
