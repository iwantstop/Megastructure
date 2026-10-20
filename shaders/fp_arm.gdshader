shader_type spatial;

// Рука героя «в кадре» из модели манекена: видна только одна рука — кисть в тёмной кожаной перчатке
// и рукав пальто до плеча; всё остальное тело отбрасывается. Граница — по оси X модели
// (в исходной Т-позе руки вытянуты вдоль X: правая — в минус, левая — в плюс).

uniform float side = 1.0;           // 1 — правая рука (x < 0), -1 — левая (x > 0)
uniform float keep_from = 0.25;     // ближе к телу этого |x| — не рисуем (туловище, голова, другая рука)
uniform float wrist = 0.70;         // дальше этого |x| — перчатка, ближе — рукав
uniform vec3 glove : source_color = vec3(0.06, 0.05, 0.045);
uniform vec3 sleeve : source_color = vec3(0.1, 0.1, 0.11);

varying float along;

void vertex() {
	along = -VERTEX.x * side;
}

void fragment() {
	if (along < keep_from) {
		discard;
	}
	float is_glove = smoothstep(wrist - 0.01, wrist + 0.01, along);
	ALBEDO = mix(sleeve, glove, is_glove);
	ROUGHNESS = mix(0.95, 0.5, is_glove);
	SPECULAR = mix(0.2, 0.45, is_glove);
}
