shader_type spatial;
render_mode cull_back, specular_disabled;

// Season palette: 32 color slots x 4 rows (spring, summer, autumn, winter).
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float season = 0.0;          // 0..4, wraps; blends near the end of each season
uniform float night = 0.0;           // 0..1, lights up the glow parts (windows, lamps, headlights)
uniform float sway = 0.0;            // wind sway for plants
uniform vec2 wind = vec2(0.0);       // world-space wind (x, z)
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 shadow_tint : source_color = vec3(1.0);
uniform float rim_strength = 0.22;
uniform float shade_soft = 0.05;
uniform float flash = 0.0;           // white flash (e.g. pickups)
// fog that thickens up the screen (ahead of the car), set by atmos.gd
uniform vec3 fog_color : source_color = vec3(1.0);
uniform float fog_amount = 0.0;
uniform vec3 fog_origin = vec3(0.0);
uniform vec3 fog_dir = vec3(-0.7071, 0.0, -0.7071);
uniform float fog_start = 2.0;
uniform float fog_len = 22.0;
uniform float haze = 0.6;              // things below the islands fade into the sky

varying vec3 v_col;
varying float v_glow;
varying vec3 v_world;

const float PAL_W = 32.0;

vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 pal(float idx) {
	float s = mod(season, 4.0);
	float r0 = floor(s);
	float r1 = mod(r0 + 1.0, 4.0);
	float f = smoothstep(0.6, 1.0, fract(s));
	float u = (idx + 0.5) / PAL_W;
	vec3 a = textureLod(palette, vec2(u, (r0 + 0.5) / 4.0), 0.0).rgb;
	vec3 b = textureLod(palette, vec2(u, (r1 + 0.5) / 4.0), 0.0).rgb;
	return mix(a, b, f);
}

void vertex() {
	vec4 c = COLOR;
	v_glow = 0.0;
	if (c.a < 0.2) {
		v_col = pal(floor(c.r * 255.0 + 0.5));
	} else if (c.a < 0.4) {
		// tile part: top or side slot comes from the instance; .b jitters brightness per tile
		float idx = c.r > 0.5 ? INSTANCE_CUSTOM.r : INSTANCE_CUSTOM.g;
		v_col = pal(floor(idx * 255.0 + 0.5)) * (0.95 + INSTANCE_CUSTOM.b * 0.1);
	} else if (c.a < 0.6) {
		v_col = lin(c.rgb);
		v_glow = 1.0;
	} else {
		v_col = lin(c.rgb);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = max(VERTEX.y, 0.0);
		float t = TIME * 1.6 + wp.x * 0.31 + wp.z * 0.23;
		vec2 off = (wind * (0.55 + 0.45 * sin(t * 1.3)) + vec2(sin(t), cos(t * 0.83)) * 0.04) * h * h * sway;
		vec3 local = (inverse(mat3(MODEL_MATRIX)) * vec3(off.x, 0.0, off.y));
		VERTEX += local;
	}
}

void fragment() {
	vec3 col = v_col * tint;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 emi = col * rim * rim_strength + col * v_glow * night * 1.4 + vec3(flash);
	float ahead = dot(v_world - fog_origin, fog_dir);
	float below = clamp((-v_world.y - 1.0) * 0.045, 0.0, 1.0);
	float f = clamp(smoothstep(fog_start, fog_start + fog_len, ahead) * fog_amount + below * haze, 0.0, 0.96);
	ALBEDO = col * (1.0 - f);
	EMISSION = emi * (1.0 - f) + fog_color * f;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(0.0, shade_soft, ndl);
	float sh = smoothstep(0.25, 0.65, ATTENUATION);
	float l = band * sh;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * l / PI;
}
