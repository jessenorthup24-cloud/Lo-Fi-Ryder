shader_type canvas_item;

// Speed streaks: thin light lines rushing out past the edges of the screen when you're going fast.
// The middle stays clear, so the car and the road ahead are never smeared.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7778;
uniform vec2 center = vec2(0.5, 0.56);

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 d = (UV - center) * vec2(aspect, 1.0);
	float r = length(d);
	float lanes = 170.0;
	float u = (atan(d.y, d.x) / 6.2831853 + 0.5) * lanes;
	float id = floor(u);
	float h = hash(id);
	float h2 = hash(id + 31.7);
	// only some lanes carry a streak, each running outward at its own pace
	float on = step(0.62, h);
	float f = fract(r * 0.8 - TIME * (1.4 + h2 * 1.2) + h * 7.0);
	float dash = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.28, 0.5, f));
	float thin = 1.0 - smoothstep(0.04, 0.1, abs(fract(u) - 0.5));
	float edge = smoothstep(0.62, 1.0, r);
	COLOR = vec4(1.0, 0.98, 0.94, on * dash * thin * edge * amount * 0.55);
}
