shader_type canvas_item;

uniform bool thermal_enabled = false;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec4 c = texture(screen_texture, SCREEN_UV);
    if (!thermal_enabled) {
        COLOR = c;
    } else {
        // Luminancia relativa
        float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        
        // Paleta térmica infrarroja (Ironbow / FLIR)
        vec3 col;
        if (lum < 0.25) {
            col = mix(vec3(0.05, 0.05, 0.2), vec3(0.1, 0.2, 0.6), lum / 0.25);
        } else if (lum < 0.5) {
            col = mix(vec3(0.1, 0.2, 0.6), vec3(0.8, 0.1, 0.4), (lum - 0.25) / 0.25);
        } else if (lum < 0.75) {
            col = mix(vec3(0.8, 0.1, 0.4), vec3(1.0, 0.6, 0.0), (lum - 0.5) / 0.25);
        } else {
            col = mix(vec3(1.0, 0.6, 0.0), vec3(1.0, 1.0, 0.9), (lum - 0.75) / 0.25);
        }
        
        // Tinte de líneas de escaneo de sensor térmico
        float scanline = sin(SCREEN_UV.y * 350.0) * 0.04;
        COLOR = vec4(clamp(col + scanline, 0.0, 1.0), 1.0);
    }
}
