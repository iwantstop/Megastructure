shader_type spatial;

// Обои «неправильной» квартиры в пещере: узор медленно течёт и плывёт по цвету,
// а сама стена едва заметно дышит. Узор — по мировым координатам (у склеенной геометрии нет UV).

uniform float breathe = 0.015;     // насколько стена «дышит», м
uniform float brightness = 0.32;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX += NORMAL * sin(TIME * 0.7 + wpos.y * 1.3 + wpos.x * 0.4) * breathe;
}

void fragment() {
	vec3 n = abs(wnorm);
	vec2 p = n.x > n.z ? wpos.zy : wpos.xy;
	float warp = sin(p.y * 2.0 + TIME * 0.35) * 0.25 + sin(p.y * 0.7 - TIME * 0.21) * 0.15;
	float stripes = sin((p.x + warp) * 9.0) * 0.5 + 0.5;
	float flowers = sin(p.x * 18.0 + warp * 3.0) * sin(p.y * 12.0 - TIME * 0.2);
	float pattern = smoothstep(0.35, 0.9, stripes) * 0.6 + smoothstep(0.55, 0.95, flowers) * 0.4;
	// Цвет медленно уплывает по кругу оттенков — то бордовый, то болезненно-зелёный.
	vec3 hue = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + TIME * 0.025 + pattern * 0.35));
	ALBEDO = mix(vec3(0.16, 0.05, 0.06), hue, 0.55 + pattern * 0.3) * brightness;
	ROUGHNESS = 0.8;
}
