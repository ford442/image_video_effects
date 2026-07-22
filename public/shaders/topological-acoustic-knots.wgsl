// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots v3
//  Category: generative
//  Features: nematic-Q-tensor, topological-charge, trefoil-sdf,
//            schlieren-texture, audio-driven, mouse-anchoring
//  Complexity: Very High
//  Chunks From: nematic tensor + defect tracking + ACES tm
//  Created: 2026-05-31
//  By: 4-Agent Upgrade Swarm
//  v3 (2026-07-22, Algorithmist swarm): honest slider wiring -
//    p1 -> Kibble-Zurek quench amplitude (true defect nucleation rate)
//    p3 -> opposite-sign annihilation rate + cascade exposure pulse
//    sweeping polarizer accumulated in extraBuffer[136], driven by mids
//    global defect census in extraBuffer[133..135] (state: 133..255 ONLY)
//  dataTextureA holds SIGNED Q-tensor sim state: never clamp/tonemap it.
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

  // Diagonal neighbor reads (ADDITIVE only - used for opposite-sign defect
  // detection; the order-dependent charge line integral below still consumes
  // n/s/e/w in its original order and is left untouched).
  let ne = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + ps, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let nw = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(-ps.x, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let se = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, -ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sw = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - ps, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Relaxation with mobility
  let mobility = 0.3 + mids * 0.7 + p2 * 0.5;
  var angle = mix(prevAngle, avgAngle, mobility * 0.25);

  // Bass creates defect pairs (Kibble-Zurek: quench noise)
  // p1 ('Defect Density') is now HONEST: it scales the quench amplitude,
  // so the slider directly controls how many defect pairs nucleate.
  let quenchNoise = (hash12(uv * 23.0 + time * 0.15) - 0.5) * bass * 0.18 * (0.5 + p1);
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
  // NOTE: order-dependent - neighbor reads must stay in this exact order.
  let dAngle_dx = atan2(sin(e.r - w.r), cos(e.r - w.r)) * res.x * 0.5;
  let dAngle_dy = atan2(sin(n.r - s.r), cos(n.r - s.r)) * res.y * 0.5;
  let chargeRaw = (dAngle_dx + dAngle_dy) * 0.15915; // / (2*pi)

  // ── Annihilation dynamics (Defect Pairing, p3) ─────────────────────
  // Estimate the winding of the two adjacent vertical plaquettes from the
  // diagonal reads. Where the east and west estimates carry OPPOSITE sign,
  // a +defect and a -defect sit side by side: p3 damps the local winding
  // (pair annihilation) and melts the order parameter at the shared core.
  let chargeEast = atan2(sin(ne.r - se.r), cos(ne.r - se.r)) * res.y * 0.5 * 0.15915;
  let chargeWest = atan2(sin(nw.r - sw.r), cos(nw.r - sw.r)) * res.y * 0.5 * 0.15915;
  let oppPair = select(0.0, 1.0, chargeEast * chargeWest < -0.0005);
  let annihilation = oppPair * p3 * smoothstep(0.05, 0.4, abs(chargeRaw));
  let charge = clamp(chargeRaw * (1.0 - annihilation * 0.55), -1.0, 1.0);

  // Defect density
  let defectDensity = smoothstep(0.15, 0.5, abs(charge));

  // Annihilation melts the core: reduce S locally (re-derived Q stays signed)
  let Sann = clamp(S * (1.0 - annihilation * 0.5), 0.0, 1.0);
  let QxxAnn = Sann * (nx * nx - 0.3333);
  let QxyAnn = Sann * nx * ny;

  // Store state (SIGNED Q-tensor sim state - never clamp/tonemap this write)
  textureStore(dataTextureA, gid.xy, vec4<f32>(QxxAnn, QxyAnn, Sann, defectDensity));

  // ── Global defect census + cascade pulse (extraBuffer state 133..136) ──
  // [133] = smoothed defect-count estimate, [134] = previous estimate,
  // [135] = annihilation-cascade exposure pulse, [136] = polarizer angle.
  let cascadePulse = extraBuffer[135];
  let polarAngle = extraBuffer[136];
  if (gid.x == 0u && gid.y == 0u) {
    // Coarse 16x16 census of last frame's defect-density field
    var census = 0.0;
    for (var cy: u32 = 0u; cy < 16u; cy = cy + 1u) {
      for (var cx: u32 = 0u; cx < 16u; cx = cx + 1u) {
        let suv = (vec2<f32>(f32(cx), f32(cy)) + vec2<f32>(0.5, 0.5)) / 16.0;
        census = census + textureSampleLevel(dataTextureC, u_sampler, suv, 0.0).a;
      }
    }
    let prevCount = extraBuffer[133];
    let count = mix(prevCount, census, 0.25);
    extraBuffer[134] = prevCount;
    extraBuffer[133] = count;
    // A sharp drop in the census = annihilation cascade: fire a brief
    // global exposure pulse, then let it decay ~10% per frame.
    let drop = prevCount - count;
    var pulse = extraBuffer[135] * 0.90;
    if (drop > 0.6) {
      pulse = min(1.0, pulse + drop * 0.35);
    }
    extraBuffer[135] = pulse;
    // Sweeping polarizer: slow constant drift, accelerated by mids energy
    // so the schlieren polarization bands sweep in sync with the music.
    extraBuffer[136] = extraBuffer[136] + 0.004 + mids * 0.035;
  }

  // Schlieren texture: dark where director aligns with polarizer.
  // Polarizer angle sweeps continuously (accumulated in extraBuffer[136]),
  // sped up by mids - polarization bands rotate in sync with the music.
  let polarizer = vec2<f32>(cos(polarAngle), sin(polarAngle));
  let alignment = abs(dot(vec2<f32>(nx, ny), polarizer));
  let schlieren = 1.0 - alignment * alignment;

  // Defect core colors: integer (red) vs half-integer (blue)
  let isInteger = abs(abs(charge) - 1.0) < 0.3;
  let defectCol = select(vec3<f32>(0.3, 0.5, 1.0), vec3<f32>(1.0, 0.3, 0.2), isInteger);
  let defectGlow = defectDensity * defectCol * (1.5 + treble * 1.2);

  // HDR bloom on +1 defects
  let plusOneBloom = select(0.0, 1.0, charge > 0.65) * defectDensity * vec3<f32>(1.0, 0.7, 0.4) * 2.0;

  let base = vec3<f32>(0.55, 0.6, 0.65) * (0.3 + schlieren * 0.7);
  var hdr = base + defectGlow + plusOneBloom + vec3<f32>(phonon * 0.3 + 0.1);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass);
  hdr = vec3<f32>(hdr.r + caStr, hdr.g, hdr.b - caStr * 0.5);

  // Exposure: steady base + brief HDR pulse when an annihilation cascade
  // fires (defect census dropped sharply this frame).
  let tone = acesToneMap(hdr * (0.85 + cascadePulse * 0.7));

  // Alpha: order parameter S × (1.0 + defect_charge_density)
  let alpha = clamp(S * (1.0 + defectDensity * 0.6) * 0.7, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(defectDensity * 0.8 + S * 0.2, 0.0, 0.0, 0.0));
}
