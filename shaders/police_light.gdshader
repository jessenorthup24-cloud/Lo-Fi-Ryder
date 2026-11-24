shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// A police light bar: red and blue taking turns in quick double flashes. As a lamp it's the bulb itself;
// as a glow (a soft disc that always faces you) it's the haze round it, bigger after dark.
uniform vec3 col : source_color = vec3(1.0, 0.12, 0.16);
uniform float phase = 0.0;      // (0 for red, 0.5 for blue: they take turns)
uniform bool glow = false;
uniform float night = 0.0;

float flash() {
	float t = fract(TIME * 1.5 + phase);
	return step(t, 0.5) * step(fract(t * 4.0), 0.55);      // two quick blinks, then the other colour's turn
}

void vertex() {
	if (glow) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	float f = flash();
	if (glow) {
		vec2 d = UV * 2.0 - 1.0;
		float r = dot(d, d);
		float g = exp(-r * 5.0) * (0.35 + 0.65 * night) + exp(-r * 40.0) * 0.9;
		ALBEDO = col * g * f;
	} else {
		ALBEDO = col * (0.18 + 2.4 * f);
	}
}
