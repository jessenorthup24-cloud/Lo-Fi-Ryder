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
// car paint (gloss > 0: the car_paint material only): a clear coat that reflects the sky, brightest at a
// glancing angle (fresnel), a light line where the horizon reflects, and a crisp toon highlight from the sun
uniform float gloss = 0.0;
uniform vec3 refl_sky : source_color = vec3(0.45, 0.62, 0.9);
uniform vec3 refl_horizon : source_color = vec3(0.85, 0.88, 0.92);
uniform vec3 refl_ground : source_color = vec3(0.16, 0.15, 0.14);
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
// livery art for a car made as a textured model (tools/cars/bake_glb_car.gd): vertex alpha 0.8-0.95 reads
// its colour from here through UV, times the vertex colour
global uniform sampler2D car_detail : filter_linear_mipmap;

varying vec3 v_col;
varying float v_glow;
varying vec3 v_world;
varying vec3 v_nrm;
varying float v_direct;
varying float v_win;
varying float v_tex;
varying float v_slot;
// the ground's detail (grass, asphalt, pavement, dirt): a baked tiling noise (r: grain, g: patches, b: cracks)
uniform sampler2D ground_noise : filter_linear_mipmap, repeat_enable;
uniform float ground_detail = 0.0;   // 0: plain (the garage turntable's material); main.gd turns it on


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
	v_tex = 0.0;
	v_slot = -1.0;
	v_direct = c.a > 0.6 ? 1.0 : 0.0;
	if (c.a < 0.2) {
		v_slot = floor(c.r * 255.0 + 0.5);
		v_col = pal(v_slot);
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
	} else if (c.a < 0.95) {
		v_col = lin(c.rgb);
		v_tex = 1.0;
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

// Detail on the flat ground, by what it is (palette slots: grass 0-1, sand 2, dirt 4-5, path 22, soil 33,
// cobble 37, concrete 49, asphalt 51, red sand 52): patches over metres, grain up close (faded out with
// distance so it doesn't shimmer), cracks in the asphalt, slab joints in the pavement.
vec3 ground(vec3 base, float s, vec2 p, float dist) {
	float near = (1.0 - smoothstep(18.0, 70.0, dist)) * ground_detail;
	float g2 = texture(ground_noise, p / 90.0).g - 0.5;           // big patches (5-15 m)
	if (s < 1.5) {
		// grass: lighter and darker patches, drier (yellower) in places, and a fine blade grain
		float fine = texture(ground_noise, p / 11.0).r - 0.5;
		float g3 = texture(ground_noise, p / 31.0).g - 0.5;
		vec3 c = base * (1.0 + g2 * 0.34 + g3 * 0.16 + fine * 0.26 * near);
		return mix(c, c * vec3(1.1, 1.05, 0.72), clamp(g2 * 2.2, 0.0, 1.0) * 0.55 * ground_detail);
	}
	if (abs(s - 51.0) < 0.5) {
		// asphalt: aggregate grain, worn and patched areas, hairline cracks
		vec3 n1 = texture(ground_noise, p / 6.0).rgb;
		// (cracks only in the worn stretches, not all over)
		float crack = texture(ground_noise, p / 27.0).b * smoothstep(0.08, 0.2, texture(ground_noise, p / 140.0 + 0.37).g - 0.5);
		float g3 = texture(ground_noise, p / 17.0).g - 0.5;
		vec3 c = base * (1.0 + (n1.r - 0.5) * 0.34 * near + g2 * 0.18 + g3 * 0.12);
		c *= 1.0 + step(0.86, n1.r) * 0.14 * near;                      // (light stones in it)
		return c * (1.0 - crack * 0.32 * (1.0 - smoothstep(10.0, 45.0, dist)) * ground_detail);
	}
	if (abs(s - 49.0) < 0.5 || abs(s - 37.0) < 0.5) {
		// pavement: concrete slabs (joints every 2 m), grain, stains
		float fine = texture(ground_noise, p / 5.0).r - 0.5;
		vec2 q = abs(fract(p / 2.0) - 0.5);
		float joint = smoothstep(0.475, 0.495, max(q.x, q.y));
		vec3 c = base * (1.0 + fine * 0.2 * near + g2 * 0.14);
		return c * (1.0 - joint * 0.22 * near);
	}
	// dirt, sand, paths, soil: grainy and patchy
	float fine = texture(ground_noise, p / 7.0).r - 0.5;
	return base * (1.0 + fine * 0.3 * near + g2 * 0.2);
}

void fragment() {
	vec3 base = v_col;
	if (v_tex > 0.5) {
		base *= lin(texture(car_detail, UV).rgb);
	}
	if (ground_detail > 0.0 && v_slot >= 0.0 && normalize(v_nrm).y > 0.55) {
		base = ground(base, v_slot, v_world.xz, length(v_world - CAMERA_POSITION_WORLD));
	}
	vec3 col = mix(base, vec3(1.0, 0.8, 0.45), v_win * night * 0.75) * tint;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = mix(col, rim_color, 0.55) * rim * rim_strength * 1.5 + col * v_glow * night * 1.4 + col * v_glow * 0.25
		+ vec3(1.0, 0.78, 0.42) * v_win * night * 1.2 + vec3(flash);
	if (gloss > 0.0 && v_glow < 0.5) {
		// the world reflected in the paint: sky above, a bright band at the horizon, the road below
		vec3 rv = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz);
		vec3 env = mix(refl_ground, refl_horizon, smoothstep(-0.25, 0.0, rv.y));
		env = mix(env, refl_sky, smoothstep(0.02, 0.5, rv.y));
		env += refl_horizon * exp(-pow(rv.y / 0.045, 2.0)) * 0.55;
		float fres = 0.05 + 0.95 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		// (darker paint shows the reflection more, as it does: a black car's a mirror, a white one's mostly white)
		float lum = dot(col, vec3(0.3, 0.55, 0.15));
		EMISSION += env * fres * gloss * mix(0.85, 0.4, clamp(lum * 1.6, 0.0, 1.0)) * (1.0 - night * 0.75);
	}
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
	if (gloss > 0.0) {
		// the sun on the clear coat: a small, hard-edged highlight (toon), and a soft sheen round it
		vec3 hv = normalize(LIGHT + VIEW);
		float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
		float hot = smoothstep(0.965, 0.975, nh) * 0.9 + pow(nh, 40.0) * 0.18;
		DIFFUSE_LIGHT += LIGHT_COLOR * hot * gloss * sh * step(0.0, ndl);
	}
}
