shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

// Мазки кисти на самих поверхностях (а не узором поверх экрана).
// Полноэкранный проход: по глубине восстанавливаем точку мира, по нормали — плоскость поверхности,
// и рисуем короткие штрихи прямо на ней (в метрах мира) — они «приклеены» к бетону, скале, стенам
// и двигаются вместе с ними. Где поверхности нет (небо, облака-купол) — штрихов нет.
// Размер штриха растёт с расстоянием ступенями ×2 (с плавным переходом) — и вблизи, и вдали
// штрих остаётся в несколько пикселей, как мазок на холсте.
// Режим blend_mul: проход только чуть затемняет/высветляет то, что уже нарисовано, поэтому
// прозрачное (голограммы, дождь, неон) не теряется.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;
uniform float amount = 0.13;        // сила мазков (доля яркости)
uniform float stroke_near = 0.16;   // длина штриха вблизи (на 6 м), м — шире фильтра Кувахары, иначе он их сглаживает
uniform float aspect = 3.0;         // штрих длиннее, чем шире
uniform float fade_start = 30.0;    // до этого расстояния мазки в полную силу, м
uniform float fade_end = 140.0;     // к этому расстоянию мазки исчезают — вдали силуэты в тумане чистые

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Штрихи на плоскости: ряды смещены, у каждого ряда своё направление из 4 (крест-накрест, как кистью).
float strokes(vec2 p, float size) {
	vec2 q = p / size;
	float row = floor(q.y * aspect);
	float angle = (hash(vec2(row, 7.0)) - 0.5) * 0.7;  // штрихи немного вразнобой
	vec2 dir = vec2(cos(angle), sin(angle));
	vec2 r = vec2(dot(q, dir), dot(q, vec2(-dir.y, dir.x)));
	float lane = floor(r.y * aspect);
	r.x += hash(vec2(lane, 3.0));
	return hash(vec2(floor(r.x), lane)) - 0.5;
}

// Трипланар: проекция на ту плоскость, к которой поверхность ближе всего.
float surface_strokes(vec3 world, vec3 n, float size) {
	vec3 a = abs(n);
	vec2 p = a.y > max(a.x, a.z) ? world.xz : (a.x > a.z ? world.zy : world.xy);
	return strokes(p, size);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);  // квадрат на весь экран
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	if (depth <= 0.0) {
		ALBEDO = vec3(1.0);  // небо — без мазков
	} else {
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vec3 view_pos = view.xyz / view.w;
		vec3 world = (INV_VIEW_MATRIX * vec4(view_pos, 1.0)).xyz;
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(texture(normal_texture, SCREEN_UV).xyz * 2.0 - 1.0, 0.0)).xyz);
		float dist = length(view_pos);
		// Ступень размера по расстоянию и плавный переход между соседними ступенями.
		float level = log2(max(dist / 6.0, 1.0));
		float step0 = floor(level);
		float size0 = stroke_near * exp2(step0);
		float s = mix(surface_strokes(world, n, size0), surface_strokes(world, n, size0 * 2.0), fract(level));
		float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
		ALBEDO = vec3(1.0 + s * amount * 2.0 * fade);
	}
	ALPHA = 1.0;
}
