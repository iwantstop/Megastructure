shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Слой туч над городом. Снизу — свинцовые, сверху — белые, освещённые солнцем.
// Медленно плывут; в разрывах иногда видно то, что выше.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 under_color : source_color = vec3(0.3, 0.32, 0.36);
uniform vec3 top_color : source_color = vec3(0.96, 0.94, 0.9);
uniform float coverage = 0.8;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform float soft_edge = 60.0;    // облака мягко тают у склонов горы (и у башен), а не режутся о них

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = texture(noise_tex, p * 0.00025 + TIME * vec2(0.002, 0.001)).r * 0.65
		+ texture(noise_tex, p * 0.0011 - TIME * vec2(0.003, 0.0)).r * 0.35;
	ALBEDO = FRONT_FACING ? top_color * (0.85 + 0.15 * n) : under_color * (0.75 + 0.45 * n);
	ALPHA = smoothstep(1.0 - coverage - 0.15, 1.0 - coverage + 0.15, n);
	// Мягкое касание: чем ближе за облаком поверхность (склон горы), тем прозрачнее облако — оно будто
	// обтекает гору, а не пронзает её ровной линией.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float gap = -behind.z / behind.w + VERTEX.z;   // сколько метров от облака до того, что за ним
	ALPHA *= smoothstep(0.0, soft_edge, gap);
}
