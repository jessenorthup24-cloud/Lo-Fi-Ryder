shader_type canvas_item;
// Aiming: the picture goes soft except where it matters, you and what you're aiming at, both kept sharp
// (two spots on the screen, eased off at their edges). A rect over the view, under the HUD, shown only while
// aiming. Drawn in 2D like the speed blur and sampled without mipmaps: on phones (GL Compatibility, MSAA)
// a 3D-pass copy of the screen, or its mipmaps, can come back blank and white the whole view out.
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec2 focus_a = vec2(0.5, 0.5);   // what you're aiming at (screen uv)
uniform vec2 focus_b = vec2(0.4, 0.7);   // you
uniform float r_a = 0.16;                // their radii (in screen heights)
uniform float r_b = 0.22;
uniform float amount = 0.0;              // 0..1: how far into aiming
uniform float aspect = 1.7778;

void fragment() {
	vec2 p = SCREEN_UV * vec2(aspect, 1.0);
	float da = length(p - focus_a * vec2(aspect, 1.0)) / r_a;
	float db = length(p - focus_b * vec2(aspect, 1.0)) / r_b;
	float coc = smoothstep(1.0, 2.4, min(da, db)) * amount;
	vec3 col = texture(screen, SCREEN_UV).rgb;
	if (coc > 0.02) {
		// two soft rings of taps
		vec2 px = SCREEN_PIXEL_SIZE * coc * 4.0;
		vec3 acc = col * 2.0;
		float w = 2.0;
		for (int k = 0; k < 8; k++) {
			float ang = float(k) * 0.785398;
			vec2 d = vec2(cos(ang), sin(ang));
			acc += texture(screen, SCREEN_UV + d * px).rgb;
			acc += texture(screen, SCREEN_UV + d * px * 2.2 + vec2(-d.y, d.x) * px * 0.6).rgb;
			w += 2.0;
		}
		col = mix(col, acc / w, smoothstep(0.0, 0.4, coc));
	}
	COLOR = vec4(col, 1.0);
}
