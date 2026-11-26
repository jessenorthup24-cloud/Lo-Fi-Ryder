shader_type sky;
// The sky: a gradient from the horizon up (atmos.gd sets the colours by the time of day), the sun by day
// and the moon by night (both where the one directional light is), stars after dark, and a layer of clouds
// drifting over (how much cover from the weather). Cheap enough for phones: a couple of noise lookups.

uniform vec3 top_color : source_color = vec3(0.35, 0.6, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 ground_color : source_color = vec3(0.4, 0.42, 0.45);
uniform float night = 0.0;           // 0 day .. 1 night
uniform float cloud_cover = 0.35;    // 0 clear .. 1 overcast
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.75);
uniform float curve = 0.12;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	// the gradient
	float t = pow(clamp(up, 0.0, 1.0), curve * 4.0);
	vec3 col = mix(horizon_color, top_color, clamp(t, 0.0, 1.0));
	if (up < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	}
	if (!AT_CUBEMAP_PASS && up > -0.05) {
		// stars: a fine scatter, twinkling, only once it's dark and only where there's no cloud
		if (night > 0.05) {
			vec2 sp = d.xz / (up + 0.25) * 90.0;
			float h = hash(floor(sp));
			float star = step(0.985, h) * smoothstep(0.5, 0.05, length(fract(sp) - 0.5));
			star *= 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 50.0);
			col += vec3(star) * night * clamp(up * 4.0, 0.0, 1.0) * (1.0 - cloud_cover);
		}
		// the sun or the moon, where the light is
		if (LIGHT0_ENABLED) {
			vec3 ld = normalize(LIGHT0_DIRECTION);
			float c = dot(d, ld);
			if (night < 0.5) {
				float disc = smoothstep(0.9993, 0.9996, c);
				float glow = pow(max(c, 0.0), 220.0) * 0.6 + pow(max(c, 0.0), 12.0) * 0.18;
				col += sun_tint * (disc * 4.0 + glow) * (1.0 - night * 2.0) * (1.0 - cloud_cover * 0.7);
			} else {
				float disc = smoothstep(0.99915, 0.99945, c);
				// (craters: blotches on the face)
				vec3 tx = normalize(cross(ld, vec3(0.0, 1.0, 0.0)));
				vec3 ty = cross(tx, ld);
				vec2 mp = vec2(dot(d, tx), dot(d, ty)) * 620.0;
				float crater = smoothstep(0.55, 0.75, noise(mp * 0.6)) * 0.25;
				float halo = pow(max(c, 0.0), 400.0) * 0.35;
				col = mix(col, vec3(0.92, 0.93, 0.88) * (1.0 - crater), disc * night * (1.0 - cloud_cover * 0.6));
				col += vec3(0.55, 0.6, 0.75) * halo * night;
			}
		}
		// clouds: a sheet overhead, seen in perspective, drifting
		if (up > 0.0) {
			vec2 cp = d.xz / (up + 0.12) * 1.3 + vec2(TIME * 0.006, TIME * 0.002);
			float n = fbm(cp);
			float cover = mix(0.72, 0.32, cloud_cover);
			float cl = smoothstep(cover, cover + 0.18, n);
			cl *= smoothstep(0.0, 0.18, up);          // (thinning toward the horizon, into the haze)
			vec3 cc = cloud_color * mix(1.0, 0.75, smoothstep(cover, cover + 0.5, n));   // (darker bellies)
			col = mix(col, cc, cl * 0.9);
		}
	}
	COLOR = col;
}
