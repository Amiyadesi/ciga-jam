shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 beam_color : source_color = vec4(0.72, 0.82, 1.0, 0.62);
uniform float intensity : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform bool texture_tints_light = true;

uniform float mask_power : hint_range(0.2, 6.0, 0.05) = 1.25;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.02;

uniform float cone_center : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float cone_top_width : hint_range(0.0, 2.0, 0.01) = 0.22;
uniform float cone_bottom_width : hint_range(0.0, 2.0, 0.01) = 0.92;
uniform float edge_softness : hint_range(0.001, 0.8, 0.001) = 0.16;

uniform float vertical_fade_in : hint_range(0.0, 0.8, 0.01) = 0.02;
uniform float vertical_fade_out : hint_range(0.0, 0.8, 0.01) = 0.18;
uniform float lower_falloff_power : hint_range(0.2, 5.0, 0.05) = 1.45;

uniform float ray_density : hint_range(0.0, 80.0, 0.1) = 18.0;
uniform float ray_strength : hint_range(0.0, 2.0, 0.01) = 0.34;
uniform float ray_waver : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float dust_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float noise_speed : hint_range(0.0, 4.0, 0.01) = 0.22;
uniform float seed = 9.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i + seed);
	float b = hash(i + vec2(1.0, 0.0) + seed);
	float c = hash(i + vec2(0.0, 1.0) + seed);
	float d = hash(i + vec2(1.0, 1.0) + seed);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float source_luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float texture_mask = max(source.a, source.a * source_luma);
	float mask = pow(max(texture_mask - alpha_cutoff, 0.0) / max(1.0 - alpha_cutoff, 0.001), mask_power);

	float y = clamp(UV.y, 0.0, 1.0);
	float width = mix(cone_top_width, cone_bottom_width, y);
	float half_width = max(width * 0.5, 0.001);
	float edge_distance = abs(UV.x - cone_center) / half_width;
	float cone = 1.0 - smoothstep(1.0 - edge_softness, 1.0, edge_distance);

	float fade_in = smoothstep(0.0, max(vertical_fade_in, 0.001), y);
	float fade_out = 1.0 - smoothstep(1.0 - vertical_fade_out, 1.0, y);
	float distance_fade = pow(1.0 - y * 0.72, lower_falloff_power);
	float vertical = fade_in * fade_out * distance_fade;

	float wave = sin(y * 12.0 + TIME * noise_speed * 2.4) * ray_waver;
	float ray_noise = value_noise(vec2((UV.x + wave) * max(ray_density, 0.001), y * 2.0 + TIME * noise_speed));
	float rays = pow(ray_noise, 3.0) * ray_strength;
	float dust = value_noise(UV * vec2(96.0, 32.0) + vec2(TIME * noise_speed * 0.35, TIME * -noise_speed * 0.18)) * dust_strength;

	float alpha = clamp(mask * cone * vertical * (1.0 + rays + dust) * intensity, 0.0, 1.0) * beam_color.a;
	vec3 tinted = texture_tints_light ? max(source.rgb, vec3(0.08)) * beam_color.rgb : beam_color.rgb;
	COLOR = vec4(tinted * intensity * (0.75 + rays + dust * 0.45), alpha);
}
