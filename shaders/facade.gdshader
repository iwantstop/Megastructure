shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Фасад небоскрёба: сетка окон по этажам, часть окон горит тёплым или холодным светом,
// между некоторыми колонками — глухие вертикальные рёбра. Считается от мировых координат,
// поэтому окна не нужно строить геометрией. Вдали сетка плавно сливается в средний тон.

uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wall_color : source_color = vec3(0.35, 0.36, 0.38);
uniform vec3 glass_color : source_color = vec3(0.06, 0.08, 0.1);
uniform vec2 cell = vec2(3.0, 3.2);     // шаг окон: по горизонтали и высота этажа
uniform vec2 window = vec2(0.7, 0.55);  // доля окна в ячейке
uniform float fin_every = 0.0;          // каждая N-я колонка — глухое ребро, 0 — без рёбер
uniform float lit_chance = 0.12;
uniform vec3 lit_warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 lit_cool : source_color = vec3(0.55, 0.8, 1.0);
uniform float lit_energy = 2.0;
uniform float ground_floor = 3.6;       // ниже этой высоты окон нет — там магазины

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float stain = texture(noise_tex, vec2(wpos.x + wpos.z, wpos.y * 0.25) * 0.03).r;
	vec3 wall = wall_color * (0.75 + 0.5 * stain);

	float vertical = step(abs(n.y), 0.5);
	vec2 face = abs(n.x) > abs(n.z) ? wpos.zy : wpos.xy;
	vec2 c = face / cell;
	vec2 id = floor(c);
	vec2 f = fract(c);
	vec2 fw = fwidth(c);
	vec2 lo = (1.0 - window) * 0.5;
	vec2 m = smoothstep(lo - fw, lo + fw, f) * (1.0 - smoothstep(1.0 - lo - fw, 1.0 - lo + fw, f));
	float win = m.x * m.y * vertical * step(ground_floor, wpos.y);
	if (fin_every > 0.0 && mod(id.x, fin_every) < 0.5) {
		win = 0.0;
	}
	// Вдали, когда окна мельче пикселя, — средний тон вместо ряби.
	float far = smoothstep(0.25, 0.7, max(fw.x, fw.y));
	float avg = window.x * window.y * vertical * step(ground_floor, wpos.y);
	win = mix(win, avg, far);

	float side = floor(n.x * 2.0 + n.z * 3.0);
	float h = hash(id + side * 31.7);
	float lit = step(1.0 - lit_chance, h);
	lit = mix(lit, lit_chance, far);
	vec3 light = mix(lit_warm, lit_cool, step(0.5, hash(id * 1.7 + side)));

	ALBEDO = mix(wall, glass_color, win);
	ROUGHNESS = mix(0.85, 0.08, win);
	METALLIC = 0.3 * win;
	EMISSION = win * lit * light * lit_energy * (0.5 + 0.5 * hash(id * 3.1));
}
