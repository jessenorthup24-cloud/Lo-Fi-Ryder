shader_type canvas_item;

// The sense of speed, without smearing your car: the picture is blurred outward from the road ahead
// (more toward the edges), with an oval round the car kept sharp, plus faint light streaks rushing past
// the edges of the screen.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7778;
uniform vec2 center = vec2(0.5, 0.5);          // where things rush out from (the road ahead)
uniform vec2 car_uv = vec2(0.5, 0.68);         // your car on screen
uniform vec2 car_size = vec2(0.15, 0.17);      // and how big (half width, half height)

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col = texture(screen_tex, uv);
	// keep the car (and a little round it) sharp
	float keep = smoothstep(1.0, 1.55, length((uv - car_uv) / car_size));
	vec2 dir = uv - center;
	float r = length(dir * vec2(aspect, 1.0));
	float k = amount * keep * smoothstep(0.12, 0.75, r);
	if (k > 0.003) {
		vec3 acc = col.rgb;
		for (int i = 1; i < 7; i++) {
			acc += texture(screen_tex, uv - dir * k * 0.075 * float(i) / 6.0).rgb;
		}
		col.rgb = acc / 7.0;
	}
	// streaks at the edges
	float lanes = 170.0;
	float u = (atan(dir.y, dir.x * aspect) / 6.2831853 + 0.5) * lanes;
	float id = floor(u);
	float h = hash(id);
	float h2 = hash(id + 31.7);
	float on = step(0.62, h);
	float f = fract(r * 0.8 - TIME * (1.4 + h2 * 1.2) + h * 7.0);
	float dash = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.28, 0.5, f));
	float thin = 1.0 - smoothstep(0.04, 0.1, abs(fract(u) - 0.5));
	float edge = smoothstep(0.62, 1.0, r);
	float a = on * dash * thin * edge * amount * 0.5 * keep;
	COLOR = vec4(mix(col.rgb, vec3(1.0, 0.98, 0.94), a), 1.0);
}
