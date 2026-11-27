shader_type canvas_item;

// Busted: the picture drains to grey and darkens towards the edges (k: 0 off, 1 all the way).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float k = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	vec2 d = SCREEN_UV - 0.5;
	float vig = clamp(1.0 - dot(d, d) * 1.6, 0.0, 1.0);
	vec3 grey = vec3(g) * (0.55 + 0.35 * vig);
	COLOR = vec4(mix(c, grey, k), 1.0);
}
