shader_type spatial;
// Aiming depth of field (the Compatibility renderer has none of its own): a quad over the whole view that
// blurs the picture behind it by how far each pixel is from what you're aiming at. Far off goes soft; the
// target stays sharp; close up (your shoulder) a touch soft. Only drawn while aiming.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth : hint_depth_texture, filter_nearest;
uniform float focus = 20.0;     // metres to what you're aiming at
uniform float amount = 0.0;     // 0..1: how far into aiming

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth, uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
	#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void fragment() {
	float z = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float far_k = smoothstep(focus * 1.25, focus * 2.6 + 6.0, z);
	float near_k = 1.0 - smoothstep(1.2, 2.6, z);
	float coc = clamp(max(far_k, near_k * 0.55), 0.0, 1.0) * amount;
	vec3 col = textureLod(screen, SCREEN_UV, 0.0).rgb;
	if (coc > 0.02) {
		float lod = coc * 2.6;
		vec2 px = coc * 2.5 / vec2(textureSize(screen, 0));
		vec3 acc = textureLod(screen, SCREEN_UV, lod).rgb * 2.0;
		acc += textureLod(screen, SCREEN_UV + vec2(px.x, px.y) * 1.5, lod).rgb;
		acc += textureLod(screen, SCREEN_UV + vec2(-px.x, px.y) * 1.5, lod).rgb;
		acc += textureLod(screen, SCREEN_UV + vec2(px.x, -px.y) * 1.5, lod).rgb;
		acc += textureLod(screen, SCREEN_UV + vec2(-px.x, -px.y) * 1.5, lod).rgb;
		col = mix(col, acc / 6.0, smoothstep(0.0, 0.35, coc));
	}
	ALBEDO = col;
}
