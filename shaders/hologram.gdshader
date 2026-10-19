shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Голограмма: светящаяся, полупрозрачная, с бегущими полосами развёртки и мерцанием.

uniform vec3 color : source_color = vec3(0.2, 0.8, 1.0);
uniform float intensity = 3.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scan = 0.6 + 0.4 * sin(wpos.y * 14.0 - TIME * 4.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 23.0) * sin(TIME * 7.3);
	float rim = 0.35 + 0.9 * (1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))));
	float border = max(max(step(UV.x, 0.015), step(0.985, UV.x)), max(step(UV.y, 0.01), step(0.99, UV.y)));
	ALBEDO = color * intensity * scan * flicker * (rim + border * 2.0);
	ALPHA = 0.5;
}
