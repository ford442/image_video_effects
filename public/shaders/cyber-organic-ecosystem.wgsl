// ═══════════════════════════════════════════════════════════════════
//  cyber-organic-ecosystem
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, organic
//  Complexity: Very High
//  Chunks From: cyber-organic.wgsl, alpha-multi-state-ecosystem.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  Scans the image to reveal a living multi-species ecosystem
//  beneath. The organic layer is a real ecosystem simulation with
//  species competing for resources while producing toxins. Mouse
//  nurtures the ecosystem, scanner beam seeds new life.
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

@compute @workgroup_size(8, 8, 1)
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

  // === ECOSYSTEM SIMULATION ===
  let prevState = textureLoad(dataTextureC, coord, 0);
  var s1 = prevState.r;
  var s2 = prevState.g;
  var resource = prevState.b;
  var toxin = prevState.a;

  if (time < 0.1) {
    s1 = 0.0; s2 = 0.0; resource = 0.5; toxin = 0.0;
    let n1 = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (n1 > 0.92) { s1 = 0.8; }
    let n2 = fract(sin(dot(uv + vec2<f32>(5.0), vec2<f32>(93.0, 17.0))) * 271.0);
    if (n2 > 0.95) { s2 = 0.7; }
  }

  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);
  resource = clamp(resource, 0.0, 2.0);
  toxin = clamp(toxin, 0.0, 2.0);

  let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let lapS1 = left.r + right.r + down.r + up.r - 4.0 * s1;
  let lapS2 = left.g + right.g + down.g + up.g - 4.0 * s2;
  let lapResource = left.b + right.b + down.b + up.b - 4.0 * resource;
  let lapToxin = left.a + right.a + down.a + up.a - 4.0 * toxin;

  let growthRate1 = mix(0.02, 0.08, 0.5);
  let growthRate2 = mix(0.015, 0.06, 0.4);
  let dt = 0.5;

  let food1 = s1 * resource * growthRate1;
  let food2 = s2 * resource * growthRate2;
  let competition = s1 * s2 * 0.1;
  let toxinProduction1 = s1 * 0.005;
  let toxinProduction2 = s2 * 0.003;
  let toxinDamage = toxin * 0.02;

  resource += 0.001 - food1 - food2 + lapResource * 0.1;
  s1 += food1 - competition - toxinDamage + lapS1 * 0.05;
  s2 += food2 - competition - toxinDamage + lapS2 * 0.05;
  toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01 + lapToxin * 0.08;
  toxin *= 0.95;
  s1 *= 0.998;
  s2 *= 0.998;

  s1 = clamp(s1, 0.0, 2.0);
  s2 = clamp(s2, 0.0, 2.0);
  resource = clamp(resource, 0.0, 2.0);
  toxin = clamp(toxin, 0.0, 2.0);

  // Mouse nurtures
  let mouseDist = length(uv - mouse);
  let mouseDown = u.zoom_config.w;
  let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
  resource += mouseInfluence * 0.5;
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

  textureStore(dataTextureA, coord, vec4<f32>(s1, s2, resource, toxin));

  // === VISUALIZATION ===
  let colorS1 = vec3<f32>(0.0, 0.8, 1.0) * min(s1, 1.0);
  let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
  let colorResource = vec3<f32>(0.2, 0.7, 0.2) * min(resource, 1.0) * 0.3;
  let colorToxin = vec3<f32>(0.3, 0.0, 0.4) * min(toxin, 1.0) * 0.5;
  var ecosystemColor = colorS1 + colorS2 + colorResource + colorToxin;
  ecosystemColor = clamp(ecosystemColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let s1Grad = length(vec2<f32>(left.r - right.r, down.r - up.r));
  let s2Grad = length(vec2<f32>(left.g - right.g, down.g - up.g));
  let edgeHighlight = (s1Grad + s2Grad) * 2.0;
  ecosystemColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;
  ecosystemColor = clamp(ecosystemColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Organic warp overlay
  let warp = vec2<f32>(
    fbm(uv * organicScale + vec2<f32>(time * 0.1, 0.0)),
    fbm(uv * organicScale + vec2<f32>(0.0, time * 0.1))
  );
  ecosystemColor = mix(ecosystemColor, vec3<f32>(0.8, 0.2, 0.6), 0.15);
  let vein = smoothstep(0.4, 0.6, abs(fbm(uv * organicScale * 2.0 + time * 0.2) - 0.5));
  ecosystemColor += vec3<f32>(vein * sin(time * pulseSpeed) * 0.5, 0.0, 0.0);

  // === REVEAL MASKS ===
  let mouseUV = mouse;
  let distVec = (uv - mouseUV) * vec2<f32>(aspect, 1.0);
  let mDist = length(distVec);
  let mouseMask = smoothstep(revealRadius, revealRadius * 0.8, mDist);

  let scanPos = fract(time * scanSpeed * 0.2);
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

  // Mix base with ecosystem
  var finalColor = mix(baseColor, vec4<f32>(ecosystemColor, 1.0), reveal);
  finalColor += vec4<f32>(gridOverlay, 0.0);

  textureStore(writeTexture, coord, finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
