#version 300 es
// Colour-vision preview (no colour at all): Machado, Oliveira & Fernandes 2009, full severity, in linear light.
// Look > Colour > Colour-blindness preview sets it as the screen shader (AppDisplay), never saved.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
vec3 toLin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
vec3 toSrgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 l = toLin(c.rgb);
    vec3 s = vec3(dot(l, vec3(0.2126, 0.7152, 0.0722)));
    fragColor = vec4(toSrgb(clamp(s, 0.0, 1.0)), c.a);
}
