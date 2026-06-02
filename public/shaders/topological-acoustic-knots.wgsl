// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots v2
//  Category: generative
//  Features: nematic-Q-tensor, topological-charge, trefoil-sdf,
//            schlieren-texture, audio-driven, mouse-anchoring
//  Complexity: Very High
//  Chunks From: nematic tensor + defect tracking + ACES tm
//  Created: 2026-05-31
//  By: 4-Agent Upgrade Swarm
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
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Trefoil knot SDF (2D projection slice)
fn trefoilSDF(uv: vec2<f32>, t: f32) -> f32 {
  let p = (uv - 0.5) * 6.283185;
  // Projected trefoil parametric
  let kx = sin(p.x) + 2.0 * sin(2.0 * p.x);
  let ky = cos(p.x) - 2.0 * cos(2.0 * p.x);
  let kz = -sin(3.0 * p.x);
  let proj = vec2<f32>(kx * 0.12 + 0.5, ky * 0.12 + 0.5);
  let d = length(uv - proj);
  let p2 = vec2<f32>(sin(p.y + t) + 2.0 * sin(2.0 * p.y + t), cos(p.y + t) - 2.0 * cos(2.0 * p.y + t)) * 0.12 + 0.5;
  let d2 = length(uv - p2);
  return min(d, d2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.8;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  // Read previous nematic state: Qxx, Qxy, S, defect
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let prevQxx = prev.r;
  let prevQxy = prev.g;
  let prevS = prev.b;

  // Recover director angle from Q tensor
  let prevAngle = 0.5 * atan2(prevQxy * 2.0, prevQxx * 2.0);

  // Sample neighbors for relaxation
  let ps = 1.0 / res;
  let n = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let s = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let e = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let w = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Average neighbor angles (handle periodicity via sin/cos)
  let sinSum = sin(n.r * 2.0) + sin(s.r * 2.0) + sin(e.r * 2.0) + sin(w.r * 2.0);
  let cosSum = cos(n.r * 2.0) + cos(s.r * 2.0) + cos(e.r * 2.0) + cos(w.r * 2.0);
  let avgAngle = 0.5 * atan2(sinSum, cosSum);

  // Relaxation with mobility
  let mobility = 0.3 + mids * 0.7 + p2 * 0.5;
  var angle = mix(prevAngle, avgAngle, mobility * 0.25);

  // Bass creates defect pairs (Kibble-Zurek: quench noise)
  let quenchNoise = (hash12(uv * 23.0 + time * 0.15) - 0.5) * bass * 0.18;
  angle += quenchNoise;

  // Treble adds acoustic phonon waves
  let phonon = sin(uv.x * 18.0 + time * 5.0 + treble * 3.0) * cos(uv.y * 14.0 - time * 4.0) * treble * 0.08;
  angle += phonon;

  // Trefoil knot SDF constraint: director avoids knot curve
  let knotDist = trefoilSDF(uv, time * 0.2);
  let knotInfluence = smoothstep(0.08, 0.0, knotDist) * (0.5 + p3 * 0.5);
  let tangentAngle = atan2(cos(uv.x * 6.283185 + time), sin(uv.y * 6.283185));
  angle = mix(angle, tangentAngle, knotInfluence * 0.6);

  // Mouse homeotropic anchoring: pins director radially
  let mouseDist = length(uv - mouse);
  let anchor = smoothstep(0.18, 0.0, mouseDist) * mouseDown * (1.0 + p4 * 2.0);
  let radialAngle = atan2(uv.y - mouse.y, uv.x - mouse.x);
  angle = mix(angle, radialAngle, anchor * 0.85);

  // Ripples spawn defect loops
  let rCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rd = length(uv - rp.xy);
    let rt = time - rp.z;
    let rippleStrength = exp(-rd * 6.0) * smoothstep(2.5, 0.0, rt) * 0.12;
    angle += rippleStrength * sin(rt * 8.0 + rd * 15.0);
  }

  // Reconstruct Q tensor: Q = s(nn^T - I/3)
  let nx = cos(angle);
  let ny = sin(angle);
  let relaxS = mix(prevS, 0.7, 0.03);
  let disorder = bass * 0.25 + quenchNoise * 2.0;
  let S = clamp(relaxS - abs(disorder), 0.0, 1.0);
  let Qxx = S * (nx * nx - 0.3333);
  let Qxy = S * nx * ny;

  // Topological charge via line-integral approximation (curl of director)
  let dAngle_dx = atan2(sin(e.r - w.r), cos(e.r - w.r)) * res.x * 0.5;
  let dAngle_dy = atan2(sin(n.r - s.r), cos(n.r - s.r)) * res.y * 0.5;
  let chargeRaw = (dAngle_dx + dAngle_dy) * 0.15915; // / (2*pi)
  let charge = clamp(chargeRaw, -1.0, 1.0);

  // Defect density
  let defectDensity = smoothstep(0.15, 0.5, abs(charge));

  // Store state
  textureStore(dataTextureA, gid.xy, vec4<f32>(Qxx, Qxy, S, defectDensity));

  // Schlieren texture: dark where director aligns with polarizer
  let polarizer = vec2<f32>(cos(time * 0.3), sin(time * 0.3));
  let alignment = abs(dot(vec2<f32>(nx, ny), polarizer));
  let schlieren = 1.0 - alignment * alignment;

  // Defect core colors: integer (red) vs half-integer (blue)
  let isInteger = abs(abs(charge) - 1.0) < 0.3;
  let defectCol = select(vec3<f32>(0.3, 0.5, 1.0), vec3<f32>(1.0, 0.3, 0.2), isInteger);
  let defectGlow = defectDensity * defectCol * (1.5 + treble * 1.2);

  // HDR bloom on +1 defects
  let plusOneBloom = select(0.0, 1.0, charge > 0.65) * defectDensity * vec3<f32>(1.0, 0.7, 0.4) * 2.0;

  let base = vec3<f32>(0.55, 0.6, 0.65) * (0.3 + schlieren * 0.7);
  let hdr = base + defectGlow + plusOneBloom + vec3<f32>(phonon * 0.3 + 0.1);
  let tone = acesToneMap(hdr * (0.8 + p1 * 0.3));

  // Alpha: order parameter S × (1.0 + defect_charge_density)
  let alpha = clamp(S * (1.0 + defectDensity * 0.6) * 0.7, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(defectDensity * 0.8 + S * 0.2, 0.0, 0.0, 0.0));
}
