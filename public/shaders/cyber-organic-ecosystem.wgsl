// ═══════════════════════════════════════════════════════════════════
//  cyber-organic-ecosystem
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, temporal, rgba-state-machine, organic, upgraded-rgba
//  Complexity: Very High
//  Chunks From: cyber-organic.wgsl, alpha-multi-state-ecosystem.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
//  Upgraded: 2026-10-31
//  Ideas: beam-seeded spores; Beer-Lambert tissue over the scanned photo; soft inverse-square beam light (nutrient + relief)
//  A packing: raw sim state (s1, s2, resource, toxin); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
//  Scans the image to reveal a living multi-species ecosystem
//  beneath. The organic layer is a real ecosystem simulation with
//  species competing for resources while producing toxins. Mouse
//  nurtures the ecosystem, scanner beam seeds new life.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(dot(hash22(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                 dot(hash22(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
             mix(dot(hash22(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                 dot(hash22(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var pos = p;
  for (var i = 0; i < 4; i++) {
    val += amp * noise(pos);
    pos = pos * 2.0;
    amp *= 0.5;
  }
  return val + 0.5;
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
  let aspect = res.x / res.y;

  let scanSpeed = u.zoom_params.x * 2.0;
  let organicScale = mix(5.0, 20.0, u.zoom_params.y);
  let revealRadius = u.zoom_params.z * 0.5;
  let pulseSpeed = u.zoom_params.w * 5.0;

  var mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;

  // Scan beam position, shared by the display mask and the sim.
  let scanPos = fract(time * scanSpeed * 0.2);
  let beamDx = (uv.x - scanPos) * aspect;
  // Idea 3: soft inverse-square beam light, I/(d^2 + r0^2) with a 0.04 core radius
  let beamLight = 0.0016 / (beamDx * beamDx + 0.0016);

  // === ECOSYSTEM SIMULATION ===
  let prevState = textureLoad(dataTextureC, coord, 0);
  var s1 = prevState.r;
  var s2 = prevState.g;
  var resourceLevel = prevState.b;
  var toxin = prevState.a;

  // HEAD fix: seed whenever the state is empty (mid-session load, restart), not only at time < 0.1
  if (time < 0.1 || (s1 + s2 + resourceLevel) <= 0.0) {
    s1 = 0.0; s2 = 0.0; resourceLevel = 0.5; toxin = 0.0;
    let n1 = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (n1 > 0.92) { s1 = 0.8; }
    let n2 = fract(sin(dot(uv + vec2<f32>(5.0), vec2<f32>(93.0, 17.0))) * 271.0);
    if (n2 > 0.95) { s2 = 0.7; }
  }

  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);
  resourceLevel = clamp(resourceLevel, 0.0, 2.0);
  toxin = clamp(toxin, 0.0, 2.0);

  let dims = vec2<i32>(i32(res.x), i32(res.y));
  let left = ld(coord - vec2<i32>(1, 0), dims);
  let right = ld(coord + vec2<i32>(1, 0), dims);
  let down = ld(coord - vec2<i32>(0, 1), dims);
  let up = ld(coord + vec2<i32>(0, 1), dims);

  let lapS1 = left.r + right.r + down.r + up.r - 4.0 * s1;
  let lapS2 = left.g + right.g + down.g + up.g - 4.0 * s2;
  let lapResource = left.b + right.b + down.b + up.b - 4.0 * resourceLevel;
  let lapToxin = left.a + right.a + down.a + up.a - 4.0 * toxin;

  let growthRate1 = mix(0.02f, 0.08f, 0.5f);
  let growthRate2 = mix(0.015f, 0.06f, 0.4f);
  let dt = 0.5;

  let food1 = s1 * resourceLevel * growthRate1;
  let food2 = s2 * resourceLevel * growthRate2;
  let competition = s1 * s2 * 0.1;
  let toxinProduction1 = s1 * 0.005;
  let toxinProduction2 = s2 * 0.003;
  let toxinDamage = toxin * 0.02;

  // Idea 3: the beam is a light source, it feeds photosynthesis where it passes
  let beamFeed = beamLight * 0.004 * (1.0 + bass * 0.5);
  resourceLevel += 0.001 + beamFeed - food1 - food2 + lapResource * 0.1;
  s1 += food1 - competition - toxinDamage + lapS1 * 0.05;
  s2 += food2 - competition - toxinDamage + lapS2 * 0.05;
  toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01 + lapToxin * 0.08;
  toxin *= 0.95;
  s1 *= 0.998;
  s2 *= 0.998;

  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);
  resourceLevel = clamp(resourceLevel, 0.0, 2.0);
  toxin = clamp(toxin, 0.0, 2.0);

  // Idea 1: the scan beam seeds spores inside its band, alternating species
  let sporeHash = fract(sin(dot(floor(uv * res) + vec2<f32>(floor(time * 6.0) * 7.31, 3.7), vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let sporeGate = step(0.985, sporeHash) * step(0.55, beamLight) * step(0.0001, scanSpeed);
  let sporePick = step(0.5, fract(sporeHash * 977.0));
  s1 = max(s1, 0.6 * sporeGate * sporePick);
  s2 = max(s2, 0.6 * sporeGate * (1.0 - sporePick));

  // Mouse nurtures
  let mouseDist = length(uv - mouse);
  let mouseDown = u.zoom_config.w;
  let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
  resourceLevel += mouseInfluence * 0.5;
  toxin -= mouseInfluence * 0.3;
  toxin = max(toxin, 0.0);

  // Ripples seed life
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 1.0 && rDist < 0.04) {
      let strength = smoothstep(0.04, 0.0, rDist) * max(0.0, 1.0 - age);
      let sign = select(1.0, 0.0, f32(i) % 2.0 < 1.0);
      s1 += strength * sign * 0.5;
      s2 += strength * (1.0 - sign) * 0.5;
    }
  }
  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);

  textureStore(dataTextureA, coord, vec4<f32>(s1, s2, resourceLevel, toxin));

  // === VISUALIZATION ===
  let colorS1 = vec3<f32>(0.0, 0.8, 1.0) * min(s1, 1.0);
  let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
  let colorResource = vec3<f32>(0.2, 0.7, 0.2) * min(resourceLevel, 1.0) * 0.3;
  let colorToxin = vec3<f32>(0.3, 0.0, 0.4) * min(toxin, 1.0) * 0.5;
  var ecosystemColor = colorS1 + colorS2 + colorResource + colorToxin;
  ecosystemColor = clamp(ecosystemColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let s1Grad = length(vec2<f32>(left.r - right.r, down.r - up.r));
  let s2Grad = length(vec2<f32>(left.g - right.g, down.g - up.g));
  let edgeHighlight = (s1Grad + s2Grad) * 2.0;
  ecosystemColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;
  // Idea 3: colony relief (gradient normal) lit from the side the beam is on
  let relief = vec2<f32>(left.r + left.g - right.r - right.g, down.r + down.g - up.r - up.g);
  let beamLit = max(relief.x * -sign(beamDx), 0.0) * beamLight;
  ecosystemColor += vec3<f32>(0.8, 1.0, 0.7) * beamLit * 1.5;

  // Organic warp overlay
  let warp = vec2<f32>(
    fbm(uv * organicScale + vec2<f32>(time * 0.1, 0.0)),
    fbm(uv * organicScale + vec2<f32>(0.0, time * 0.1))
  );
  ecosystemColor = mix(ecosystemColor, vec3<f32>(0.8, 0.2, 0.6), 0.15);
  let vein = smoothstep(0.4, 0.6, abs(fbm(uv * organicScale * 2.0 + time * 0.2) - 0.5));
  ecosystemColor += vec3<f32>(vein * sin(time * pulseSpeed) * 0.5 * (1.0 + bass * 0.4), 0.0, 0.0);

  // === REVEAL MASKS ===
  let mouseUV = mouse;
  let distVec = (uv - mouseUV) * vec2<f32>(aspect, 1.0);
  let mDist = length(distVec);
  let mouseMask = smoothstep(revealRadius, revealRadius * 0.8, mDist);

  let scanDist = abs(uv.x - scanPos);
  let scanMask = smoothstep(0.05, 0.0, scanDist) * 0.5;
  let scanNoise = noise(vec2<f32>(uv.y * 50.0, time * 10.0));
  let finalScanMask = scanMask * step(0.2, scanNoise);

  let reveal = clamp(mouseMask + finalScanMask, 0.0, 1.0);

  // Digital grid overlay on edge
  let grid = step(0.98, fract(uv.x * 50.0)) + step(0.98, fract(uv.y * 50.0 * aspect));
  let edge = smoothstep(0.0, 0.1, abs(reveal - 0.5)) * (1.0 - abs(reveal - 0.5) * 2.0);
  let gridOverlay = grid * edge * vec3<f32>(0.0, 1.0, 0.5);

  // Base image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Idea 2: Beer-Lambert tissue. Optical depth from colonies, nutrient and toxin; thin tissue
  // is translucent over the scanned photo (green absorbed least), dense colonies are opaque.
  let tau = (s1 + s2) * 1.6 + resourceLevel * 0.35 + toxin * 1.2;
  let transmit = exp(-tau * vec3<f32>(1.1, 0.6, 0.9));
  let revealed = aces(ecosystemColor + baseColor.rgb * transmit * 0.5);
  let cover = clamp(max(s1, s2) + toxin * 0.3, 0.0, 1.0);

  // Mix base with ecosystem
  var finalColor = vec4<f32>(mix(baseColor.rgb, revealed, reveal), mix(baseColor.a, max(0.6, cover), reveal));
  finalColor += vec4<f32>(gridOverlay, 0.0);

  textureStore(writeTexture, coord, finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
