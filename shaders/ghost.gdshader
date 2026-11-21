shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;

uniform vec3 color : source_color = vec3(0.75, 0.9, 1.0);
uniform float alpha = 0.38;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color + vec3(rim * 0.35);
	ALPHA = alpha * (0.55 + rim * 0.8);
}
