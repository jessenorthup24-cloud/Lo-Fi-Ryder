shader_type canvas_item;

// Iris wipe between screens. progress 0 = clear, 1 = fully covered.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.996, 0.945, 0.871, 1.0);
uniform vec2 center = vec2(0.5, 0.55);
uniform vec2 aspect = vec2(0.5625, 1.0);

void fragment() {
	vec2 d = (UV - center) * aspect;
	float r = (1.0 - progress) * 1.25;
	float m = smoothstep(r, r + 0.006, length(d));
	COLOR = vec4(color.rgb, color.a * m);
}
