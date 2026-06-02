// ═══════════════════════════════════════════════════════════════════
//  Liquid Warp Interactive
//  Category: distortion
//  Features: mouse-driven, audio-reactive, curl-noise, depth-viscosity, temporal, upgraded-rgba
//  Complexity: High
//  Chunks From: liquid-warp-interactive, curl2D, fbm, bass_env
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let clickState = u.zoom_config.w;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let viscosity = mix(0.3, 1.0, depth);

    let distortAmt = u.zoom_params.x * 0.25 * bass_env(bass, mids);
    let flowSpeed = mix(0.5, 4.0, u.zoom_params.y) * (1.0 + mids * 0.35);
    let noiseScale = mix(4.0, 40.0, u.zoom_params.z) * (1.0 + treble * 0.2);
    let viscosityParam = u.zoom_params.w;

    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mousePosCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let mVec = mousePosCorrected - uvCorrected;
    let mDist = length(mVec);
    let ripple = sin((mDist - time * flowSpeed) * (12.0 + noiseScale)) * 0.5 + 0.5;
    let pull = smoothstep(0.6, 0.0, mDist) * distortAmt * (0.7 + ripple * 0.3) * mix(0.25, 1.0, clickState);
    let flow = mVec / max(mDist, 0.001) * pull;

    let curl = curl2D(uv * 2.0, time * 0.12) * 0.025 * bass_env(bass, mids) * viscosity;
    let turbulence = vec2<f32>(
        sin(uv.y * noiseScale + time * flowSpeed * (1.5 + mids)),
        cos(uv.x * noiseScale + time * flowSpeed * (1.2 + treble))
    ) * (0.006 + (1.0 - viscosityParam) * 0.014) * viscosity;

    let distUV = clamp(uv + vec2<f32>(flow.x / aspect, flow.y) + turbulence + curl, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let chromaticAberration = (0.004 + (1.0 - viscosityParam) * 0.014) * (1.0 + treble * 0.4) * (1.0 + clickState);
    let rUV = clamp(distUV + vec2<f32>(chromaticAberration, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = distUV;
    let bUV = clamp(distUV - vec2<f32>(chromaticAberration, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let gColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let warped = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        gColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );
    let tint = vec3<f32>(0.03, 0.18 + mids * 0.08, 0.12 + bass * 0.06) * ripple * pull * 3.0;
    let finalColor = warped + tint;
    let alpha = clamp(gColor.a * 0.45 + pull * 1.6 + ripple * 0.12 + bass * 0.05, 0.08, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, gUV, 0.0).r + pull * 0.18, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
