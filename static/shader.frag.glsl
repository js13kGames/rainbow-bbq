#version 300 es

precision highp float;
precision highp int;
uniform lowp usampler2D s;

in vec2 v_uv;
in vec4 v_color[2];

out vec4 o_color;

void main() {
    vec2 tex_size = vec2(textureSize(s, 0));
    uint byte = texture(s, v_uv).x;

    uint bit_idx = uint(fract(v_uv.x * tex_size.x) * 8.);

    uint bit = (byte >> bit_idx) & 1u;

    o_color = v_color[bit];
}
