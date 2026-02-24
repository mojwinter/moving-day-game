shader_type canvas_item;

// Soft bloom for constellation edges. Samples screen texture, extracts bright
// pixels, applies a single-pass box blur, and blends additively.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.35;
uniform float brightness_threshold : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE;
	// 5-tap cross blur (cheap approximation of Gaussian)
	vec4 sum = vec4(0.0);
	float weights[5] = {0.06, 0.24, 0.4, 0.24, 0.06};
	// Horizontal pass
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			vec2 offset = vec2(float(i), float(j)) * ps * 2.0;
			vec4 s = texture(screen_texture, SCREEN_UV + offset);
			float w = weights[i + 2] * weights[j + 2];
			sum += s * w;
		}
	}
	// Extract bright parts
	float brightness = dot(sum.rgb, vec3(0.299, 0.587, 0.114));
	float soft = smoothstep(brightness_threshold, brightness_threshold + 0.2, brightness);
	COLOR = vec4(sum.rgb * soft * bloom_intensity, soft * bloom_intensity);
}
