#version 440

// Horizontal slice tearing with chroma split — a broken signal.
//
// SAMPLING pack shader: it reads the window through `source` and MOVES those
// pixels, which is what makes text appear to ripple rather than merely change
// colour. Declared with "samples": true in its .json so the host attaches a
// live capture; without that the sampler would be empty.
//
// @param p1 Tear 0.0 0.06 0.018
// @param p2 Slices 4.0 60.0 24.0
// @param p3 Rate 0.0 12.0 5.0
// @param p4 Chroma 0.0 0.02 0.005

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
    // Quantise y into slices, then offset each by a value that only changes
    // when its slice index does — that stepping is what reads as "digital".
    float slice = floor(uv.y * ubuf.p2);
    float seed = fract(sin(slice * 43.7 + floor(ubuf.time * ubuf.p3) * 12.9898) * 43758.5453);
    float off = (seed - 0.5) * ubuf.p1 * ubuf.strength * 4.0;
    vec2 suv = clamp(vec2(uv.x + off, uv.y), 0.0, 1.0);
    // Sample the channels apart so edges fringe like a mistimed signal.
    float ca = ubuf.p4 * ubuf.strength * 3.0;
    vec4 col;
    col.r = texture(source, clamp(suv + vec2(ca, 0.0), 0.0, 1.0)).r;
    col.g = texture(source, suv).g;
    col.b = texture(source, clamp(suv - vec2(ca, 0.0), 0.0, 1.0)).b;
    col.a = texture(source, suv).a;
    fragColor = col * coverage(uv) * ubuf.qt_Opacity;
}
