#version 440

// Foil edition: a diagonal iridescent sheen that rides across the real content, brightening what it crosses instead of covering it.
//
// SAMPLING pack shader: reads the window through `source` and modulates those
// pixels, so it changes the content itself rather than laying colour on top.
//
// @param p1 Sheen 0.0 1.0 0.40
// @param p2 Bands 1.0 12.0 3.5
// @param p3 Travel 0.0 3.0 0.8
// @param p4 Tightness 0.5 8.0 3.0
// @param c1 Cool #0093FF
// @param c2 Warm #FFC500

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

float coverage(vec2 uv) {
    vec2 S = vec2(ubuf.pxh * ubuf.aspect, ubuf.pxh);
    vec2 q = abs(uv * S - S * 0.5) - (S * 0.5 - vec2(ubuf.radius));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - ubuf.radius;
    return 1.0 - smoothstep(-1.0, 1.0, d);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 src = texture(source, uv);
    // Diagonal coordinate so the sheen sweeps corner to corner like light
    // catching a foil card as it tilts.
    float d = (uv.x * ubuf.aspect + uv.y) * ubuf.p2 - ubuf.time * ubuf.p3;
    float band = pow(0.5 + 0.5 * sin(d * 6.2831), ubuf.p4);
    vec3 sheen = mix(ubuf.c1.rgb, ubuf.c2.rgb, 0.5 + 0.5 * sin(d * 2.0));
    // Screen-blend so it lifts highlights and leaves dark ink readable —
    // an additive wash would wipe out the text underneath.
    vec3 col = 1.0 - (1.0 - src.rgb) * (1.0 - sheen * band * ubuf.p1 * ubuf.strength);
    fragColor = vec4(col, 1.0) * src.a * coverage(uv) * ubuf.qt_Opacity;
}
