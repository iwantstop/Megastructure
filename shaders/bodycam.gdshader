shader_type canvas_item;

// Экранный эффект поверх 3D:
// 1. Живопись — фильтр Кувахары: кадр распадается на мазки-пятна, как масло
//    (стиль «Аркейна»). Края остаются чёткими, плоскости становятся пятнами краски.
// 2. Гамма зоны — кадр почти одноцветный (город — холодная сталь, мост — сирень, гора — янтарь,
//    над облаками — золото), но яркие насыщенные пятна (неон, огни) сохраняют свой цвет — акценты.
// 3. Нагрудная камера: широкоугольное искажение по краям, цветовые разводы, виньетка, зерно.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float distortion = 0.14;
uniform float aberration = 0.006;
uniform float vignette = 0.5;
uniform float grain = 0.055;
uniform float saturation = 0.88;

uniform float paint = 1.0;                  // 0 — обычная картинка, 1 — живопись
uniform int paint_radius : hint_range(1, 6) = 3;
uniform float paint_scale = 2.0;            // шаг выборки в пикселях: мазок крупнее при той же цене
uniform vec3 grade_tint = vec3(0.55, 0.68, 0.88);
uniform float grade_amount : hint_range(0.0, 1.0) = 0.6;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float rand(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

// Классическая Кувахара: из четырёх квадрантов вокруг точки берём средний цвет того,
// где разброс яркости меньше всего — получается плоское пятно «краски» с чётким краем.
vec3 kuwahara(vec2 uv, vec2 px) {
	vec3 mean[4];
	float best = 1e9;
	vec3 result = vec3(0.0);
	for (int q = 0; q < 4; q++) {
		vec2 dir = vec2(q % 2 == 0 ? -1.0 : 1.0, q < 2 ? -1.0 : 1.0);
		vec3 sum = vec3(0.0);
		float sum_l = 0.0;
		float sum_l2 = 0.0;
		float n = 0.0;
		for (int y = 0; y <= paint_radius; y++) {
			for (int x = 0; x <= paint_radius; x++) {
				vec3 c = textureLod(screen, uv + vec2(float(x), float(y)) * dir * px, 1.0).rgb;  // половинное разрешение — мягче, крупнее и дешевле
				float l = dot(c, LUMA);
				sum += c;
				sum_l += l;
				sum_l2 += l * l;
				n += 1.0;
			}
		}
		vec3 m = sum / n;
		float variance = sum_l2 / n - (sum_l / n) * (sum_l / n);
		if (variance < best) {
			best = variance;
			result = m;
		}
	}
	return result;
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r2 = dot(c, c);
	// Бочкообразное искажение: углы остаются на месте, центр чуть «выпуклый».
	vec2 uv = 0.5 + c * (1.0 + distortion * r2) / (1.0 + distortion * 0.5);

	vec3 base = texture(screen, uv).rgb;
	vec3 col = base;
	if (paint > 0.0) {
		col = mix(base, kuwahara(uv, SCREEN_PIXEL_SIZE * paint_scale), paint);
	}

	// Цветовые разводы по краям — поверх «краски».
	vec2 shift = c * aberration * r2 * 4.0;
	col.r += texture(screen, uv + shift).r - base.r;
	col.b += texture(screen, uv - shift).b - base.b;

	// Гамма зоны: почти одноцветный кадр, но насыщенные яркие пятна остаются акцентами.
	float luma = dot(col, LUMA);
	float sat = (max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b))) / max(max(col.r, max(col.g, col.b)), 1e-3);
	vec3 graded = grade_tint * (luma / max(dot(grade_tint, LUMA), 1e-3));
	float accent = smoothstep(0.2, 0.5, sat) * smoothstep(0.1, 0.3, luma);
	col = mix(col, graded, grade_amount * paint * (1.0 - accent * 0.95));

	luma = dot(col, LUMA);
	col = mix(vec3(luma), col, saturation);
	col *= 1.0 - vignette * smoothstep(0.25, 1.0, r2 * 2.0);
	col += (rand(SCREEN_UV * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain * (1.0 - paint * 0.5);  // у живописи зерно мягче

	COLOR = vec4(col, 1.0);
}
