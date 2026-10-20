shader_type canvas_item;

// Экранный эффект поверх 3D:
// 1. Живопись — фильтр Кувахары: детали собираются в мелкие пятна краски с чёткими краями,
//    поверх — фактура кисти: короткие штрихи вдоль контуров; лёгкая резкость возвращает
//    окнам, неону и разметке чёткость (стиль «Аркейна», но без «мыла»).
// 2. Гамма зоны — кадр почти одноцветный (город — холодная сталь, мост — сирень, гора — янтарь,
//    над облаками — золото), но яркие насыщенные пятна (неон, огни) сохраняют свой цвет — акценты.
// 3. Нагрудная камера: широкоугольное искажение по краям, цветовые разводы, виньетка, зерно.
// 4. Припадок (glitch): кадр рвётся полосами, расслаивается цвет, помехи блоками, негатив, чернота.

uniform sampler2D screen : hint_screen_texture, filter_linear;  // без мипмапов — их пересчёт каждый кадр стоит FPS
uniform float distortion = 0.14;
uniform float aberration = 0.006;
uniform float vignette = 0.5;
uniform float grain = 0.055;
uniform float saturation = 0.88;

uniform float paint = 0.7;                  // 0 — обычная картинка, 1 — только пятна краски
uniform int paint_radius : hint_range(1, 6) = 2;
uniform float paint_scale = 1.0;            // шаг выборки в пикселях: 1 — мелкий, детальный мазок
uniform float stroke_amount = 0.07;         // сила фактуры кисти (доля яркости)
uniform float stroke_length = 7.0;          // длина штриха, px
uniform float stroke_width = 2.0;           // ширина штриха, px
uniform float sharpen = 0.6;                // возврат резкости после Кувахары
uniform vec3 grade_tint = vec3(0.55, 0.68, 0.88);
uniform float grade_amount : hint_range(0.0, 1.0) = 0.6;

uniform float glitch = 0.0;                 // 0 — спокойно, 1 — припадок в полную силу
uniform float glitch_seed = 0.0;            // меняется рывками — каждый «срыв» кадра другой
uniform float glitch_invert = 0.0;          // 1 — на миг негатив
uniform float blackout = 0.0;               // 1 — чернота (в ней героя переносят)

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float rand(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

// Классическая Кувахара: из четырёх квадрантов вокруг точки берём средний цвет того,
// где разброс яркости меньше всего — получается пятно «краски» с чётким краем.
vec3 kuwahara(vec2 uv, vec2 px) {
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
				vec3 c = textureLod(screen, uv + vec2(float(x), float(y)) * dir * px, 0.0).rgb;
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

// Фактура кисти: короткие штрихи, повёрнутые вдоль контура (поперёк градиента яркости).
// Направление округляется до 8 положений — штрихи ложатся ровными «полосами» мазков.
float brush(vec2 pixel, vec2 gradient) {
	float angle = length(gradient) > 0.004 ? atan(gradient.y, gradient.x) + 1.5708 : 0.6;
	angle = round(angle / 0.3927) * 0.3927;
	vec2 along = vec2(cos(angle), sin(angle));
	vec2 p = vec2(dot(pixel, along), dot(pixel, vec2(-along.y, along.x)));
	float row = floor(p.y / stroke_width);
	p.x += rand(vec2(row, angle)) * stroke_length;  // ряды сдвинуты — штрихи не выстраиваются в сетку
	vec2 cell = floor(vec2(p.x / stroke_length, row));
	return rand(cell + angle * 7.0) - 0.5;
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r2 = dot(c, c);
	// Бочкообразное искажение: углы остаются на месте, центр чуть «выпуклый».
	vec2 uv = 0.5 + c * (1.0 + distortion * r2) / (1.0 + distortion * 0.5);

	// Припадок: полосы кадра срываются вбок, куски экрана переставляются блоками.
	if (glitch > 0.0) {
		float band = floor(uv.y * 28.0 + glitch_seed * 13.0);
		if (rand(vec2(band, glitch_seed)) < glitch * 0.55) {
			uv.x += (rand(vec2(glitch_seed, band)) - 0.5) * 0.18 * glitch;
		}
		vec2 block = floor(uv * vec2(14.0, 8.0));
		if (rand(block + glitch_seed * 3.1) < glitch * 0.18) {
			uv += (vec2(rand(block * 1.7 + glitch_seed), rand(block * 2.3 - glitch_seed)) - 0.5) * 0.12 * glitch;
		}
		uv = clamp(uv, vec2(0.0), vec2(1.0));
	}

	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 base = texture(screen, uv).rgb;
	vec3 col = base;
	if (paint > 0.0) {
		// Соседи по кресту: градиент для направления штрихов и среднее для резкости.
		vec3 l = texture(screen, uv - vec2(px.x, 0.0)).rgb;
		vec3 r = texture(screen, uv + vec2(px.x, 0.0)).rgb;
		vec3 d = texture(screen, uv - vec2(0.0, px.y)).rgb;
		vec3 u = texture(screen, uv + vec2(0.0, px.y)).rgb;
		vec2 gradient = vec2(dot(r - l, LUMA), dot(u - d, LUMA));
		col = mix(base, kuwahara(uv, px * paint_scale), paint);
		col += (col - (l + r + d + u) * 0.25) * sharpen;  // края, окна и неон остаются острыми
		col *= 1.0 + brush(uv / px, gradient) * stroke_amount * 2.0;
	}

	// Цветовые разводы по краям — поверх «краски»; в припадке — сильное расслоение.
	vec2 shift = c * aberration * r2 * 4.0 + vec2(0.012 * glitch, 0.0);
	col.r += texture(screen, uv + shift).r - base.r;
	col.b += texture(screen, uv - shift).b - base.b;

	// Гамма зоны: почти одноцветный кадр, но насыщенные яркие пятна остаются акцентами.
	float luma = dot(col, LUMA);
	float sat = (max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b))) / max(max(col.r, max(col.g, col.b)), 1e-3);
	vec3 graded = grade_tint * (luma / max(dot(grade_tint, LUMA), 1e-3));
	float accent = smoothstep(0.2, 0.5, sat) * smoothstep(0.1, 0.3, luma);
	col = mix(col, graded, grade_amount * min(paint * 1.25, 1.0) * (1.0 - accent * 0.95));

	luma = dot(col, LUMA);
	col = mix(vec3(luma), col, saturation);
	col *= 1.0 - vignette * smoothstep(0.25, 1.0, r2 * 2.0);
	col += (rand(SCREEN_UV * 1000.0 + fract(TIME) * 37.0) - 0.5) * (grain * (1.0 - paint * 0.5) + glitch * 0.25);

	col = mix(col, vec3(1.0) - col, glitch_invert);
	col *= 1.0 - blackout;
	COLOR = vec4(col, 1.0);
}
