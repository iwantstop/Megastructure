shader_type spatial;
render_mode unshaded, fog_disabled;

// Далёкая гора — цель пути. Рисуется силуэтом без тумана (иначе на таком расстоянии её не видно):
// низ растворяется в дымке, середина — тёмная скала, вершина над облаками освещена солнцем.

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 haze_color : source_color = vec3(0.5, 0.53, 0.57);
uniform vec3 rock_color : source_color = vec3(0.32, 0.33, 0.36);
uniform vec3 peak_color : source_color = vec3(0.95, 0.86, 0.72);
uniform float height = 2600.0;
uniform float cloud_level = 0.16;   // доля высоты, где проходит слой облаков

varying float h;

void vertex() {
	h = VERTEX.y / height + 0.5;
	float a = atan(VERTEX.z, VERTEX.x) / 6.28318 * 4.0;
	float n = texture(noise_tex, vec2(a, h * 3.0)).r;
	VERTEX.xz *= 0.7 + n * 0.6;  // рваный, неровный силуэт
}

void fragment() {
	float n = texture(noise_tex, UV * vec2(8.0, 4.0)).r;
	vec3 col = mix(haze_color, rock_color, 0.35 + 0.65 * smoothstep(0.0, 0.5, h));
	col = mix(col, peak_color, smoothstep(cloud_level + 0.15, cloud_level + 0.45, h + (n - 0.5) * 0.15));
	ALBEDO = col * (0.85 + 0.3 * n);
}
