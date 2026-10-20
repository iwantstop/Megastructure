shader_type spatial;

// Паркет «неправильной» квартиры: доски ёлочкой по мировым координатам, каждая своего оттенка,
// и весь пол очень медленно ползёт в сторону телевизора — замечаешь, только если смотреть.

uniform vec2 flow = vec2(0.0, 0.03);   // куда и как быстро ползёт рисунок, м/с

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz + flow * TIME;
	vec2 board = vec2(0.12, 0.72);
	vec2 cell = floor(p / board + vec2(0.0, floor(p.x / board.x) * 0.5));
	vec2 f = fract(p / board + vec2(0.0, floor(p.x / board.x) * 0.5));
	float seam = smoothstep(0.0, 0.04, f.x) * smoothstep(1.0, 0.96, f.x) * smoothstep(0.0, 0.015, f.y) * smoothstep(1.0, 0.985, f.y);
	float tone = hash(cell);
	float grain = sin(p.y * 90.0 + tone * 20.0) * 0.04;
	vec3 wood = mix(vec3(0.22, 0.12, 0.06), vec3(0.36, 0.21, 0.11), tone) + grain;
	ALBEDO = wood * (0.55 + 0.45 * seam);
	ROUGHNESS = 0.45;
}
