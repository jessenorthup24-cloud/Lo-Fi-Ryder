shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// A challenge's beacon: a column of light in its colour, bright at the ground and fading up into the sky,
// with bands of light drifting up it.
uniform vec4 col : source_color = vec4(1.0, 0.5, 0.4, 1.0);
uniform float height = 16.0;
uniform float fade = 1.0;      // (thins out as you drive into it)
varying float y;

void vertex() {
	y = VERTEX.y / height + 0.5;       // 0 at the ground, 1 at the top
}

float fade_y(float yy) {
	return pow(1.0 - clamp(yy, 0.0, 1.0), 1.6);
}

void fragment() {
	float bands = 0.7 + 0.3 * sin((y * 7.0 - TIME * 0.9) * 6.2831853);
	ALBEDO = col.rgb * fade_y(y) * bands * 0.45 * fade;
}
