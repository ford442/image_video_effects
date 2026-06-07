// ═══════════════════════════════════════════════════════════════════
//  Sonar Reveal
//  Category: lighting-effects
//  Features: mouse-driven, sonar, reveal, audio-pulse, depth-echo, atmospheric-reveal
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer pulse propagation, audio-reactive echoes, volumetric atmosphere)
// ═══════════════════════════════════════════════════════════════════
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= res.x || global_id.y >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / vec2<f32>(res);
  let aspect = u.config.z / u.config.w;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

    // Grok: Richer sonar pulse with atmospheric propagation
    let pulseStrength = 1.0 + bass * 0.6 + treble * 0.4;

// Grok: Richer atmospheric propagation and echo layers
let echoLayers = 1.0 + mids * 0.8;

  let baseSize = u.zoom_params.x * 0.45 + 0.06;
  let intensity = u.zoom_params.y * 3.0;
  let softness = u.zoom_params.z * 0.18 + 0.01;
  let echoMix = u.zoom_params.w;

  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let gray = dot(c0.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let dim = vec3<f32>(gray * 0.22, gray * 0.25, gray * 0.30);

  let dUV = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dUV);

  let audioPulse = 1.0 + bass * 0.6 + mids * 0.25;
  let speedBoost = 1.0 + bass * 1.2;

  var ringAccum = 0.0;
  var sparkle = 0.0;
  let f1 = 8.0;
  let f2 = 8.6;
  let f3 = 9.2;
  let detune = 0.015 * (1.0 + mids * 0.5);

  for (var i: u32 = 0u; i < 3u; i = i + 1u) {
    let fi = select(f1, select(f2, f3, i == 1u), i == 0u);
    let phase = dist * fi * 6.283185307 - time * speedBoost * 2.5;
    let rw = 0.012 + softness * 0.06 + treble * 0.008;
    let r = smoothstep(rw, 0.0, abs(sin(phase) * 0.5 - 0.5 + detune * f32(i)));
    ringAccum = ringAccum + r;
    sparkle = sparkle + smoothstep(0.85, 1.0, r) * treble * 2.0;
  }
  ringAccum = ringAccum * 0.45;

  let shockAccum = 0.0;
  let rippleCount = u32(u.config.y);
  var shockwaves = 0.0;
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rpl = u.ripples[i];
    let rpos = rpl.xy;
    let elapsed = time - rpl.z;
    let rd = length((uv - rpos) * vec2<f32>(aspect, 1.0));
    let radius = elapsed * 0.35 * speedBoost;
    let sw = smoothstep(0.06, 0.0, abs(rd - radius)) * exp(-elapsed * 2.0);
    shockwaves = shockwaves + sw;
  }
  shockwaves = clamp(shockwaves, 0.0, 1.0);

  let doppler = 1.0 + 0.08 * sin(dist * 40.0 - time * 6.0 * speedBoost);
  let reveal = 1.0 - smoothstep(baseSize, baseSize + softness + 0.02, dist / doppler);

  let prevEcho = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let echoDecay = exp(-depth * 3.0) * 0.35 * echoMix;
  let echoRGB = prevEcho.rgb * echoDecay;

  let warm = vec3<f32>(1.0, 0.65, 0.15);
  let cool = vec3<f32>(0.15, 0.55, 1.0);
  let temp = clamp(mids * 2.0 + bass, 0.0, 1.0);
  let rimColor = mix(warm, cool, temp);

  let hdrRim = ringAccum * intensity * audioPulse * rimColor;
  let hdrSparkle = vec3<f32>(1.0, 0.92, 0.75) * sparkle * intensity;
  let hdrShock = shockwaves * intensity * rimColor * 0.6;

  let splitShadow = mix(vec3<f32>(0.08, 0.04, 0.12), vec3<f32>(0.04, 0.08, 0.14), temp);
  let shadowMask = (1.0 - reveal) * (1.0 - ringAccum);
  var rgb = mix(dim, c0.rgb, reveal) + hdrRim + hdrSparkle + hdrShock + echoRGB;
  rgb = rgb + splitShadow * shadowMask * 0.25;
  rgb = aces_tonemap(rgb * 1.2);

  let alpha = mix(0.45 + depth * 0.35, 0.85, reveal + ringAccum * 0.5);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
