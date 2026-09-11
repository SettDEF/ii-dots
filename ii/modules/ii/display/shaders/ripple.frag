#version 440

// Radial ripples spreading from the centre, like a dropped stone.
//
// SAMPLING pack shader: it reads the window through `source` and MOVES those
// pixels, which is what makes text appear to ripple rather than merely change
// colour. Declared with "samples": true in its .json so the host attaches a
// live capture; without that the sampler would be empty.
//
// @param p1 Amount 0.0 0.03 0.010
// @param p2 Rings 4.0 80.0 34.0
// @param p3 Speed 0.0 6.0 2.4
// @param p4 Falloff 0.0 3.0 1.2

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;
    float strength;
    float aspect;
    float radius;
    float pxh;
    float p1;
    float p2;
    float p3;
    float p4;
    vec4  c1;
    vec4  c2;
} ubuf;

// Rounded-rect coverage, so the effect stops exactly where the window does.
float coverage(vec2 uv) {
    vec2 S = vec2(ubuf.pxh * ubuf.aspect, ubuf.pxh);
    vec2 q = abs(uv * S - S * 0.5) - (S * 0.5 - vec2(ubuf.radius));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - ubuf.radius;
    return 1.0 - smoothstep(-1.0, 1.0, d);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 c = uv - 0.5;
    c.x *= ubuf.aspect;
    float r = length(c);
    // Falloff keeps the centre calm and the motion out at the edges, which
    // looks like a wave travelling rather than the whole window vibrating.
    float wave = sin(r * ubuf.p2 - ubuf.time * ubuf.p3) * ubuf.p1
               * exp(-r * ubuf.p4);
    vec2 dir = r > 0.0001 ? c / r : vec2(0.0);
    vec4 col = texture(source, clamp(uv + dir * wave * ubuf.strength * 6.0, 0.0, 1.0));
    fragColor = col * coverage(uv) * ubuf.qt_Opacity;
}
