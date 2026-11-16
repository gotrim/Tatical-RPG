shader_type spatial;
render_mode specular_disabled;

// Terreno distante (LOD). A cor vem das cores por vértice (já em espaço linear).
// A iluminação é a mesma do ground_shader.gdshader, para a transição não "pular".

uniform vec4 fade_color : source_color = vec4(0.68, 0.82, 0.84, 1.0); // sky_horizon_color
uniform float fade_start = 190.0;
uniform float fade_end = 310.0;
// O ROUGHNESS é usado como máscara do outline (o chão usa 1.0).
uniform float outline_mask = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 camera_position = INV_VIEW_MATRIX[3].xyz;
	float fade = smoothstep(fade_start, fade_end, distance(world_pos.xz, camera_position.xz));
	ALBEDO = mix(COLOR.rgb, fade_color.rgb, fade);
	SPECULAR = 0.0;
	ROUGHNESS = outline_mask;
}

void light() {
	float light = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += light * (LIGHT_COLOR / PI) * max(ATTENUATION, 0.5);
}
