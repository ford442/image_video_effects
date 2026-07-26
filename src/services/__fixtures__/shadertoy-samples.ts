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
