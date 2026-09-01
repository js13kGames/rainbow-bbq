#version 300 es

precision highp float;

// Sprite position, aligned to top-left screen position
layout(location = 0) in vec4 a_pos;

// Texture coordinates
layout(location = 1) in vec2 a_uv;

// Sprite background color in RGBA
layout(location = 2) in vec4 a_back;

// Sprite foreground color in RGBA
layout(location = 3) in vec4 a_fore;

out vec2 v_uv;
out vec4 v_color[2];

void main() {
    v_color[0] = a_back;
    v_color[1] = a_fore;
    v_uv = a_uv;
    gl_Position = a_pos;
}
