shader_type canvas_item;

// Simple radial vignette. "intensity" is driven at runtime from the player
// script so it can darken further as the enemy gets closer.
uniform float intensity : hint_range(0.0, 1.0) = 0.25;
uniform float radius : hint_range(0.0, 1.5) = 0.75;
uniform float softness : hint_range(0.01, 1.5) = 0.55;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// Scale so the corners of the screen reach ~1.0 regardless of aspect ratio.
	float dist = length(uv) * 1.414213;
	float edge = smoothstep(radius - softness, radius, dist);
	COLOR = vec4(vignette_color.rgb, edge * intensity);
}
