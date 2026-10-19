shader_type canvas_item;

// Экранный эффект нагрудной камеры: широкоугольный объектив с искажением по краям,
// цветовые разводы, виньетка, зерно и приглушённые цвета.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float distortion = 0.14;
uniform float aberration = 0.006;
uniform float vignette = 0.5;
uniform float grain = 0.055;
uniform float saturation = 0.88;

float rand(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r2 = dot(c, c);
	// Бочкообразное искажение: углы остаются на месте, центр чуть «выпуклый».
	vec2 uv = 0.5 + c * (1.0 + distortion * r2) / (1.0 + distortion * 0.5);

	vec2 shift = c * aberration * r2 * 4.0;
	vec3 col;
	col.r = texture(screen, uv + shift).r;
	col.g = texture(screen, uv).g;
	col.b = texture(screen, uv - shift).b;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col *= 1.0 - vignette * smoothstep(0.25, 1.0, r2 * 2.0);
	col += (rand(SCREEN_UV * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain;

	COLOR = vec4(col, 1.0);
}
