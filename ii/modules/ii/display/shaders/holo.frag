#version 440

// Holographic edition: hue rotates with brightness and drifts, so the content recolours itself rather than being tinted.
//
// SAMPLING pack shader: reads the window through `source` and modulates those
// pixels, so it changes the content itself rather than laying colour on top.
//
// @param p1 Shift 0.0 1.0 0.30
// @param p2 Bands 0.5 8.0 2.2
// @param p3 Drift 0.0 2.0 0.5
// @param p4 Keep 0.0 1.0 0.55
// @param c1 Cool #0093FF
// @param c2 Warm #FE5F55

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
    float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
    // Drive the mix from LUMA, so bright glyphs shift and the background
    // stays put — that is what makes it read as a holographic print.
    float t = sin((luma * ubuf.p2 + uv.y * 0.6 - ubuf.time * ubuf.p3) * 6.2831);
    vec3 tintc = mix(ubuf.c1.rgb, ubuf.c2.rgb, 0.5 + 0.5 * t);
    vec3 col = mix(src.rgb * tintc * 1.6, src.rgb, ubuf.p4);
    col = mix(src.rgb, col, ubuf.p1 * ubuf.strength * 2.0);
    fragColor = vec4(col, 1.0) * src.a * coverage(uv) * ubuf.qt_Opacity;
}
