// ═══════════════════════════════════════════════════════════════════
//  Gen Xeno Botanical Ecosystem
//  Category: advanced-hybrid
//  Features: generative, botanical, ecosystem, temporal, rgba-state-machine, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: gen-xeno-botanical-synth-flora.wgsl, alpha-multi-state-ecosystem.wgsl
//  Created: 2026-04-18
//  By: Agent CB-5 — Generative & Hybrid Enhancer
//  Upgraded: 2026-10-31
//  Ideas: additive spiral twist of the petal angle; Beer-Lambert canopy self-shading of the light resource and floor
//  A packing: raw sim state (s1, s2, resource, toxin); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
//  Botanical flora patterns host a living RGBA ecosystem simulation.
//  Species colonize branch structures, competing for photosynthetic
//  resources while toxins accumulate in dense growth regions.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: botanical structure (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn botanicalStructure(uv: vec2<f32>, time: f32, complexity: f32, growth: f32) -> f32 {
  let centered = uv - 0.5;
  let radius = length(centered);
  // Idea 1: additive domain twist, petals sweep into slow breathing spirals (zero at t = 0)
  let angle = atan2(centered.y, centered.x) + radius * 0.9 * sin(time * 0.2) * 0.7;
  let branchPattern = sin(angle * complexity + time * 0.5) * cos(radius * 10.0 - time);
  let organicNoise = hash12(floor(uv * 20.0) + time * 0.1);
  let flora = smoothstep(0.0, 0.5, branchPattern * growth) * (0.8 + 0.2 * organicNoise);
  return flora;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / max(c * (2.43 * c + 0.59) + 0.14, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ld(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let ps = 1.0 / res;
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let time = u.config.x;

  // Audio reactivity
  let audioMid = plasmaBuffer[0].y;
  let audioReactivity = 1.0 + audioMid * 0.5;

  // Parameters
  let growth = u.zoom_params.x * (1.0 + audioMid * 0.3);
  let complexity = u.zoom_params.y * 10.0 + 3.0;
  let ecosystemStrength = u.zoom_params.z;
  let glowSpread = u.zoom_params.w;

  // Botanical structure at this pixel
  let flora = botanicalStructure(uv, time, complexity, growth);

  // Read previous ecosystem state
  let prevState = textureLoad(dataTextureC, coord, 0);
  var s1 = prevState.r;
  var s2 = prevState.g;
  var resourceVal = prevState.b;
  var toxin = prevState.a;

  // Seed whenever the state is empty (HEAD only seeded at time < 0.1, so a mid-session load stayed bare)
  if (time < 0.1 || (s1 + s2 + resourceVal) <= 0.0) {
    s1 = 0.0;
    s2 = 0.0;
    resourceVal = 0.5;
    toxin = 0.0;
    // Seed species along botanical branches
    if (flora > 0.3) {
      let n1 = hash12(uv * 47.0 + vec2<f32>(12.9898, 78.233));
      if (n1 > 0.85) { s1 = 0.8 * flora; }
      let n2 = hash12(uv * 53.0 + vec2<f32>(93.0, 17.0));
      if (n2 > 0.9) { s2 = 0.7 * flora; }
    }
  }

  // Clamp
  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);
  resourceVal = clamp(resourceVal, 0.0, 2.0);
  toxin = clamp(toxin, 0.0, 2.0);

  // Diffusion
  let dims = vec2<i32>(i32(res.x), i32(res.y));
  let left = ld(coord - vec2<i32>(1, 0), dims);
  let right = ld(coord + vec2<i32>(1, 0), dims);
  let down = ld(coord - vec2<i32>(0, 1), dims);
  let up = ld(coord + vec2<i32>(0, 1), dims);

  let lapS1 = left.r + right.r + down.r + up.r - 4.0 * s1;
  let lapS2 = left.g + right.g + down.g + up.g - 4.0 * s2;
  let lapResource = left.b + right.b + down.b + up.b - 4.0 * resourceVal;
  let lapToxin = left.a + right.a + down.a + up.a - 4.0 * toxin;

  // Ecosystem dynamics modulated by botanical structure
  let growthRate1 = mix(0.02, 0.08, u.zoom_params.x) * (0.5 + flora * 0.5);
  let growthRate2 = mix(0.015, 0.06, u.zoom_params.y) * (0.5 + flora * 0.5);
  let toxinDecay = 0.95;
  // Idea 2: Beer-Lambert canopy, light reaching a cell falls as exp(-k * density)
  let canopyLight = exp(-1.4 * (s1 + s2));
  let resourceRegen = (0.001 + flora * 0.003) * (0.4 + 0.6 * canopyLight); // More light on branches, less under canopy
  let dt = 0.5;

  let food1 = s1 * resourceVal * growthRate1;
  let food2 = s2 * resourceVal * growthRate2;
  let competition = s1 * s2 * 0.1;
  let toxinProduction1 = s1 * 0.005 * flora;
  let toxinProduction2 = s2 * 0.003 * flora;
  let toxinDamage = toxin * 0.02;

  resourceVal += resourceRegen - food1 - food2;
  resourceVal += lapResource * 0.1;

  s1 += food1 - competition - toxinDamage + lapS1 * 0.05;
  s2 += food2 - competition - toxinDamage + lapS2 * 0.05;

  toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01;
  toxin += lapToxin * 0.08;
  toxin *= toxinDecay;

  s1 *= 0.998;
  s2 *= 0.998;

  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);
  resourceVal = clamp(resourceVal, 0.0, 2.0);
  toxin = clamp(toxin, 0.0, 2.0);

  // Mouse interaction nurtures ecosystem
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
  resourceVal += mouseInfluence * 0.5;
  toxin -= mouseInfluence * 0.3;
  toxin = max(toxin, 0.0);

  // Ripples seed new life
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 1.0 && rDist < 0.04) {
      let strength = smoothstep(0.04, 0.0, rDist) * max(0.0, 1.0 - age);
      let is_s1 = f32(i) % 2.0 < 1.0;
      s1 += strength * select(0.0, 1.0, is_s1) * 0.5;
      s2 += strength * select(1.0, 0.0, is_s1) * 0.5;
    }
  }
  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);

  // Store state
  textureStore(dataTextureA, coord, vec4<f32>(s1, s2, resourceVal, toxin));

  // Visualization: blend botanical base with ecosystem overlay
  // the floor sits under the canopy: green is absorbed least, red and blue most
  let botanicalColor = vec3<f32>(0.15 + flora * 0.4, 0.35 + flora * 0.3, 0.25 + flora * 0.35)
    * exp(-(s1 + s2) * vec3<f32>(1.0, 0.45, 0.8));
  let colorS1 = vec3<f32>(0.0, 0.9, 1.0) * min(s1, 1.0);
  let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
  let colorResource = vec3<f32>(0.3, 0.8, 0.3) * min(resourceVal, 1.0) * 0.3;
  let colorToxin = vec3<f32>(0.4, 0.0, 0.5) * min(toxin, 1.0) * 0.5;

  var displayColor = colorS1 + colorS2 + colorResource + colorToxin;
  displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Edge highlights where species meet
  let s1Grad = length(vec2<f32>(left.r - right.r, down.r - up.r));
  let s2Grad = length(vec2<f32>(left.g - right.g, down.g - up.g));
  let edgeHighlight = (s1Grad + s2Grad) * 2.0;
  displayColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;
  displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Blend botanical base with ecosystem
  let ecoAlpha = min(s1 + s2, 1.0) * ecosystemStrength;
  let finalColor = mix(botanicalColor * flora * 0.5, displayColor, ecoAlpha);
  let finalAlpha = max(flora * 0.6, ecoAlpha);

  // Glow spread
  let glow = smoothstep(0.0, glowSpread * 0.5 + 0.05, flora + s1 + s2);

  textureStore(writeTexture, coord, vec4<f32>(aces(finalColor * (0.8 + glow * 0.4)), finalAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
