// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Stream
//  Category: image
//  Features: advanced-alpha, streaming-pulses, neon-effect, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: neon-pulse-stream, curl2D, warpedFBM, bass_env, Fresnel-tube
//  Created: 2026-05-23
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t * 0.1, 3);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t * 0.1, 3);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let audioReactivity = bass_env(bass, mids);

    let streamSpeed = u.zoom_params.x * 3.0 * (1.0 + mids * 0.3);
    let streamDensity = u.zoom_params.y * 10.0 + 3.0 + treble * 2.0;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = u.zoom_params.w * 0.2;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(0.6, 1.0, depth);

    let curl = curl2D(uv * 2.0, time * 0.15) * 0.02 * audioReactivity;
    let advectUV = uv + curl;

    let bg = textureSampleLevel(readTexture, u_sampler, advectUV, 0.0).rgb;
    let bgLuma = dot(bg, vec3<f32>(0.299, 0.587, 0.114));

    let streamY = fract(advectUV.y * streamDensity - time * streamSpeed * audioReactivity);
    let dC = (streamY - 0.5) * 10.0;
    let pulse = exp(-dC * dC);

    let phase = time + advectUV.y * 3.0 + bass * 1.0;
    let neonColor = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    let tubeWidth = pulse * streamDensity * 0.5;
    let fresnel = pow(1.0 - tubeWidth, 2.0);
    let rimLight = neonColor * fresnel * 2.0 * depthFade;
    let coreLight = neonColor * pulse * streamDensity * 0.8;
    let streamColor = rimLight + coreLight;

    let composite = bg * (1.0 - pulse * 0.7) + streamColor;

    var sparkle = 0.0;
    var sparkleCol = vec3<f32>(0.0);
    if (treble > 0.4 && bgLuma > 0.5) {
      let sparkNoise = hash21(uv * 500.0 + time * 30.0);
      let sparkMask = step(0.97, sparkNoise);
      sparkleCol = vec3<f32>(sparkMask * treble * 2.0);
      sparkle = sparkMask;
    }

    let lumaAlpha = luminanceKeyAlpha(streamColor, lumaThreshold, softness);
    let alpha = clamp(lumaAlpha * pulse + dot(bg, vec3<f32>(0.299, 0.587, 0.114)) * 0.2 + 0.1 + sparkle * 0.5, 0.0, 1.0);

    let finalRGB = composite + sparkleCol;
    let finalColor = vec4<f32>(finalRGB, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
