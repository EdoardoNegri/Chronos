// The graveyard on the table: a round vortex that turns slowly, dark in the middle with purple
// arms spiralling in and a gold rim. `glow` brightens it while the mouse is over it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 core : source_color = vec4(0.02, 0.0, 0.06, 1.0);
uniform vec4 arm : source_color = vec4(0.5, 0.32, 0.92, 1.0);
uniform vec4 rim : source_color = vec4(0.95, 0.8, 0.45, 1.0);
uniform float speed = 1.0;
uniform float glow = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	// Arms that wind tighter toward the middle and turn with time.
	float arms = sin(angle * 3.0 + 9.0 * sqrt(r) - TIME * speed * 2.5);
	float brightness = smoothstep(0.1, 1.0, arms) * (1.0 - r) + 0.2 * (1.0 - r);
	vec3 color = mix(core.rgb, arm.rgb, clamp(brightness * (1.0 + glow), 0.0, 1.0));
	color = mix(color, rim.rgb, smoothstep(0.86, 0.98, r) * (0.55 + 0.45 * glow));
	ALBEDO = color;
	ALPHA = 1.0 - smoothstep(0.97, 1.0, r);
}
