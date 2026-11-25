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
uniform vec3 rim_color : source_color = vec3(0.75, 0.85, 1.0);   // sky light catching the edges
uniform float depth_bias = 0.0;        // roads and lots: drawn a hair toward the camera so they never flicker (fraction of distance)
// after dark, lights near the camera light things up: street lamps (warm) and your headlights (cool). xyz: where,
// w: reach in metres (negative: a headlight), 0: none
uniform vec4 lamps[16];
uniform vec3 lamp_col : source_color = vec3(1.0, 0.76, 0.44);
uniform vec3 head_col : source_color = vec3(0.85, 0.92, 1.0);
// your car's neon underglow, as light (it lies on whatever's under the car: road, kerb, grass, its own
// lower body): xyz where (just under the floor), w strength (0: none); fwd: the car's way (xyz), w half
// length; col: linear rgb, a half width
global uniform vec4 neon_pos;
global uniform vec4 neon_fwd;
global uniform vec4 neon_col;

varying vec3 v_col;
varying float v_glow;
varying vec3 v_world;
varying vec3 v_nrm;
varying float v_direct;
varying float v_win;


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
	// (written for every vertex: once a shader sets POSITION, Godot no longer does)
	// depth_bias pulls the surface toward the camera by that fraction of its distance (a few cm far
	// away, nothing up close), so it never covers things standing on it
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= 1.0 - depth_bias;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec3 col = mix(v_col, vec3(1.0, 0.8, 0.45), v_win * night * 0.75) * tint;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = mix(col, rim_color, 0.55) * rim * rim_strength * 1.5 + col * v_glow * night * 1.4 + col * v_glow * 0.25
		+ vec3(1.0, 0.78, 0.42) * v_win * night * 1.2 + vec3(flash);
	if (night > 0.02) {
		vec3 lit = vec3(0.0);
		for (int i = 0; i < 16; i++) {
			vec4 L = lamps[i];
			float reach = abs(L.w);
			if (reach < 0.01) {
				continue;
			}
			vec3 d = L.xyz - v_world;
			float dist = length(d);
			float q = dist / reach;
			float att = clamp(1.0 - q * q, 0.0, 1.0);
			att *= att;
			float ndl = clamp(dot(v_nrm, d / max(dist, 0.001)), 0.0, 1.0) * 0.85 + 0.15;
			lit += (L.w < 0.0 ? head_col : lamp_col) * att * ndl;
		}
		// (plus a touch of the light's own colour, so a pool of light shows even on dark asphalt)
		EMISSION += (col * 1.9 + vec3(0.035)) * lit * night;
	}
	if (neon_pos.w > 0.001) {
		vec3 nd = v_world - neon_pos.xyz;
		vec3 nf = neon_fwd.xyz;
		vec3 ns = normalize(cross(vec3(0.0, 1.0, 0.0), nf) + vec3(1e-4, 0.0, 0.0));
		float lon = dot(nd, nf) / max(neon_fwd.w, 0.1);
		float lat = dot(nd, ns) / max(neon_col.a, 0.1);
		float r = sqrt(lon * lon + lat * lat);
		float f = (1.0 - smoothstep(0.15, 1.0, r)) * (1.0 - smoothstep(0.35, 1.3, abs(nd.y)));
		if (f > 0.0) {
			vec3 to_l = normalize(neon_pos.xyz - v_world + vec3(0.0, 0.2, 0.0));
			float ndl = clamp(dot(v_nrm, to_l), 0.0, 1.0) * 0.75 + 0.25;
			EMISSION += neon_col.rgb * f * ndl * neon_pos.w;
		}
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// the turn from light to shade: soft over the first few degrees, so the flat panels of a car (or a
	// curved roof) that face the sun only just don't flicker between lit and dark facet by facet
	float band = smoothstep(-0.02, shade_soft + 0.2, ndl);
	// the shadow map's own soft edge, as it comes (sharpening it turns its grain into blotches)
	float sh = ATTENUATION;
	float l = band * sh;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * l / PI;
}
