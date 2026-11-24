shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Flames from a wrecked engine: soft camera-facing licks that add light (bright enough to bloom), hot
// yellow in the middle going orange at the edge, fading out (the instance colour's alpha).
varying vec4 tint;

void vertex() {
	tint = COLOR;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 q = UV - 0.5;
	// (a tongue: narrower at the top. smoothstep's edges must rise: some phone GPUs give garbage otherwise,
	// which showed as pale boxes round the flames)
	q.y *= 0.8 + 0.6 * (1.0 - smoothstep(-0.5, 0.5, q.y));
	float r = length(q) * 2.0;
	float a = clamp(1.0 - smoothstep(0.1, 1.0, r), 0.0, 1.0);
	vec3 hot = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.86, 0.45), 1.0 - smoothstep(0.0, 0.7, r));
	ALBEDO = hot * tint.rgb * 2.2 * a * a * tint.a;
}
