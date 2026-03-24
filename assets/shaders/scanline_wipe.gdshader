shader_type canvas_item;

uniform float scanline_wipe : hint_range(-0.1, 1.1) = -0.1;
uniform float scanline_wipe_width : hint_range(0.01, 0.2) = 0.05;
uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float wipe_y = UV.y;
	// Above the scanline = transparent (puzzle visible), below = opaque fill
	float mask = smoothstep(scanline_wipe - scanline_wipe_width, scanline_wipe, wipe_y);
	// Bright scanline bar at the edge
	float bar = 1.0 - smoothstep(0.0, scanline_wipe_width, abs(wipe_y - scanline_wipe));
	vec3 col = mix(fill_color.rgb, vec3(1.0), bar * 0.8);
	COLOR = vec4(col, mask);
}
