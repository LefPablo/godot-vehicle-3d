shader_type spatial;
// World-space grid so speed and bump shapes are easy to read while driving.

uniform vec3 base_color : source_color = vec3(0.36, 0.4, 0.34);
uniform vec3 line_color : source_color = vec3(0.26, 0.29, 0.25);
uniform float grid_size = 2.0;
uniform float line_width = 0.05;
uniform float roughness_value = 0.9;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.6 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	vec2 cell = abs(fract(uv / grid_size - 0.5) - 0.5) * grid_size;
	float line = 1.0 - smoothstep(line_width * 0.6, line_width, min(cell.x, cell.y));
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = roughness_value;
}
