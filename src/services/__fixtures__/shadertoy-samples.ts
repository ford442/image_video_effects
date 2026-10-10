/** Minimal Shadertoy-style GLSL fixtures for conversion tests (no live API). */

export const SAMPLE_PLASMA_GLSL = `
#define PI 3.14159265359

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime * 0.5;
    float v = sin(uv.x * 10.0 + t) + sin(uv.y * 10.0 + t);
    fragColor = vec4(0.5 + 0.5 * sin(v), 0.5 + 0.5 * cos(v), 0.5, 1.0);
}
`;

export const SAMPLE_TUNNEL_GLSL = `
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord * 2.0 - iResolution.xy) / iResolution.y;
    float t = iTime;
    float r = length(uv);
    float a = atan(uv.y, uv.x);
    float tunnel = sin(r * 8.0 - t * 2.0 + a * 3.0);
    fragColor = vec4(vec3(0.5 + 0.5 * tunnel), 1.0);
}
`;

export const SAMPLE_NOISE_GLSL = `
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float n = hash(floor(uv * 32.0) + iTime);
    fragColor = vec4(vec3(n), 1.0);
}
`;

/** Pre-built WGSL image logic (simulates Tint output) for gate tests without CDN. */
export const SAMPLE_PLASMA_WGSL_LOGIC = `
var outColor = vec4<f32>(
  0.5 + 0.5 * sin(sin(uv.x * 10.0 + u.config.x * 0.5) + sin(uv.y * 10.0 + u.config.x * 0.5)),
  0.5 + 0.5 * cos(sin(uv.x * 10.0 + u.config.x * 0.5) + sin(uv.y * 10.0 + u.config.x * 0.5)),
  0.5,
  1.0
);
`;

export const SAMPLE_TUNNEL_WGSL_LOGIC = `
let aspectUv = (fragCoord * 2.0 - vec2<f32>(u.config.z, u.config.w)) / u.config.w;
let r = length(aspectUv);
let a = atan2(aspectUv.y, aspectUv.x);
let tunnel = sin(r * 8.0 - u.config.x * 2.0 + a * 3.0);
var outColor = vec4<f32>(vec3<f32>(0.5 + 0.5 * tunnel), 1.0);
`;

export const SAMPLE_NOISE_WGSL_LOGIC = `
fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
var outColor = vec4<f32>(vec3<f32>(hash(floor(uv * 32.0) + vec2<f32>(u.config.x, 0.0))), 1.0);
`;

/** iMouse, iChannel0, a const global, a loop and a helper with a non-default mainImage signature. */
export const SAMPLE_MOUSE_CHANNEL_GLSL = `
precision highp float;
const float RINGS = 6.0;

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

void mainImage(out vec4 col, in vec2 p) {
    vec2 uv = p / iResolution.xy;
    vec2 m = iMouse.xy / iResolution.xy;
    float d = length(uv - m);
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        acc += 0.25 * texture(iChannel0, uv * rot(iTime * 0.1 * float(i))).rgb;
    }
    float ring = 0.5 + 0.5 * cos(d * RINGS * 6.2831 - iTime);
    col = vec4(acc * ring, 1.0);
}
`;
