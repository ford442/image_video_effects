// ═══════════════════════════════════════════════════════════════════
//  DLA Crystals
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-19
//  Ideas: tip screening; branch-angle facets; attraction reach
//  A packing: raw sim (frozen, age, hue, branchId). ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=WalkerSpeed, y=AttractStrength, z=Stickiness, w=BranchAngle

const NEIGHBOR_CHECK_RADIUS: i32 = 1;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 1.0)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(c: vec2<i32>, size: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

// max frozen neighbor, and how many of the 8 are frozen (a tip vs a fjord)
fn neighborStats(coord: vec2<i32>, size: vec2<i32>) -> vec2<f32> {
  var maxFrozen = 0.0;
  var count = 0.0;
  for (var dy = -NEIGHBOR_CHECK_RADIUS; dy <= NEIGHBOR_CHECK_RADIUS; dy = dy + 1) {
    for (var dx = -NEIGHBOR_CHECK_RADIUS; dx <= NEIGHBOR_CHECK_RADIUS; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let n = loadC(coord + vec2<i32>(dx, dy), size);
      maxFrozen = max(maxFrozen, n.r);
      count = count + step(0.5, n.r);
    }
  }
  return vec2<f32>(maxFrozen, count);
}

fn frozenNeighborColor(coord: vec2<i32>, size: vec2<i32>) -> vec3<f32> {
  var colorSum = vec3<f32>(0.0);
  var count = 0.0;
  for (var dy = -NEIGHBOR_CHECK_RADIUS; dy <= NEIGHBOR_CHECK_RADIUS; dy = dy + 1) {
    for (var dx = -NEIGHBOR_CHECK_RADIUS; dx <= NEIGHBOR_CHECK_RADIUS; dx = dx + 1) {
      let n = loadC(coord + vec2<i32>(dx, dy), size);
      if (n.r > 0.5) {
        let uv = (vec2<f32>(coord + vec2<i32>(dx, dy)) + vec2<f32>(0.5)) / vec2<f32>(size);
        let src = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        colorSum = colorSum + src.rgb;
        count = count + 1.0;
      }
    }
  }
  if (count > 0.0) {
    return colorSum / count;
  }
  return vec3<f32>(0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let sizeI = vec2<i32>(i32(size.x), i32(size.y));
  let coordI = vec2<i32>(coord);
  let uv = (vec2<f32>(coordI) + vec2<f32>(0.5)) / vec2<f32>(sizeI);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;

  // Parameters — roles unchanged. Walker speed and attraction now reach the stick test.
  let walkerSpeed = mix(0.5, 3.0, u.zoom_params.x);
  let attractStrength = mix(0.0, 0.5, u.zoom_params.y);
  let stickiness = mix(0.3, 1.0, u.zoom_params.z);
  let branchAngle = mix(0.1, 1.0, u.zoom_params.w);
  // ── Idea: attraction reach — faster walkers sense farther ──
  let reach = clamp(i32(round(walkerSpeed * 2.0)), 2, 6);

  let state = loadC(coordI, sizeI);
  var frozen = state.r;
  var age = state.g;
  var crystalHue = state.b;
  var branchId = state.a;

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Initialize seed crystals at ripple points
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 0.5) {
        let dist = length(uv - ripple.xy);
        if (dist < 0.02 && frozen < 0.5) {
          frozen = 1.0;
          age = time;
          crystalHue = hash21(ripple.xy) * 0.3 + 0.6;
          branchId = f32(i) / 50.0;
        }
      }
    }
  }

  // Initialize seed at mouse position
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(uv - mouse);
  if (mouseDist < 0.01 && frozen < 0.5) {
    frozen = 1.0;
    age = time;
    crystalHue = 0.55;
    branchId = 0.0;
  }

  // If not frozen, freeze when a neighbor is already crystal
  if (frozen < 0.5) {
    var attractDir = vec2<f32>(0.0);
    var minFrozenDist = 100.0;
    for (var dy = -6; dy <= 6; dy = dy + 1) {
      for (var dx = -6; dx <= 6; dx = dx + 1) {
        let dist = length(vec2<f32>(f32(dx), f32(dy)));
        if (dist <= f32(reach) && dist > 0.0) {
          let searchState = loadC(coordI + vec2<i32>(dx, dy), sizeI);
          if (searchState.r > 0.5 && dist < minFrozenDist) {
            minFrozenDist = dist;
            attractDir = vec2<f32>(f32(dx), f32(dy)) / max(dist, 0.001);
          }
        }
      }
    }

    let stats = neighborStats(coordI, sizeI);
    let neighborFrozen = stats.x;
    let nCount = stats.y;
    // ── Idea: tip screening — a fjord (many frozen neighbors) sticks less than a tip ──
    let tipGate = mix(1.0, 0.28, clamp(nCount / 5.0, 0.0, 1.0));
    // ── Idea: branch-angle facets — stick peaks on a 2-to-6-fold set of directions ──
    let fold = 2.0 + branchAngle * 4.0;
    let growthAngle = atan2(attractDir.y, attractDir.x);
    let facet = pow(abs(cos(growthAngle * fold)), 4.0);
    let stickGate = clamp(
      mix(stickiness * 0.45, stickiness, attractStrength * 2.0) * (0.35 + 0.65 * facet) * tipGate * (1.0 + bass * 0.12),
      0.0, 1.0);

    if (neighborFrozen > 0.5) {
      let stickChance = hash21(uv * 500.0 + vec2<f32>(time));
      if (stickChance < stickGate) {
        frozen = 1.0;
        age = time;
        let neighborColor = frozenNeighborColor(coordI, sizeI);
        crystalHue = dot(neighborColor, vec3<f32>(0.333)) + hash21(uv * 123.0) * 0.1;
        branchId = (growthAngle / 6.2831853 + 0.5) * branchAngle;
      }
    }
  } else {
    age = age + 0.001;
  }

  textureStore(dataTextureA, coordI, vec4<f32>(frozen, age, crystalHue, branchId));

  var finalColor = sourceColor.rgb;
  var tipVis = 0.0;
  if (frozen > 0.5) {
    let crystalAge = clamp(time - age, 0.0, 8.0);
    let hue = crystalHue + branchId * 0.2;
    let h = hue * 6.0;
    let c = 0.8;
    let x = c * (1.0 - abs((h % 2.0) - 1.0));
    let m = 0.2;
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    let crystalColor = rgb + vec3<f32>(m);
    let glow = exp(-crystalAge * 0.5) * 0.5 + 0.5;
    let edgeStats = neighborStats(coordI, sizeI);
    let edgeStrength = 1.0 - edgeStats.x;
    tipVis = 1.0 - edgeStats.y / 8.0;
    let edgeGlow = vec3<f32>(1.0) * edgeStrength * 0.3;
    finalColor = crystalColor * glow + edgeGlow;
    finalColor = finalColor + vec3<f32>(0.72, 0.88, 1.0) * tipVis * edgeStrength * 0.55;
    let sparkle = pow(hash21(uv * 1000.0 + vec2<f32>(time * (4.0 + treble * 6.0))), 8.0) * (0.12 + treble * 0.4);
    finalColor = finalColor + vec3<f32>(sparkle);
  } else {
    finalColor = sourceColor.rgb * 0.7;
    var closestFrozen = 100.0;
    let glowReach = f32(clamp(reach + 4, 4, 10));
    for (var dy = -10; dy <= 10; dy = dy + 1) {
      for (var dx = -10; dx <= 10; dx = dx + 1) {
        let dist = length(vec2<f32>(f32(dx), f32(dy)));
        if (dist <= glowReach && dist > 0.0) {
          let searchState = loadC(coordI + vec2<i32>(dx, dy), sizeI);
          if (searchState.r > 0.5) {
            closestFrozen = min(closestFrozen, dist);
          }
        }
      }
    }
    if (closestFrozen < glowReach) {
      let fieldGlow = (glowReach - closestFrozen) / max(glowReach, 0.001) * attractStrength;
      finalColor = finalColor + vec3<f32>(0.2, 0.5, 1.0) * fieldGlow;
    }
  }

  let display = acesToneMap(max(finalColor, vec3<f32>(0.0)));
  let alpha = select(0.28 + sourceColor.a * 0.2, clamp(0.55 + tipVis * 0.4, 0.0, 1.0), frozen > 0.5);
  let depthOut = clamp(mix(depth, 0.2 + tipVis * 0.45, step(0.5, frozen)), 0.0, 1.0);
  textureStore(writeTexture, coordI, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coordI, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
