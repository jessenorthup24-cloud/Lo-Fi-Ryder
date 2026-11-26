shader_type canvas_item;
// A collectible car card (or its back, or a foil pack), drawn on a ColorRect the card's size. The text goes
// on top (ui.gd draws it). Front: a metallic frame in the rarity's colour, the car's photo in a window, a
// dark plate for the name and facts; Rare and up get a holographic sheen that sweeps across, Epic more,
// Legendary gold with glints. Back: the game's card back. Pack: a crimped foil wrapper.

uniform int mode = 0;                 // 0 front, 1 back, 2 pack
uniform vec4 rarity_col : source_color = vec4(0.6, 0.64, 0.68, 1.0);
uniform int rarity = 0;               // 0 Common .. 4 Legendary
uniform sampler2D photo : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_photo = false;
uniform float photo_aspect = 1.5;     // the photo's width / height
uniform vec2 card_px = vec2(250.0, 350.0);
uniform float tilt = 0.0;             // moves the sheen (a little wobble as it's handled)
uniform float glow = 0.0;             // a flash as it's revealed
uniform bool show_ring = true;        // (the back: the logo ring; off when the fact is written on it)

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

// brushed metal in the given colour: a light band across, fine streaks
vec3 metal(vec2 uv, vec3 c, float t) {
	float band = 0.55 + 0.45 * sin((uv.x * 1.3 + uv.y * 2.2) * 3.14159 + t * 0.6 + tilt * 3.0);
	float streak = hash(vec2(floor(uv.y * card_px.y * 0.5), 3.0)) * 0.12;
	vec3 hi = mix(c, vec3(1.0), 0.55);
	vec3 lo = c * 0.45;
	return mix(lo, hi, band) + streak;
}

void fragment() {
	vec2 uv = UV;
	vec2 px = uv * card_px;
	vec2 half_px = card_px * 0.5;
	float r = card_px.x * 0.07;
	float d = sd_round_box(px - half_px, half_px, r);
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);
	vec3 rc = rarity_col.rgb;
	vec3 col;
	float t = TIME;
	if (mode == 2) {
		// the pack: foil, crimped top and bottom, a bright wrapper with the rarity colour (gold by default)
		float crimp_h = card_px.y * 0.07;
		float zig = abs(fract(px.x / 12.0) - 0.5) * 8.0;
		bool in_crimp = px.y < crimp_h || px.y > card_px.y - crimp_h;
		float edge = in_crimp ? step(zig, min(px.y, card_px.y - px.y)) : 1.0;
		inside = (in_crimp ? edge : 1.0) * step(0.0, px.x) * step(px.x, card_px.x);
		vec3 base = metal(uv, rc, t);
		float holo = sin((uv.x - uv.y) * 9.0 + t * 1.4 + tilt * 4.0) * 0.5 + 0.5;
		base = mix(base, base + hue(uv.x * 0.8 + uv.y * 0.4 + t * 0.08) * 0.35, holo * 0.6);
		if (in_crimp) {
			base *= 0.8 + 0.2 * step(0.5, fract(px.x / 6.0));
		}
		// a dark band across the middle for the title
		float band = smoothstep(0.36, 0.37, uv.y) * (1.0 - smoothstep(0.63, 0.64, uv.y));
		col = mix(base, vec3(0.05, 0.05, 0.08), band * 0.85);
		col += glow * vec3(1.0, 0.9, 0.6);
		COLOR = vec4(col, inside);
	} else if (mode == 1) {
		// the back: midnight blue, a fine diamond pattern, a ring in the middle (the logo goes on it)
		vec2 g = px / 14.0;
		float diamond = abs(fract(g.x + g.y) - 0.5) + abs(fract(g.x - g.y) - 0.5);
		col = mix(vec3(0.07, 0.07, 0.16), vec3(0.12, 0.11, 0.26), smoothstep(0.4, 0.6, diamond));
		float ring = abs(length(px - half_px) - card_px.x * 0.3);
		col = mix(col, vec3(1.0, 0.31, 0.55), (1.0 - smoothstep(1.5, 3.5, ring)) * 0.9 * (show_ring ? 1.0 : 0.0));
		if (!show_ring) { col *= 0.55; }
		float frame_b = smoothstep(-card_px.x * 0.05, -card_px.x * 0.04, d);
		col = mix(col, metal(uv, vec3(1.0, 0.31, 0.55), t) * 0.8, frame_b);
		col += glow * vec3(1.0, 0.9, 0.7);
		COLOR = vec4(col, inside);
	} else {
	// the front
	float fw = card_px.x * 0.045;                                      // the frame's width
	float frame = smoothstep(-fw - 1.0, -fw, d);
	vec3 fcol = metal(uv, rc, t);
	if (rarity == 4) {
		fcol = metal(uv, vec3(1.0, 0.78, 0.25), t);                    // gold
	}
	// inside the frame: a dark plate
	col = mix(vec3(0.06, 0.06, 0.09), vec3(0.11, 0.1, 0.15), uv.y);
	// the photo window
	vec2 wmin = vec2(fw * 1.6, card_px.y * 0.115);
	vec2 wmax = vec2(card_px.x - fw * 1.6, card_px.y * 0.6);
	vec2 wc = (wmin + wmax) * 0.5;
	vec2 wh = (wmax - wmin) * 0.5;
	float wd = sd_round_box(px - wc, wh, card_px.x * 0.035);
	float win = 1.0 - smoothstep(-0.5, 0.5, wd);
	vec2 wuv = (px - wmin) / (wmax - wmin);
	vec3 pic;
	if (has_photo) {
		// cover the window: crop the photo to fill it
		float win_aspect = (wmax.x - wmin.x) / (wmax.y - wmin.y);
		vec2 puv = wuv;
		if (photo_aspect > win_aspect) {
			puv.x = 0.5 + (wuv.x - 0.5) * win_aspect / photo_aspect;
		} else {
			puv.y = 0.5 + (wuv.y - 0.5) * photo_aspect / win_aspect;
		}
		pic = texture(photo, puv).rgb;
	} else {
		// no photo: a studio backdrop in the rarity's colour (ui.gd draws a car on it)
		pic = mix(rc * 0.9 + 0.08, rc * 0.25, wuv.y);
		pic += 0.25 * (1.0 - smoothstep(0.0, 0.6, length(wuv - vec2(0.5, 0.35))));
	}
	// (a soft inner shadow round the window's edge)
	pic *= 1.0 - 0.35 * smoothstep(-card_px.x * 0.05, 0.0, wd);
	col = mix(col, pic, win);
	// a thin bright rule under the window
	float rule = (1.0 - smoothstep(0.0, 1.5, abs(px.y - (wmax.y + card_px.y * 0.02)))) * step(wmin.x, px.x) * step(px.x, wmax.x);
	col = mix(col, rc * 1.3, rule * 0.9);
	// the frame on top
	col = mix(col, fcol, frame);
	// the sheen: Rare and up. A rainbow band sweeping across (more for Epic; gold glints for Legendary)
	if (rarity >= 2) {
		float k = rarity == 2 ? 0.22 : (rarity == 3 ? 0.38 : 0.3);
		float sweep = fract((uv.x * 0.7 - uv.y * 0.9) * 0.6 + t * 0.18 + tilt * 0.6);
		float band = smoothstep(0.0, 0.18, sweep) * (1.0 - smoothstep(0.18, 0.42, sweep));
		vec3 rainbow = hue(uv.x * 0.9 + uv.y * 0.6 + t * 0.05);
		col += rainbow * band * k * (0.55 + 0.45 * frame);
		// a fine holo grain over the whole card for Epic and Legendary
		if (rarity >= 3) {
			float grain = hash(floor(px / 3.0)) * hash(floor(px / 3.0) + 7.0);
			col += rainbow * grain * 0.08;
		}
		if (rarity == 4) {
			vec2 cell = floor(px / 18.0);
			float h = hash(cell);
			float tw = pow(max(sin(t * (1.5 + h * 3.0) + h * 40.0), 0.0), 24.0);
			float spark = (1.0 - smoothstep(0.0, 3.0, length(fract(px / 18.0) * 18.0 - 9.0))) * step(0.82, h);
			col += vec3(1.0, 0.92, 0.6) * spark * tw * 1.4;
		}
	}
	col += glow * mix(rc, vec3(1.0), 0.4);
	COLOR = vec4(col, inside);
	}
}
