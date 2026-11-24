shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Tyre smoke and dust: soft round puffs that always face the camera and fade out (the instance colour's
// alpha), a little dimmer after dark.
uniform float night = 0.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(0.15, 1.0, r);
	ALBEDO = tint.rgb * mix(1.0, 0.4, night);
	ALPHA = a * a * tint.a * 0.75;
}
