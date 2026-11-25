shader_type canvas_item;

uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.5;

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 grid_uv = floor(UV * screen_size / pixel_size) * pixel_size / screen_size;
	COLOR = texture(TEXTURE, grid_uv);
}
