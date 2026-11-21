shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, specular_disabled;

uniform vec3 color : source_color = vec3(0.24, 0.17, 0.15);
uniform float width = 0.035;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color;
}
