shader_type canvas_item;

uniform float body_alpha : hint_range(0.0, 1.0) = 0.38;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.20;
uniform float text_darkness : hint_range(0.0, 1.0) = 0.55;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Your icon only carries information in alpha (RGB is flat black
    // everywhere, glyph included) — so "is this pixel text" has to come
    // from alpha, not from RGB darkness.
    float is_text = smoothstep(text_darkness - 0.15, text_darkness + 0.15, tex.a);

    // --------------------------------------------------
    // PLASTIC BODY — now drawn across the whole button,
    // not just where the source texture happens to have alpha.
    // --------------------------------------------------
    float edge = min(
        min(UV.x, 1.0 - UV.x),
        min(UV.y, 1.0 - UV.y)
    );
    float edge_glow = 1.0 - smoothstep(0.02, 0.15, edge);
    float top_highlight = 1.0 - smoothstep(0.0, 0.55, UV.y);

    vec3 plastic_color = vec3(0.65, 0.65, 0.65);
    plastic_color += vec3(top_highlight * highlight_strength);
    plastic_color += vec3(edge_glow * 0.18);

    float plastic_alpha = mix(body_alpha, edge_alpha, edge_glow);

    // Keep the glyph dark & fully opaque on top of the plastic body.
    vec3 final_color = mix(plastic_color, tex.rgb, is_text);
    float final_alpha = mix(plastic_alpha, 1.0, is_text);

    COLOR = vec4(final_color, final_alpha);
}