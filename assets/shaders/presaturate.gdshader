shader_type canvas_item;

uniform float saturation_boost : hint_range(1.0, 3.0) = 1.8;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	tex.rgb = mix(vec3(grey), tex.rgb, saturation_boost);
	COLOR = tex;
}
