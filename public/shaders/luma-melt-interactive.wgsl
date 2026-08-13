// ═══════════════════════════════════════════════════════════════════
//  Luma Melt
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  Chunks From: luma-melt-interactive, warpedFBM, curl2D, bass_env
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// ═══ CHUNK: valueNoise ═══
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

// ═══ CHUNK: fbm ═══
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

// ═══ CHUNK: curl2D ═══
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

// ═══ CHUNK: bass_env ═══
fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.6 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let held = step(0.5, u.zoom_config.w);

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let meltSpeed = u.zoom_params.x * 0.03 * bass_env(bass, mids);
    let persistence = clamp(u.zoom_params.y, 0.5, 0.99);
    let radius = max(u.zoom_params.z, 0.01);
    let heat = u.zoom_params.w * 0.15;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let viscosity = mix(0.3, 1.0, depth);

    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let mouseFactor = smoothstep(radius, 0.0, dist) * mix(0.12, 1.0, held);

    var clickHeat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
      let ripple = u.ripples[rippleIndex];
      let rippleAge = max(time - ripple.z, 0.0);
      let front = abs(distance(uv, ripple.xy) - rippleAge * (0.17 + bass * 0.10));
      clickHeat += exp(-front * 125.0) * exp(-rippleAge * 1.55);
    }

    let newColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(newColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let meltRunner = pow(max(0.0, sin((uv.y + uv.x * 0.22) * 46.0 - time * (13.0 + mids * 6.0))), 14.0);
    let dripPacket = pow(max(0.0, sin(uv.y * 62.0 + fbm(uv * 7.0, 3) * 8.0 - time * (18.0 + treble * 7.0))), 18.0);
    let curl = curl2D(uv * 3.0, time * 0.2) * meltSpeed * (1.0 + bass * 0.5);
    let gravity = vec2<f32>(0.0, meltSpeed * luma * (1.0 + meltRunner * 0.7));
    let flow = (curl + gravity) * viscosity;

    let totalFlow = flow + vec2<f32>(0.0, heat * (mouseFactor + clickHeat * 0.8 + dripPacket * 0.18));
    let sourceUV = clamp(uv - totalFlow, vec2<f32>(0.0), vec2<f32>(1.0));

    let historyCoord = clamp(vec2<i32>(sourceUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyCoord, 0);

    let trebleGlow = treble * 0.1 * mouseFactor;
    let blended = mix(newColor, history, persistence);
    let heated = blended + vec4<f32>(trebleGlow + meltRunner * mids * 0.05,
                                     trebleGlow * 0.5 + clickHeat * 0.05,
                                     trebleGlow * 0.2 + dripPacket * treble * 0.04,
                                     0.0);

    let meltAlpha = clamp(luma * 0.8 + mouseFactor * 0.3 + bass * 0.15, 0.0, 1.0);
    let finalColor = vec4<f32>(clamp(heated.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), meltAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
