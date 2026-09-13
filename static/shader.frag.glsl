#version 300 es

precision highp float;
uniform lowp usampler2D s;

in vec2 u;
in vec4 c[2];

out vec4 o;

void main() {
    vec2 d = vec2(textureSize(s, 0));

    uint y = texture(s, u).x;
    uint i = uint(fract(u.x * d.x) * 8.);

    uint b = (y >> i) & 1u;
    vec4 l = c[b];

    if (l.a == 0.) discard;
    o = l;
}
