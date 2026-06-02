// ═══════════════════════════════════════════════════════════════════
//  Aurora Curtain
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, chapman-layer,
//            kelvin-helmholtz, temporal-flow, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
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
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let layerBase = 3 + i32(u.zoom_params.x * 5.0);
  let flowSpeed = u.zoom_params.y * 0.4;
  let curtainWidth = 0.25 + u.zoom_params.z * 0.4;
  let colorShift = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = uv * vec2<f32>(aspect, 1.0);

  // Mouse drags magnetic zenith
  let magZenith = vec2<f32>(mouse.x * aspect, mouse.y);
  let distToZenith = length(p - magZenith);

  var color = vec3<f32>(0.0);
  var excitation = 0.0;
  var bloom = 0.0;

  for (var i = 0; i < layerBase; i = i + 1) {
    let fi = f32(i);
    let t = time * flowSpeed * (0.4 + fi * 0.12);

    // Chapman layer altitude (0=high red, 1=mid green, 2=low blue)
    let altitude = fi / f32(layerBase);

    // Curtain displacement with Kelvin-Helmholtz folding
    let baseY = 0.15 + fi * 0.18 + (mouse.y - 0.5) * 0.2;
    let khx = p.x * (2.5 + fi * 0.8) + t + fi * 1.9;
    let kh = sin(khx) * 0.06 + sin(khx * 2.7 - t * 1.4) * 0.03 * (1.0 + mids);
    let khInstability = noise2(vec2<f32>(p.x * 4.0 + t, fi * 3.0)) * 0.04 * mids;
    let curtainY = baseY + kh + khInstability + (distToZenith * 0.08 * (1.0 - altitude));

    let dist = abs(p.y - curtainY);
    let thickness = curtainWidth * (0.7 + fi * 0.08) * (1.0 + bass * 0.25);
    let glow = smoothstep(thickness, 0.0, dist);

    // Physically accurate auroral colors by altitude
    var layerColor: vec3<f32>;
    if (altitude < 0.35) {
      // High altitude: atomic oxygen red (630nm)
      layerColor = vec3<f32>(0.85, 0.25, 0.15);
    } else if (altitude < 0.65) {
      // Mid altitude: atomic oxygen green (557.7nm)
      layerColor = vec3<f32>(0.25, 0.95, 0.35);
    } else if (altitude < 0.85) {
      // Low-mid: N2+ blue/purple
      layerColor = vec3<f32>(0.35, 0.45, 0.95);
    } else {
      // Lowest: N2 pink/magenta
      layerColor = vec3<f32>(0.95, 0.35, 0.75);
    }

    // Color shift and rayed bands from treble
    let rayBands = sin(p.x * 18.0 + fi * 3.7 + treble * 5.0) * 0.5 + 0.5;
    let rayMask = smoothstep(0.55, 0.95, rayBands) * treble * 0.4;
    layerColor = mix(layerColor, layerColor * 1.4, rayMask);

    let layerIntensity = glow * (0.45 + fi * 0.08) * (1.0 + bass * 0.35);
    color = color + layerColor * layerIntensity;
    excitation = excitation + layerIntensity;
    bloom = bloom + glow * (0.3 + bass * 0.2);
  }

  // Star field
  let starHash = hash21(floor(uv * 800.0));
  let star = step(0.998, starHash);
  let twinkle = sin(time * 2.5 + starHash * 20.0) * 0.5 + 0.5;
  let starColor = vec3<f32>(0.85, 0.92, 1.0) * star * twinkle * 0.35;
  color = color + starColor;

  // Rayleigh scattering of underlying atmosphere
  let atmosScatter = smoothstep(0.0, 0.5, uv.y) * vec3<f32>(0.08, 0.12, 0.22) * (1.0 + mids * 0.3);
  color = color + atmosScatter;

  // HDR bloom on curtain folds
  color = color + vec3<f32>(0.4, 0.7, 0.5) * bloom * 0.25;

  // ACES tone mapping
  color = acesToneMap(color * 1.3);

  // Atmospheric extinction by depth
  let extinction = depth * 0.25 * (1.0 + bass * 0.15);
  color = color * (1.0 - extinction * 0.3);

  // Alpha: excitation rate * atmospheric_transparency * depth
  let transparency = 1.0 - smoothstep(0.0, 0.4, uv.y) * 0.25;
  let alpha = clamp(excitation * transparency * (0.6 + depth * 0.4), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(excitation * 0.4, 0.0, 0.0, 0.0));
}
