shader_type spatial;
render_mode depth_prepass_alpha, depth_draw_opaque, cull_disabled;

uniform sampler2D grass_texture : source_color, filter_nearest;
uniform vec3 grass_color : source_color = vec3(1.0);
uniform float wind_speed = 3.0;
uniform float wind_strength = 0.15;

varying vec3 base_world_pos;
varying vec4 biome_tint;

void vertex() {
	base_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	biome_tint = INSTANCE_CUSTOM;

	float stepped_time = floor(TIME * wind_speed) / wind_speed;
	float sway = sin(stepped_time * 4.0 + base_world_pos.x + base_world_pos.z)
		* wind_strength;
	VERTEX.y += 0.375;
	VERTEX.x += sway * (1.0 - UV.y);

	vec3 model_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * model_scale.x,
		INV_VIEW_MATRIX[1] * model_scale.y,
		INV_VIEW_MATRIX[2] * model_scale.z,
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec4 tex = texture(grass_texture, UV);
	if (tex.a < 0.5) {
		discard;
	}

	ALBEDO = tex.rgb * grass_color * biome_tint.rgb;
	ALPHA = tex.a * biome_tint.a;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void light() {
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(base_world_pos, 1.0)).xyz;
	float NdotL = dot(NORMAL, LIGHT);
	float toon_light = smoothstep(0.0, 0.05, NdotL);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * toon_light;
}
