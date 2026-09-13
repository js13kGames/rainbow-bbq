#version 300 es

// Sprite position, aligned to top-left screen position
layout(location = 0) in vec4 p;

// Texture coordinates
layout(location = 1) in vec2 v;

// Sprite background color in RGBA
layout(location = 2) in vec4 b;

// Sprite foreground color in RGBA
layout(location = 3) in vec4 f;

out vec2 u;
out vec4 c[2];

void main() {
    c[0] = b;
    c[1] = f;
    u = v;
    gl_Position = p;
}
