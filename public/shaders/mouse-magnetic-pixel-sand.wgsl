// ═══════════════════════════════════════════════════════════════════
//  mouse-magnetic-pixel-sand
//  Category: interactive-mouse
//  Features: mouse-driven, particle-simulation, magnetic, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: chunk-library.md (hash12)
//  Created: 2026-04-18
//  By: Agent 2C
//  Upgraded: 2026-09-21
//  Ideas: field-line chaining; bass-driven field pulse; settling residue (C feedback)
//  A packing: raw sim state — C.a settled residue (decays), C.rgb last filing color
// ═══════════════════════════════════════════════════════════════════
//  Pixels are treated as iron filings. The mouse is a magnet that
//  attracts bright pixels and repels dark ones. Creates beautiful
//  flowing patterns as magnetic grains flow toward/away from mouse.
//  Alpha channel stores pixel magnetic field strength.
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;

  // Idea 2: bass-driven field pulse — the magnet visibly surges on the beat.
  let magnetStrength = mix(0.05, 0.4, u.zoom_params.x) * (1.0 + bass * 0.5);
  let magneticRange = mix(0.1, 0.5, u.zoom_params.y) * (1.0 + bass * 0.15);
  let polarity = select(-1.0, 1.0, u.zoom_params.z > 0.5); // attract vs repel
  let grainSize = mix(50.0, 300.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Sample base image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(baseColor);

  // Magnetic susceptibility: bright pixels are more magnetic
  let susceptibility = smoothstep(0.0, 0.8, luma);

  // Mouse magnetic field
  let toMouse = (mousePos - uv) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let fieldStrength = magnetStrength * susceptibility * polarity;

  // Magnetic displacement: filings align along field lines
  let fieldDir = select(vec2<f32>(0.0), normalize(toMouse), dist > 0.001);
  let falloff = smoothstep(magneticRange, 0.0, dist);

  // Add noise for grain texture
  let grain = hash12(floor(uv * grainSize) + vec2<f32>(0.5));
  let grainOffset = (grain - 0.5) * 0.02 * susceptibility;

  var displacedUV = uv;
  if (mousePos.x >= 0.0) {
    displacedUV = uv + fieldDir * fieldStrength * falloff + vec2<f32>(grainOffset);
  }

  // Ripple effects: secondary magnetic pulses
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rToMouse = (rPos - uv) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rFalloff = smoothstep(0.3, 0.0, rDist) * exp(-elapsed * 1.2);
      let rDir = select(vec2<f32>(0.0), normalize(rToMouse), rDist > 0.001);

      // Ripples alternate polarity
      let rPolarity = select(-1.0, 1.0, f32(i % 2u) > 0.5);
      displacedUV = displacedUV + rDir * magnetStrength * rFalloff * rPolarity * susceptibility * 0.5;
    }
  }

  // Idea 1: field-line chaining — average the displaced sample with taps
  // slightly ahead of and behind it along the field direction, so grains
  // read as short linked chains instead of independent jittered dots.
  let chainStep = fieldDir * grainSize * 0.00035 * (0.5 + falloff);
  let filingColorFwd = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + chainStep, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let filingColorBack = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - chainStep, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let filingColor = mix(textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb,
                         (filingColorFwd + filingColorBack) * 0.5,
                         susceptibility * falloff * 0.6);

  // Darken non-magnetic areas to emphasize filings
  let filingLuma = getLuma(filingColor);
  var color = mix(vec3<f32>(filingLuma * 0.3), filingColor, susceptibility);

  // Metallic sheen on magnetic grains
  let sheen = pow(susceptibility, 2.0) * falloff * 0.5;
  color = color + vec3<f32>(0.7, 0.8, 1.0) * sheen;

  // Mouse down intensifies alignment
  let alignBoost = mouseDown * 0.3 * falloff * susceptibility;
  color = mix(color, vec3<f32>(1.0, 0.9, 0.7), alignBoost);

  // Idea 3: settling residue — filings that clustered strongly leave a
  // faint, slowly-decaying sediment behind once the field moves away,
  // like real iron filings settling instead of snapping back instantly.
  let prevResidue = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  let residueDecay = 0.985;
  let depositRate = clamp(abs(fieldStrength) * falloff * 2.0, 0.0, 1.0);
  let settled = max(prevResidue.a * residueDecay, depositRate);
  let residueColor = mix(prevResidue.rgb * residueDecay, color, depositRate);
  color = mix(color, residueColor, settled * 0.5 * (1.0 - falloff));

  // Alpha = magnetic field strength at this pixel
  let alpha = clamp(abs(fieldStrength) * falloff * 3.0 + susceptibility * 0.3 + settled * 0.15, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(residueColor, settled));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
