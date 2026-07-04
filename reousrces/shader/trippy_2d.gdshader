shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 albedo : source_color = vec4(1.0);
// texture_albedo is usually the node's TEXTURE in 2D, 
// but we'll provide a separate uniform if specific sampling is needed.
uniform sampler2D texture_albedo : source_color;
uniform float alpha_scissor_threshold : hint_range(0, 1) = 0.5;
uniform float speed = 5.0;
uniform float frequency_uniform = 30.0;

uniform bool is_breath = false;
uniform float breath_speed = 0.368;
uniform float breath_freq = 0.021;

// Use local vertex coordinates for the effect
varying float local_vertex_x;
varying float local_vertex_y;

void vertex() {
	local_vertex_x = VERTEX.x;
	local_vertex_y = VERTEX.y;
}

void fragment() {
	float frequency = frequency_uniform;
	if (is_breath) {
		frequency = breath_freq * sin(TIME * breath_speed);
	}
	
	// Sample texture (TEXTURE is the node's texture by default)
	vec4 albedo_tex = texture(TEXTURE, UV);
	// If texture_albedo is assigned, we could use that instead or mix them
	// For this port, we'll stick to the original logic pattern
	
	// The original used world_vertex_x/y/z. In 2D we use x and y.
	// world_vertex_z is replaced by a combination or just ignored.
	float oh_no = cos(local_vertex_x * TIME * speed) + sin(local_vertex_y * TIME * speed);
	float oh_god = sin(local_vertex_y * TIME * speed) + cos(local_vertex_x * TIME * speed);
	float oh_feck = sin(local_vertex_y * TIME * speed) + cos(local_vertex_x * TIME * speed);
	
	vec3 trippy_color = vec3(
		sin(oh_no * frequency * TIME * speed),
		cos(oh_god * frequency * TIME * speed),
		tan(oh_feck * frequency * TIME * speed)
	);
	
	// Apply the trippy color to the texture color, masked by the original texture's alpha
	// This ensures the effect is strictly contained within the "original image" silhouette
	COLOR = vec4(trippy_color, albedo_tex.a * albedo.a);
	
	// Alpha scissor equivalent in 2D - ensures transparent areas are fully discarded
	if (albedo_tex.a < alpha_scissor_threshold) {
		discard;
	}
}
