shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// The neon tubes under the floor: only there when you're looking from underneath (not through the bodywork
// from above or the side).
uniform vec4 col : source_color = vec4(1.0, 0.25, 0.8, 1.0);
varying vec3 wpos;
varying vec3 car_up;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	car_up = normalize(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (dot(cam - wpos, car_up) > -0.02) {
		discard;
	}
	ALBEDO = col.rgb * 1.3;
}
