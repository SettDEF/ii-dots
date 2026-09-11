#version 440

// Balatro-style churning background: iterative domain warp (each pass bends
// the coordinate field by a sine of the other axis) fed into a two-colour
// mix. That warp-then-colour structure is what gives the liquid, folding look
// rather than a plain scrolling gradient.
//
// ── PACK SHADER ABI ──────────────────────────────────────────────────────
// Every shader in an effect pack declares this exact uniform block. Qt binds
// uniforms to QML properties by NAME, and can only do so for properties that
// already exist when the QML is compiled — QML cannot invent properties per
// shader at runtime. So the slot names are FIXED (p1..p4, c1, c2) and the
// @param lines below say what each slot means. Quickshell parses those lines
// to build the controls shown on this effect's row.
//
//   @param <slot> <label> <min> <max> <default> [step=<n>]
//   @param <slot> <label> <#rrggbb>            — colour slots c1/c2
//   @param <slot> <label> toggle <0|1>         — on/off slots
//
// `time`, `strength`, `aspect`, `radius` and `pxh` are supplied by the host
// and are not user-tunable, so they carry no @param line.
//
// @param p1 Warp 0.0 1.2 0.42
// @param p2 Folds 1 6 4 step=1
// @param p3 Drift 0.0 1.0 0.28
// @param p4 Contrast 0.6 2.0 1.18
// @param c1 Deep #121B6B
// @param c2 Hot #BD1A36

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;
    float strength;
    float aspect;
    float radius;  // corner radius in px — the shader rounds its own edge, so
    float pxh;     // no offscreen mask pass is needed just to clip corners
    float p1;      // warp amount
    float p2;      // fold iterations
    float p3;      // drift speed
    float p4;      // contrast
    vec4  c1;      // deep colour
    vec4  c2;      // hot colour
} ubuf;

void main() {
    vec2 p = qt_TexCoord0 * 2.0 - 1.0;
    p.x *= ubuf.aspect;

    float t = ubuf.time;
    int folds = int(clamp(ubuf.p2, 1.0, 6.0));
    for (int i = 1; i <= folds; ++i) {
        float fi = float(i);
        p.x += ubuf.p1 / fi * sin(fi * 2.4 * p.y + t * 0.75 + fi);
        p.y += ubuf.p1 / fi * cos(fi * 2.4 * p.x + t * 0.60 + fi);
    }

    // Two fixed anchors rather than a full cosine palette: sweeping the whole
    // spectrum reads as generic plasma, not Balatro.
    float f = 0.5 + 0.5 * sin((p.x + p.y) * 1.1 + t * ubuf.p3);
    vec3 col = mix(ubuf.c1.rgb, ubuf.c2.rgb, f);

    // Violet highlight folded over the top. Derived from the two anchors so it
    // still tracks when you recolour the effect instead of fighting it.
    vec3 violet = mix(ubuf.c1.rgb, ubuf.c2.rgb, 0.5) + vec3(0.12, -0.02, 0.20);
    col = mix(col, violet, 0.45 + 0.45 * cos(p.x * 1.6 - p.y * 0.7 - t * ubuf.p3));
    col = pow(max(col, vec3(0.0)), vec3(ubuf.p4));

    float a = clamp(ubuf.strength, 0.0, 1.0) * ubuf.qt_Opacity;

    // Rounded-rect signed distance, so the effect ends exactly where the
    // window's own corners do. Doing it here costs a few instructions;
    // masking it externally would cost a full-window texture round-trip
    // every frame.
    vec2 S = vec2(ubuf.pxh * ubuf.aspect, ubuf.pxh);
    vec2 q = abs(qt_TexCoord0 * S - S * 0.5) - (S * 0.5 - vec2(ubuf.radius));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - ubuf.radius;
    a *= 1.0 - smoothstep(-1.0, 1.0, d);

    fragColor = vec4(col * a, a);             // premultiplied
}
