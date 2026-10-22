shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Процедурный бетон: пятна, потёки, грязь у земли, панели со швами и рельеф.
// Всё считается от мировых координат, поэтому швов на стыках деталей нет.

uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.6);
uniform float variation = 0.3;       // крупные пятна разного тона
uniform vec3 tint_color : source_color = vec3(0.55, 0.5, 0.4);
uniform float tint_amount = 0.15;    // ржавые/землистые разводы
uniform float streaks = 0.5;         // вертикальные потёки на стенах
uniform float grime = 0.5;           // грязь у самой земли
uniform float panel_size = 0.0;      // 0 — без панелей
uniform float seam_width = 0.04;
uniform float seam_dark = 0.4;
uniform float roughness_value = 0.92;
uniform float bump = 1.0;
uniform float puddles = 0.0;         // лужи на горизонтальных поверхностях
uniform float brick_size = 0.0;      // длина кирпича в метрах, 0 — без кирпичной кладки
uniform vec3 mortar_color : source_color = vec3(0.55, 0.54, 0.5);
global uniform float rain_amount;    // 0..1 — сколько дождя (journey.gd): круги от капель в лужах

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float tri(vec3 p, vec3 w, float s) {
	return texture(noise_tex, p.zy * s).r * w.x
		+ texture(noise_tex, p.xz * s).r * w.y
		+ texture(noise_tex, p.xy * s).r * w.z;
}

float hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 hash2(vec2 c) {
	return fract(sin(vec2(dot(c, vec2(127.1, 311.7)), dot(c, vec2(269.5, 183.3)))) * 43758.5453);
}

// Круги от капель: в каждой клетке — свой, расходится и гаснет (как в лужах на крыше, puddles.gdshader).
float ripples(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 rnd = hash2(cell + o);
			float t = fract(TIME * 1.1 * (0.7 + rnd.y * 0.6) + rnd.x);
			float d = length(o + rnd - f);
			float r = t * 0.9;
			h += sin((d - r) * 40.0) * smoothstep(0.08, 0.0, abs(d - r)) * (1.0 - t) * (1.0 - t);
		}
	}
	return h;
}

// Следы капель на сухом бетоне: в каждой клетке время от времени падает капля — тёмная клякса сразу,
// потом подсыхает и тает. Возвращает 0..1 — насколько темнеет точка.
float drop_marks(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float m = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 rnd = hash2(cell + o + 17.0);
			float period = 2.2 + rnd.y * 2.5;                   // капля в эту клетку — раз в 2–5 с
			float t = fract(TIME / period + rnd.x) * period;    // секунд с момента падения
			float life = 1.0 - smoothstep(0.0, 1.6, t);         // подсыхает за ~1,6 с
			float d = length(o + rnd * 0.8 + 0.1 - f);
			float size = 0.07 + rnd.y * 0.08;
			m = max(m, smoothstep(size, size * 0.4, d) * life);
		}
	}
	return m;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	// Вдали мелкие детали плавно гасим — иначе они мерцают рябью.
	float far = smoothstep(15.0, 80.0, length(VERTEX));
	float fine = mix(tri(wpos, w, 0.4), 0.5, far);
	float mid = tri(wpos, w, 0.045);
	float big = tri(wpos, w, 0.005);

	vec3 col = base_color * (0.82 + 0.36 * fine);
	col *= 1.0 - variation * 0.5 + variation * big;
	col = mix(col, col * tint_color * 1.8, tint_amount * smoothstep(0.5, 0.8, mid));

	// Двумерные координаты в плоскости грани.
	vec2 face = abs(n.y) > 0.5 ? wpos.xz : (abs(n.x) > abs(n.z) ? wpos.zy : wpos.xy);
	float vertical = 1.0 - abs(n.y);

	float s = texture(noise_tex, vec2(face.x * 0.12, face.y * 0.006)).r;
	col *= 1.0 - streaks * vertical * smoothstep(0.45, 0.85, s) * 0.45;

	float seam = 0.0;
	if (panel_size > 0.0) {
		vec2 cell = face / panel_size;
		vec2 f = abs(fract(cell) - 0.5);
		// Ширина пикселя в долях панели: по ней сглаживаем край шва,
		// а когда панели становятся мельче пикселей — заменяем швы средним тоном.
		float px = max(fwidth(cell).x, fwidth(cell).y);
		float edge = 0.5 - seam_width / panel_size;
		seam = smoothstep(edge - px, edge + px, max(f.x, f.y));
		float fade = 1.0 - smoothstep(0.05, 0.25, px);
		float avg_seam = seam_width / panel_size * 2.0;
		seam = mix(avg_seam, seam, fade);
		col *= mix(0.98, 0.9 + 0.16 * hash(floor(cell)), fade);
		col *= 1.0 - seam * seam_dark;
	}

	// Кирпичная кладка со смещением рядов.
	if (brick_size > 0.0 && vertical > 0.5) {
		vec2 bc = face / vec2(brick_size, brick_size * 0.33);
		bc.x += 0.5 * mod(floor(bc.y), 2.0);
		vec2 bf = abs(fract(bc) - 0.5);
		float bpx = max(fwidth(bc).x, fwidth(bc).y);
		float mortar = max(smoothstep(0.44 - bpx, 0.44 + bpx, bf.x), smoothstep(0.38 - bpx, 0.38 + bpx, bf.y));
		float bfade = 1.0 - smoothstep(0.08, 0.3, bpx);
		vec3 brick = col * (0.78 + 0.44 * hash(floor(bc)));
		vec3 laid = mix(brick, mortar_color * (0.8 + 0.3 * fine), mortar);
		col = mix(mix(col, mortar_color, 0.2), laid, bfade);
		seam = max(seam, mortar * 0.6 * bfade);
	}

	col *= 1.0 - grime * vertical * (1.0 - smoothstep(0.0, 5.0, wpos.y)) * 0.45;

	// Лужи: тёмные, гладкие, отражают небо и постройки.
	float wet = 0.0;
	if (puddles > 0.0 && n.y > 0.9) {
		float pm = texture(noise_tex, wpos.xz * 0.04).r * 0.7 + texture(noise_tex, wpos.xz * 0.15).r * 0.3;
		wet = smoothstep(0.64 - puddles * 0.08, 0.7 - puddles * 0.08, pm);
		float damp = smoothstep(0.5 - puddles * 0.08, 0.66 - puddles * 0.08, pm);
		col *= 1.0 - damp * 0.15 - wet * 0.15;
	}

	// Дождь бьёт по лужам: круги расходятся (только вблизи — вдали они мерцали бы).
	vec3 drip = vec3(0.0);
	float ring_glow = 0.0;
	float rain_here = wet * rain_amount * (1.0 - smoothstep(12.0, 30.0, length(VERTEX)));
	if (rain_here > 0.01) {
		vec2 q = wpos.xz * 1.6;
		float h0 = ripples(q);
		drip = vec3(-(ripples(q + vec2(0.02, 0.0)) - h0), 0.0, -(ripples(q + vec2(0.0, 0.02)) - h0)) / 0.02 * 0.012 * rain_here;
		ring_glow = max(h0, 0.0) * rain_here;   // гребни кругов ловят отсвет неба и огней
	}

	// Сухие места темнеют пятнами от капель (в лужах вместо них — круги).
	float marks_here = rain_amount * (1.0 - wet) * step(0.9, n.y) * (1.0 - smoothstep(10.0, 25.0, length(VERTEX)));
	if (marks_here > 0.01) {
		col *= 1.0 - drop_marks(wpos.xz * 3.0) * 0.35 * marks_here;
	}

	ALBEDO = col;
	EMISSION = vec3(0.07, 0.075, 0.09) * ring_glow;
	ROUGHNESS = mix(roughness_value, 0.04, wet);

	// Рельеф из того же шума и швов (в лужах поверхность ровная).
	float h = (fine * 0.004 + mid * 0.01 - seam * 0.02) * (1.0 - wet);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * (1.0 - far));
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(drip, 0.0)).xyz);
}
