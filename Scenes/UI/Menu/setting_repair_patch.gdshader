shader_type canvas_item;
render_mode blend_add;

uniform vec4 patch_color : source_color = vec4(0.36, 0.62, 0.88, 0.18);
uniform float intensity = 0.35;
uniform float patch_scale = 11.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 grid = floor(UV * patch_scale);
	float noise = hash(grid + floor(TIME * 1.4));
	float patch = smoothstep(0.88, 0.98, noise);
	float sweep = smoothstep(0.96, 1.0, fract((UV.x * 0.62 + UV.y * 0.38) * 36.0 - TIME * 0.18));
	COLOR = vec4(patch_color.rgb, patch_color.a * (patch * 0.34 + sweep * 0.26) * intensity);
}
