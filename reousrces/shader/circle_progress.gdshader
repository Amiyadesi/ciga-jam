// Liquid circular progress shader adapted from the Booom observation gauge.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;

group_uniforms Color;
uniform vec4 liquid_color : source_color = vec4(0.18, 0.74, 0.92, 1.0);
uniform vec4 liquid_back_color : source_color = vec4(0.06, 0.32, 0.55, 1.0);
uniform vec4 danger_color : source_color = vec4(1.0, 0.24, 0.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 0.24);
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 0.28);

group_uniforms Animation;
uniform float wave_speed : hint_range(0.0, 10.0) = 2.0;
uniform float wave_amplitude : hint_range(0.0, 0.2) = 0.05;
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;

group_uniforms Shape;
uniform float rim_thickness : hint_range(0.0, 0.5) = 0.1;
uniform float circle_radius : hint_range(0.0, 1.5) = 0.85;

void fragment() {
	vec2 uv = ((UV / -0.10)) + vec2(1.25, 1.25);
	float sdf = length(uv);
	float outer_circle = step(sdf, 1.0);
	float inner_circle = step(sdf, circle_radius);
	float rim_mask = outer_circle - step(sdf, 1.0 - rim_thickness);

	float vB = smoothstep(0.1, 0.9, sin(uv.x + (PI * 0.5)) - 0.3);
	float vBA = vB * sin(TIME * wave_speed * 2.0) * 0.1;
	float fW = (sin(((TIME * wave_speed) + uv.x) * wave_frequency) * wave_amplitude) + vBA;
	float bW = (sin(((TIME * -wave_speed) + uv.x) * wave_frequency + PI) * wave_amplitude) - vBA;
	float fA = (sin(TIME * wave_speed * 2.0) * 0.05) * vB;
	float fP = progress * 2.3 + (sin(TIME * PI * 0.5) * 0.1) - 1.1;

	float fF = step(uv.y, (fA + fW) + fP) * inner_circle;
	float bF = step(uv.y, (-fA + bW) + fP) * inner_circle;
	float shine = clamp(pow((sdf + 0.01) * ((1.0 - (fF + bF)) * inner_circle), 5.0), 0.0, 1.0);

	vec4 final_color = vec4(0.0);
	float danger_factor = 1.0 - smoothstep(0.1, 0.4, progress);
	vec4 front_liquid_color = vec4(mix(liquid_color.rgb, danger_color.rgb, danger_factor), liquid_color.a);
	vec4 back_liquid_color = vec4(mix(liquid_back_color.rgb, danger_color.rgb * 0.5, danger_factor), liquid_back_color.a);
	vec4 danger_rim_color = vec4(mix(rim_color.rgb, danger_color.rgb, danger_factor * 0.8), rim_color.a);

	final_color = mix(final_color, bg_color, inner_circle);
	final_color = mix(final_color, back_liquid_color, bF);
	final_color = mix(final_color, front_liquid_color, fF);
	final_color = mix(final_color, danger_rim_color, rim_mask);
	final_color += shine * shine_color;
	final_color.a *= outer_circle;

	COLOR = final_color;
}
