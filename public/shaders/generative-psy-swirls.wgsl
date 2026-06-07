// ═══════════════════════════════════════════════════════════════════
//  Generative Psy Swirls
//  Category: generative
//  Features: audio-reactive, mouse-interactive, psychedelic, chromatic, temporal-layer-memory,
//            upgraded-rgba, aces-tone-map, chromatic-hue-separation, audio-twist
//  Complexity: High
//  Upgraded: 2026-06-06
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn layeredSwirlLayer(uv: vec2<f32>, time: f32, twist: f32, freq: f32, offset: vec2<f32>) -> vec3<f32> {
    let d = length(uv - offset);
    let a = atan2(uv.y - offset.y, uv.x - offset.x);
    let swirl = a + d * twist * freq - time * 0.5;
    let arm = sin(swirl * 3.0) * 0.5 + 0.5;
    let distRipple = sin(d * 10.0 - time * 2.0) * 0.5 + 0.5;
    let val = arm * distRipple;
    let hue = fract(d * 0.5 + time * 0.1);
    return hsv2rgb(vec3<f32>(hue, 0.8, val));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let twist = u.zoom_params.x * 4.0 * (1.0 + bass * 0.3);
    let layers = u.zoom_params.y * 5.0 + 2.0;
    let freq = u.zoom_params.z * 2.0 + 0.5;
    let depthReduction = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let adjustedTwist = twist * (1.0 - depth * depthReduction);

    let mouse = u.zoom_config.yz;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let m = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

    // Chromatic hue separation per layer
    var rLayer = vec3<f32>(0.0);
    var gLayer = vec3<f32>(0.0);
    var bLayer = vec3<f32>(0.0);
    for (var i: i32 = 0; i < i32(layers); i = i + 1) {
        let fi = f32(i);
        let offset = m * fi * 0.1 + vec2<f32>(
            sin(time * 0.3 + fi * 1.2) * 0.1,
            cos(time * 0.2 + fi * 0.8) * 0.1
        );
        rLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2 + treble * 0.1, offset + vec2<f32>(fi * 0.02, 0.0));
        gLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2, offset);
        bLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2 - bass * 0.1, offset - vec2<f32>(fi * 0.02, 0.0));
    }
    let invLayers = 1.0 / layers;
    rLayer *= invLayers;
    gLayer *= invLayers;
    bLayer *= invLayers;

    var color = vec3<f32>(rLayer.r, gLayer.g, bLayer.b);

    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rp = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let rd = length(p - rp);
        let rt = time - ripple.z;
        let ring = sin(rd * 20.0 - rt * 5.0) * exp(-rd * 3.0 - rt * 0.5);
        color += vec3<f32>(0.5, 0.3, 0.8) * ring * 0.3;
    }

    // Temporal swirl layer accumulation: previous color fades in for trails
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    color = mix(color, prev * 0.92, 0.04 + mids * 0.02);

    let alpha = clamp(length(color) * 0.8 + bass * 0.05, 0.0, 1.0);

    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
