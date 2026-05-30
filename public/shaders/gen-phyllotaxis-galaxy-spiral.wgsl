// ═══════════════════════════════════════════════════════════════════
//  Phyllotaxis Galaxy Spiral
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
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

const PHI: f32 = 2.39996323; // golden angle in radians
const TAU: f32 = 6.283185307;

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;

  // 3D viewpoint offset from mouse
  var viewOffset = vec2<f32>(0.0, 0.0);
  if (u.zoom_config.w > 0.5) {
    viewOffset = (mouse - 0.5) * 1.5;
  }

  // Galaxy center with rotation from mids
  let rotAngle = time * 0.08 + mids * TAU * 0.25;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let centered = (uv - 0.5) * 2.0;
  let rotUV = vec2<f32>(centered.x * cosR - centered.y * sinR,
                        centered.x * sinR + centered.y * cosR);
  let sampleUV = rotUV + viewOffset;

  // Star accumulation
  var accum = vec3<f32>(0.0, 0.0, 0.0);
  var alphaAcc = 0.0;
  var maxDepth = 0.0;
  let starCount = 350;
  let c = 0.012 + p1 * 0.015;
  let densityWaveAmp = 0.15 + bass * 0.25;

  for (var i: i32 = 1; i <= starCount; i = i + 1) {
    let n = f32(i);
    let theta = n * PHI + time * 0.03 * (1.0 + hash11(n) * 0.5);
    let r = c * sqrt(n);

    // Lin-Shu density wave perturbation
    let wave = sin(theta * 2.0 + r * 40.0) * densityWaveAmp;
    let rWave = r + wave * r;

    let pos = vec2<f32>(cos(theta) * rWave, sin(theta) * rWave);
    let delta = sampleUV - pos;
    let dist = length(delta);

    // Perspective depth based on ring radius + hash
    let depth = clamp(1.0 - r * 0.9 + (hash11(n * 3.7) - 0.5) * 0.3, 0.0, 1.0);
    let size = (0.003 + hash11(n * 13.0) * 0.006) * (0.6 + depth * 0.8) * (1.0 + p2);

    let starShape = exp(-dist * dist / (size * size));
    if (starShape < 0.001) { continue; }

    // Hubble palette: young=blue, old=red, dust=yellow
    let starType = hash11(n * 7.3);
    var starColor: vec3<f32>;
    if (starType < 0.25) {
      starColor = vec3<f32>(0.4, 0.6, 1.0); // young blue
    } else if (starType < 0.6) {
      starColor = vec3<f32>(1.0, 0.85, 0.6); // yellow main seq
    } else if (starType < 0.9) {
      starColor = vec3<f32>(1.0, 0.5, 0.3); // old red
    } else {
      starColor = vec3<f32>(1.0, 0.3, 0.5); // supernova candidate
    }

    // Treble triggers supernova flare on rare stars
    let isSupernova = step(0.96, starType) * step(0.7, fract(hash11(n) + time * 0.5 + treble));
    starColor += vec3<f32>(1.0, 0.9, 0.7) * isSupernova * treble * 3.0;

    // Depth fade
    let depthFade = smoothstep(0.0, 0.15, depth) * smoothstep(1.0, 0.6, depth);
    let dust = smoothstep(0.3, 0.7, hash11(n * 19.0)) * 0.4;
    let extinction = 1.0 - dust * r * 2.0;

    accum += starColor * starShape * depthFade * extinction;
    alphaAcc += starShape * depthFade * extinction;
    maxDepth = max(maxDepth, depth * starShape);
  }

  // Chromatic aberration on bright giants
  let caStrength = 0.008 * treble;
  let caR = exp(-pow(length(sampleUV * (1.0 + caStrength) - sampleUV), 2.0) * 200.0);
  accum.r *= 1.0 + caR * 0.2;
  accum.b *= 1.0 - caR * 0.15;

  // ACES tone mapping
  accum = accum * (2.51 * accum + 0.03) / (accum * (2.43 * accum + 0.59) + 0.14);

  // Alpha: brightness × depth_fade × (1.0 - dust_extinction)
  let alpha = clamp(alphaAcc * 0.5 * (1.0 + maxDepth), 0.0, 1.0);
  let out = vec4<f32>(accum, alpha);

  // Depth: brightest/nearest stars occlude the background field
  let depthOut = clamp(maxDepth, 0.0, 1.0);
  textureStore(writeTexture, coord, out);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, out);
}
