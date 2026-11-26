shader_type spatial;
// Aiming: the picture goes soft except where it matters, you and what you're aiming at, both kept sharp
// (two spots on the screen, eased off at their edges). A quad over the whole view, drawn only while aiming.
// (Done on the screen rather than by depth: phones' depth buffers don't all read back the same, and a
// depth-based blur there went soft all over.)
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec2 focus_a = vec2(0.5, 0.5);   // what you're aiming at (screen uv)
uniform vec2 focus_b = vec2(0.4, 0.7);   // you
uniform float r_a = 0.16;                // their radii (in screen heights)
uniform float r_b = 0.22;
uniform float amount = 0.0;              // 0..1: how far into aiming

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	vec2 sz = vec2(textureSize(screen, 0));
	float asp = sz.x / sz.y;
	vec2 p = SCREEN_UV * vec2(asp, 1.0);
	float da = length(p - focus_a * vec2(asp, 1.0)) / r_a;
	float db = length(p - focus_b * vec2(asp, 1.0)) / r_b;
	float coc = smoothstep(1.0, 2.4, min(da, db)) * amount;
	vec3 col = textureLod(screen, SCREEN_UV, 0.0).rgb;
	if (coc > 0.02) {
		// a soft ring of taps at a gentle mip (a deep mip alone goes blocky)
		vec2 px = coc * 3.0 / sz;
		float lod = coc * 1.4;
		vec3 acc = textureLod(screen, SCREEN_UV, lod).rgb * 2.0;
		for (int k = 0; k < 8; k++) {
			float ang = float(k) * 0.785398;
			acc += textureLod(screen, SCREEN_UV + vec2(cos(ang), sin(ang)) * px * 2.0, lod).rgb;
		}
		col = mix(col, acc / 10.0, smoothstep(0.0, 0.4, coc));
	}
	ALBEDO = col;
}
