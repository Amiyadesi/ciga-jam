shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.98, 0.08, 0.05, 1.0);
uniform float edge_start : hint_range(0.0, 1.0) = 0.58;
uniform float edge_end : hint_range(0.0, 1.2) = 1.02;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float rect_edge = max(abs(uv.x), abs(uv.y));
	float radial = clamp(length(uv) * 0.78, 0.0, 1.0);
	float edge_mask = smoothstep(edge_start, edge_end, rect_edge);
	float radial_mask = smoothstep(edge_start - 0.08, edge_end, radial);
	float pulse = 0.92 + 0.08 * sin(TIME * 6.0);
	float alpha = clamp(max(edge_mask, radial_mask * 0.82) * intensity * pulse, 0.0, 1.0);
	COLOR = vec4(glow_color.rgb, alpha);
}
