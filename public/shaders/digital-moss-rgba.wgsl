// ═══════════════════════════════════════════════════════════════════
//  digital-moss-rgba
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, organic
//  Complexity: Very High
//  Chunks From: digital-moss.wgsl, alpha-reaction-diffusion-rgba.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  Digital moss that grows via reaction-diffusion patterns.
//  The RGBA state machine drives both moss coloration and growth.
//  Dark areas accumulate moss; the RD chemicals color it with
//  living, evolving patterns. Mouse cleans the moss.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let aspect = f32(dims.x) / f32(dims.y);

  let feedParam = u.zoom_params.x;
  let killParam = u.zoom_params.y;
  let sourceMix = u.zoom_params.z;
  let growSpeed = u.zoom_params.w;

  let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

  // === REACTION DIFFUSION STATE ===
  let state = textureLoad(dataTextureC, coord, 0);
  var A = state.r;
  var B = state.g;
  var C = state.b;
  var D = state.a;

  if (time < 0.1) {
    A = 1.0; B = 0.0; C = 1.0; D = 0.0;
    let centerDist = length(uv - vec2<f32>(0.5));
    if (centerDist < 0.05) { B = 0.5; D = 0.3; }
    let seed2Dist = length(uv - vec2<f32>(0.3, 0.7));
    if (seed2Dist < 0.03) { B = 0.4; }
  }

  let ps = 1.0 / vec2<f32>(dims);
  let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let lapA = left.r + right.r + down.r + up.r - 4.0 * A;
  let lapB = left.g + right.g + down.g + up.g - 4.0 * B;
  let lapC = left.b + right.b + down.b + up.b - 4.0 * C;
  let lapD = left.a + right.a + down.a + up.a - 4.0 * D;

  let feed = mix(0.02, 0.06, feedParam);
  let kill = mix(0.04, 0.07, killParam);
  let diffA = 0.8; let diffB = 0.3; let diffC = 0.7; let diffD = 0.25;
  let crossInhibit = sourceMix * 0.3;
  let dt = 0.8;

  let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
  let dB = diffB * lapB + A * B * B - (feed + kill) * B;
  let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B;
  let dD = diffD * lapD + C * D * D - (feed + kill) * D;

  A = A + dA * dt; B = B + dB * dt; C = C + dC * dt; D = D + dD * dt;
  A = clamp(A, 0.0, 1.0); B = clamp(B, 0.0, 1.0);
  C = clamp(C, 0.0, 1.0); D = clamp(D, 0.0, 1.0);

  // Mouse injection
  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mouse);
  let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
  B += mouseInfluence * 0.3;
  D += mouseInfluence * 0.2;
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  // Ripple perturbation
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 1.5 && rDist < 0.06) {
      let strength = smoothstep(0.06, 0.0, rDist) * max(0.0, 1.0 - age);
      B += strength * 0.4;
      D += strength * 0.2;
    }
  }
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

  // === MOSS GROWTH ===
  let oldState = textureLoad(dataTextureC, coord, 0).r;
  let seed = hash12(uv + vec2<f32>(time * 0.1, time * 0.05));
  var grown = oldState;

  if (luma < 0.15 && seed > 0.995) {
    grown = 1.0;
  }

  if (grown < 0.9) {
    let angle = hash12(uv * 10.0 + time) * 6.28;
    let dist = 2.0;
    let offset = vec2<f32>(cos(angle), sin(angle)) * dist;
    let neighborCoord = coord + vec2<i32>(offset);
    let neighborState = textureLoad(dataTextureC, clamp(neighborCoord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    if (neighborState > 0.5 && luma < 0.4) {
      grown = min(1.0, grown + 0.05 * growSpeed);
    }
  }

  if (luma > 0.6) {
    grown *= 0.9;
  }

  // Mouse cleaning
  let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let m_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let mDist = length(p_aspect - m_aspect);
  if (mDist < 0.05) {
    grown = 0.0;
  }

  // RD colors drive moss color
  let colorA = vec3<f32>(0.0, 0.4, 1.0) * A;
  let colorB = vec3<f32>(1.0, 0.2, 0.0) * B;
  let colorC = vec3<f32>(0.0, 1.0, 0.3) * C;
  let colorD = vec3<f32>(1.0, 0.8, 0.0) * D;
  let rdColor = colorA + colorB + colorC + colorD;
  let mossColor = mix(vec3<f32>(0.2, 0.95, 0.35), rdColor, 0.7);

  let scan = 0.8 + 0.2 * sin(uv.y * 500.0);
  let scannedMossColor = mossColor * scan;

  let finalColor = mix(imgColor, scannedMossColor, grown * 0.85);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, mix(1.0, 0.85, grown)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
