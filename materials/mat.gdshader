shader_type spatial;

// Competition mat: combat area in one color, safety border in another, a seam
// every tile, and two start marks. Drawn in world space, so it lines up with
// Arena.combat_size wherever the mat mesh sits.

uniform vec3 combat_color : source_color = vec3(0.16, 0.36, 0.64);
uniform vec3 safety_color : source_color = vec3(0.96, 0.74, 0.24);
uniform vec3 mark_color : source_color = vec3(0.97, 0.96, 0.92);
uniform float combat_half = 4.0;
uniform float tile = 1.0;
uniform float seam_width = 0.008;
uniform float start_mark_z = 0.9;

varying vec3 world_pos;
varying float top;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	top = step(0.5, NORMAL.y);
}

float box_mask(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	float dist = max(d.x, d.y);
	float aa = fwidth(dist);
	return 1.0 - smoothstep(-aa, aa, dist);
}

void fragment() {
	vec2 p = world_pos.xz;
	float inside = box_mask(p, vec2(combat_half));
	vec3 c = mix(safety_color, combat_color, inside * top);

	vec2 f = abs(fract(p / tile + 0.5) - 0.5) * tile;
	float d = min(f.x, f.y);
	float aa = fwidth(d);
	float seam = (1.0 - smoothstep(seam_width - aa, seam_width + aa, d)) * top;
	c *= mix(1.0, 0.8, seam);

	float marks = box_mask(vec2(p.x, abs(p.y) - start_mark_z), vec2(0.3, 0.035)) * top;
	c = mix(c, mark_color, marks);

	c *= mix(0.78, 1.0, top);
	ALBEDO = c;
	ROUGHNESS = mix(0.5, 0.75, seam);
	SPECULAR = 0.35;
}
