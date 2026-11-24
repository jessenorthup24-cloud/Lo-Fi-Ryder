shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The police helicopter's searchlight: the beam (a cone, faint, brighter near the lamp and fading off at
// its edges) or, as a pool, the soft circle of light where it lands.
uniform bool pool = false;
uniform float night = 0.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 col = vec3(1.0, 0.97, 0.88);
	if (pool) {
		vec2 d = UV * 2.0 - 1.0;
		float r = length(d);
		float a = (1.0 - smoothstep(0.6, 1.0, r)) * 0.42 + (1.0 - smoothstep(0.0, 0.5, r)) * 0.18;
		ALBEDO = col * a * night;
	} else {
		// (the cylinder is 1 tall, from -0.5 at the ground to 0.5 at the lamp)
		float along = v_local.y + 0.5;
		float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float a = (0.04 + 0.16 * along * along) * smoothstep(0.0, 0.6, edge);
		ALBEDO = col * a * night;
	}
}
