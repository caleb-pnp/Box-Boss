shader_type spatial;

uniform sampler2D color_ramp : source_color;
uniform float uv_scale : hint_range(1.0, 50.0) = 1.0;
uniform float uv_offset : hint_range(-1.0, 1.0) = 0.0;

void fragment() {
  float final_uv_x = (UV.x * uv_scale) + uv_offset;
  vec4 color = texture(color_ramp, vec2(final_uv_x, 0.5));
  ALBEDO = color.rgb;
}