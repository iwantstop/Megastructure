shader_type spatial;
// Лужи на мокрой крыше (вступление): форма — из шума (рваные края, мелкие лужицы), вокруг — тёмный мокрый ореол;
// в луже вода гладкая как зеркало (резкие блики огней), по ней от капель расходятся круги.
// Плоскость лежит над бетоном; тени не принимает (она тоньше запаса теней — иначе всегда «в тени»).
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

uniform sampler2D shape_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;
uniform float coverage = 0.63;      // меньше — больше луж
uniform vec3 wet_color : source_color = vec3(0.26, 0.265, 0.29);
uniform vec3 horizon : source_color = vec3(0.32, 0.34, 0.4);   // что отражает вода под скользящим взглядом: дымка у горизонта
uniform float ripple_density = 1.6; // кругов на метр
uniform float ripple_speed = 1.1;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 c) {
	return fract(sin(vec2(dot(c, vec2(127.1, 311.7)), dot(c, vec2(269.5, 183.3)))) * 43758.5453);
}

// Высота ряби: в каждой клетке — свой круг от капли, расходится и гаснет.
float ripples(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 rnd = hash2(cell + o);
			float t = fract(TIME * ripple_speed * (0.7 + rnd.y * 0.6) + rnd.x);
			float d = length(o + rnd - f);
			float r = t * 0.9;   // радиус круга
			float wave = sin((d - r) * 40.0) * smoothstep(0.08, 0.0, abs(d - r));
			h += wave * (1.0 - t) * (1.0 - t);
		}
	}
	return h;
}

void fragment() {
	vec2 p = wpos.xz;
	float shape = texture(shape_noise, p * 0.03).r;
	float detail = texture(detail_noise, p * 0.35).r;
	float m = shape + (detail - 0.5) * 0.12;                 // рваный край
	float wet = smoothstep(coverage - 0.12, coverage - 0.02, m);   // мокрый ореол
	float pool = smoothstep(coverage - 0.01, coverage + 0.015, m);  // сама вода

	// Рябь — нормаль из разностей высоты.
	vec2 q = p * ripple_density;
	float e = 0.02;
	float h0 = ripples(q);
	float hx = ripples(q + vec2(e, 0.0));
	float hz = ripples(q + vec2(0.0, e));
	vec3 n_world = normalize(vec3(-(hx - h0) / e * 0.012 * pool, 1.0, -(hz - h0) / e * 0.012 * pool));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Отражение: под скользящим взглядом вода зеркалит светлую дымку горизонта (Френель), рябь его дробит.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = horizon * fresnel * pool * (0.8 + h0 * 0.6);
	ALBEDO = wet_color * mix(1.0, 0.6, pool);
	ROUGHNESS = mix(0.55, 0.03, pool);
	SPECULAR = mix(0.4, 0.9, pool);
	METALLIC = 0.0;
	ALPHA = max(wet * 0.55, pool * 0.9);
}
