shader_type spatial;
render_mode unshaded;

// Экран телевизора: помехи, полосы развёртки — и иногда в шуме проступает тёмный силуэт
// девушки с каре, будто кто-то стоит по ту сторону стекла.

uniform float silhouette = 1.0;    // 0 — только помехи

float rand(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 d = (p - c) / r;
	return 1.0 - smoothstep(0.85, 1.0, dot(d, d));
}

void fragment() {
	vec2 uv = UV;
	float noise = rand(floor(uv * vec2(180.0, 100.0)) + floor(TIME * 24.0) * 7.31);
	float scan = 0.75 + 0.25 * sin(uv.y * 400.0 - TIME * 30.0);
	float roll = smoothstep(0.0, 0.08, abs(fract(uv.y - TIME * 0.11) - 0.5));
	// Силуэт: голова с каре и плечи, проявляется медленно и редко.
	float shape = max(ellipse(uv, vec2(0.5, 0.36), vec2(0.075, 0.1)), ellipse(uv, vec2(0.5, 0.33), vec2(0.1, 0.085)));
	shape = max(shape, ellipse(uv, vec2(0.5, 0.8), vec2(0.22, 0.25)));
	float appear = smoothstep(0.55, 1.0, sin(TIME * 0.23) * 0.5 + 0.5) * silhouette;
	float v = noise * scan * (0.55 + 0.45 * roll) * (1.0 - shape * appear * 0.85);
	ALBEDO = vec3(v) * vec3(0.75, 0.85, 1.0) * 1.6;  // unshaded: свечение (EMISSION) игнорируется — только ALBEDO
}
