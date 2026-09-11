#version 440

// Rising heat haze — slow vertical shimmer.
//
// SAMPLING pack shader: it reads the window through `source` and MOVES those
// pixels, which is what makes text appear to ripple rather than merely change
// colour. Declared with "samples": true in its .json so the host attaches a
// live capture; without that the sampler would be empty.
//
// @param p1 Amount 0.0 0.02 0.006
// @param p2 Detail 4.0 40.0 16.0
// @param p3 Rise 0.0 3.0 1.1
// @param p4 Width 0.0 2.0 0.7

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
    float t = ubuf.time * ubuf.p3;
    // Two waves at different rates so the shimmer never visibly repeats.
    float n = sin(uv.y * ubuf.p2 - t * 2.0) * 0.6
            + sin(uv.y * ubuf.p2 * 1.7 - t * 3.1) * 0.4;
    float d = n * ubuf.p1 * ubuf.strength * 6.0 * mix(1.0, uv.y, ubuf.p4);
    vec4 col = texture(source, clamp(uv + vec2(d, 0.0), 0.0, 1.0));
    fragColor = col * coverage(uv) * ubuf.qt_Opacity;
}
