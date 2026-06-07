// ═══════════════════════════════════════════════════════════════════
//  Luminance Wind
//  Category: artistic
//  Features: mouse-driven, audio-reactive, curl-noise, chromatic-drift, depth-parallax, upgraded-rgba
//  Complexity: High
//  Chunks From: luminance-wind, curl2D, fbm, bass_env
//  Created: 2024-01-01
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
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

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthLayer = mix(0.5, 1.5, depth);

    let speed = mix(0.0, 0.05, u.zoom_params.x) * bass_env(bass, mids);
    let decay = mix(0.8, 0.99, u.zoom_params.y);
    let threshold = u.zoom_params.z;
    let noiseAmt = u.zoom_params.w;

    let windDir = select(vec2<f32>(1.0, 0.0), normalize(uv - mouse), mouse.x > 0.0 && mouse.y > 0.0);

    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(current.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

    var localSpeed = speed * luma * depthLayer;
    if (luma < threshold) { localSpeed = 0.0; }

    // Curl noise for organic wind turbulence
    let curl = curl2D(uv * 3.0, time * 0.2) * 0.02 * bass_env(bass, mids);
    let noise = (hash21(uv * 100.0 + time) - 0.5) * noiseAmt;
    let noisyWind = normalize(windDir + vec2<f32>(0.0, noise)) + curl;

    let sourceUV = clamp(uv - noisyWind * localSpeed, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, sourceUV, 0.0);

    // Chromatic drift: R and B channels drift at different rates
    let driftR = clamp(uv - noisyWind * localSpeed * 1.1, vec2<f32>(0.0), vec2<f32>(1.0));
    let driftB = clamp(uv - noisyWind * localSpeed * 0.9, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(dataTextureC, non_filtering_sampler, driftR, 0.0).r;
    let b = textureSampleLevel(dataTextureC, non_filtering_sampler, driftB, 0.0).b;
    let g = history.g;

    let injection = 0.1 + bass * 0.05;
    let newColor = mix(vec4<f32>(r, g, b, history.a), current, injection);
    let finalColor = newColor * decay;

    let alpha = clamp(finalColor.a + localSpeed * 10.0 + bass * 0.05, 0.0, 1.0);

    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor.rgb, alpha));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
