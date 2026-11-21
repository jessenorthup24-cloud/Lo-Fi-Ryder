shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Far-away clouds and islands under the play area: soft, flat and hazy.
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float season = 0.0;
uniform vec3 haze_color : source_color = vec3(0.9, 0.92, 1.0);
uniform float haze = 0.55;
uniform vec3 light_dir = vec3(0.4, 0.8, 0.3);
uniform float night = 0.0;

varying vec3 v_col;

vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }

vec3 pal(float idx) {
	float s = mod(season, 4.0);
	float r0 = floor(s);
	float r1 = mod(r0 + 1.0, 4.0);
	float f = smoothstep(0.6, 1.0, fract(s));
	float u = (idx + 0.5) / 32.0;
	return mix(textureLod(palette, vec2(u, (r0 + 0.5) / 4.0), 0.0).rgb, textureLod(palette, vec2(u, (r1 + 0.5) / 4.0), 0.0).rgb, f);
}

void vertex() {
	v_col = COLOR.a < 0.2 ? pal(floor(COLOR.r * 255.0 + 0.5)) : lin(COLOR.rgb);
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float l = 0.72 + 0.28 * smoothstep(-0.2, 0.6, dot(n, normalize(light_dir)));
	vec3 c = v_col * l * mix(1.0, 0.45, night);
	ALBEDO = mix(c, haze_color, haze);
}
