shader_type spatial;
render_mode cull_back, specular_disabled;

// Vertex colour alpha picks the colour source: <0.2 palette slot, 0.2-0.4 tile top/side from the instance,
// 0.4-0.48 window glass (painted, lit at night), 0.48-0.6 glowing, 0.6-0.8 painted colour as is, above that sRGB.
// Season palette: 64 color slots x 4 rows (spring, summer, autumn, winter).
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
uniform float haze = 0.6;              // things below the islands fade into the abyss
uniform vec3 abyss_color : source_color = vec3(0.05, 0.03, 0.12);
uniform vec3 rim_color : source_color = vec3(0.6, 0.5, 1.0);   // the abyss's aura light on edges
uniform float decay = 0.0;             // post-apocalyptic weathering: grime and moss patches
uniform vec3 moss_color : source_color = vec3(0.35, 0.55, 0.25);

varying vec3 v_col;
varying float v_glow;
varying vec3 v_world;
varying vec3 v_nrm;
varying float v_direct;
varying float v_win;

float hsh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hsh(i), hsh(i + vec2(1, 0)), u.x), mix(hsh(i + vec2(0, 1)), hsh(i + vec2(1, 1)), u.x), u.y);
}

const float PAL_W = 64.0;

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
	v_win = 0.0;
	v_direct = c.a > 0.6 ? 1.0 : 0.0;
	if (c.a < 0.2) {
		v_col = pal(floor(c.r * 255.0 + 0.5));
	} else if (c.a < 0.4) {
		// tile part: top or side slot comes from the instance; .b jitters brightness per tile
		float idx = c.r > 0.5 ? INSTANCE_CUSTOM.r : INSTANCE_CUSTOM.g;
		v_col = pal(floor(idx * 255.0 + 0.5)) * (0.95 + INSTANCE_CUSTOM.b * 0.1);
	} else if (c.a < 0.48) {
		// window glass (the Kenney houses): painted by day, lit warm at night
		v_col = c.rgb;
		v_win = 1.0;
	} else if (c.a < 0.6) {
		v_col = lin(c.rgb);
		v_glow = 1.0;
	} else if (c.a < 0.8) {
		// colours as the artist painted them (the Kenney models)
		v_col = c.rgb;
	} else {
		v_col = lin(c.rgb);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	vec3 col = mix(v_col, vec3(1.0, 0.8, 0.45), v_win * night * 0.75) * tint;
	if (decay > 0.0 && v_glow < 0.5) {
		// weathering: blotchy grime, and moss creeping over anything facing up
		// (living things - anything already green - stay fresh)
		float green = smoothstep(0.01, 0.08, col.g - max(col.r, col.b));
		float n = vnoise(v_world.xz * 0.9 + vec2(v_world.y * 0.7));
		float grime = smoothstep(0.35, 0.75, n) * decay * (1.0 - green);
		float l = dot(col, vec3(0.3, 0.55, 0.15));
		col = mix(col, mix(vec3(l), col, 0.6) * vec3(0.86, 0.82, 0.78), grime * 0.55);
		float up = smoothstep(0.55, 0.9, v_nrm.y);
		float mp = smoothstep(0.6, 0.78, vnoise(v_world.xz * 0.9 + 11.0) * 0.8 + vnoise(v_world.xz * 3.1) * 0.2);
		col = mix(col, moss_color, up * mp * decay * 0.8 * (1.0 - green) * (1.0 - v_direct * 0.75));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 emi = mix(col, rim_color, 0.55) * rim * rim_strength * 1.5 + col * v_glow * night * 1.4 + col * v_glow * 0.25 + vec3(1.0, 0.78, 0.42) * v_win * night * 1.2 + vec3(flash);
	float ahead = dot(v_world - fog_origin, fog_dir);
	float below = clamp((-v_world.y - 1.0) * 0.045, 0.0, 1.0);
	float fa = smoothstep(fog_start, fog_start + fog_len, ahead) * fog_amount;
	float fb = below * haze;
	float f = clamp(fa + fb, 0.0, 0.96);
	vec3 fc = (fog_color * fa + abyss_color * fb) / max(fa + fb, 0.001);
	ALBEDO = col * (1.0 - f);
	EMISSION = emi * (1.0 - f) + fc * f;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(0.0, shade_soft, ndl);
	float sh = smoothstep(0.25, 0.65, ATTENUATION);
	float l = band * sh;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * l / PI;
}
