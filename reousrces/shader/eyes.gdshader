shader_type canvas_item;

uniform float open_amount : hint_range(0.0, 1.0, 0.01) = 0.67;
uniform float edge_blur_amount : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform vec4 background_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sclera_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 pupil_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 pupil_position = vec2(0.5, 0.5); // 0.0 to 1.0
uniform float pupil_radius : hint_range(0.0, 0.5) = 0.12;
uniform float sclera_radius : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float blur = edge_blur_amount * 0.5;
	// v controls the opening. 0.02 is the minimum slit width.
	float v = max(open_amount, 0.02) + edge_blur_amount * open_amount;
	
	// Original parabolic eyelid distance logic
	float d1 = (2.0 * v * pow(UV.x - 0.5, 2.0) - v/2.0 + 0.5) - (UV.y+v/(2.0));
	float d2 = -(-2.0 * v * pow(UV.x - 0.5, 2.0) + v/2.0 + 0.5) + (UV.y-v/(2.0));
	float d = max(d1, d2);

	if (d > -blur) {
		// Outside the eye (Eyelid / Skin) -> Transparent
		float alpha = clamp((-d-blur)/-blur, 0.0, 1.0);
		// We set alpha to 0 for the area outside the slit to make it transparent
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Inside the eye (The hole)
		
		// Sclera (White part)
		// It moves slightly with the pupil for a 3D effect
		vec2 sclera_pos = mix(vec2(0.5), pupil_position, 0.3);
		float dist_sclera = distance(UV, sclera_pos);
		float sclera_mask = smoothstep(sclera_radius, sclera_radius - 0.05, dist_sclera);
		
		// Pupil (Black part)
		float dist_pupil = distance(UV, pupil_position);
		float pupil_mask = smoothstep(pupil_radius, pupil_radius - 0.02, dist_pupil);
		
		vec4 eye_final = mix(background_color, sclera_color, sclera_mask);
		eye_final = mix(eye_final, pupil_color, pupil_mask);
		
		COLOR = eye_final;
	}
}
