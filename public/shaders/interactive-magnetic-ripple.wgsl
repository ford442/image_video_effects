// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
// ───────────────────────────────────────────────────────────────

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ Interactive Magnetic Ripple — Algorithmist Upgrade ═══
// FBM domain warping, curl-noise velocity field, multi-octave ripple,
// SDF mouse influence zone, Worley cellular modulation, click ripples.
// Chunks from: standard hash22, valueNoise, fbm, curlNoise, worley

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973);
  pp = pp + dot(pp, pp.yzx + 33.33);
  return fract((pp.xx + pp.yz) * pp.zy);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
             mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
             u.y);
}

fn fbm(p: vec2<f32>, t: f32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    s += a * valueNoise(p * f + t * 0.12 * f32(i + 1));
    f *= 2.1;
    a *= 0.5;
  }
  return s;
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.008;
  let n0 = fbm(p + vec2<f32>(0.0,  e), t);
  let n1 = fbm(p + vec2<f32>(0.0, -e), t);
  let n2 = fbm(p + vec2<f32>( e, 0.0), t);
  let n3 = fbm(p + vec2<f32>(-e, 0.0), t);
  return vec2<f32>(n0 - n1, n3 - n2) / (2.0 * e);
}

fn worleyNoise(p: vec2<f32>, t: f32) -> f32 {
  let i = floor(p);
  let f = fract(p);
  var d = 1.0;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let n = vec2<f32>(f32(x), f32(y));
      let h = hash22(i + n + vec2<f32>(t * 0.05, t * 0.03));
      d = min(d, length(n + h - f));
    }
  }
  return d;
}

fn domainWarpFbm(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), t),
                     fbm(p + vec2<f32>(5.2, 1.3), t));
  return fbm(p + q * 1.5, t);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let strength = u.zoom_params.x;
  let freq = u.zoom_params.y * 40.0;
  let decay = u.zoom_params.z * 3.0 + 0.5;
  let aberration = u.zoom_params.w * 0.08;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let audioPulse = 1.0 + bass * 0.4;

  var totalDisp = vec2<f32>(0.0);

  // ── Mouse-driven magnetic field ──
  if (mouse.x >= 0.0) {
    let dMouse = mouse - uv;
    let dAspect = vec2<f32>(dMouse.x * aspect, dMouse.y);
    let dist = length(dAspect);
    let dir = select(vec2<f32>(0.0), dMouse / dist, dist > 0.001);

    // SDF-based mouse influence zone with animated radius
    let zone = smoothstep(0.0, 0.3, 0.4 + fbm(vec2<f32>(time * 0.1, 0.0), time) * 0.08 - dist);

    // Curl-noise velocity field (divergence-free)
    let curl = curlNoise(uv * 3.0 + time * 0.3, time) * 0.25;

    // Multi-octave ripple with FBM phase warp + Worley cells
    let phase = dist * freq * audioPulse - time * 4.0;
    let fbmWarp = fbm(vec2<f32>(dist * 4.0, time * 0.4), time) * 2.5;
    let cells = worleyNoise(uv * 7.0 + time * 0.15, time);
    let ripple = cos(phase + fbmWarp) * 0.55 + sin(phase * 1.618 + cells * 6.283) * 0.45;
    let rippleAtten = exp(-dist * decay);
    totalDisp += dir * ripple * rippleAtten * 0.06;

    // Magnetic pull with FBM-modulated radial falloff
    let magFalloff = fbm(vec2<f32>(dist * 6.0, time * 0.2), time) * 0.3 + 0.7;
    let magPull = dir * strength * zone * magFalloff / (dist * dist + 0.04) * 0.06;
    totalDisp += magPull + curl * zone * 0.04;

    // Secondary fractal vorticity in the magnetic core
    let turb = domainWarpFbm(uv * 6.0 + dir * dist * 4.0, time) * 0.08;
    totalDisp += dir * turb * zone * strength;
  }

  // ── Stored click ripples ──
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rPos = rp.xy;
    let rAge = time - rp.z;
    let rDiff = vec2<f32>((rPos.x - uv.x) * aspect, rPos.y - uv.y);
    let rDist = length(rDiff);
    let rDir = select(vec2<f32>(0.0), vec2<f32>(rDiff.x / aspect, rDiff.y) / rDist, rDist > 0.001);
    let rRipple = cos(rDist * freq * 0.6 - rAge * 5.0) * exp(-rDist * decay - rAge * 1.2);
    totalDisp += rDir * rRipple * 0.035;
  }

  // Domain-warped displacement amplification
  let warp = domainWarpFbm(uv * 4.0 + time * 0.2, time) * 0.015;
  totalDisp = totalDisp + totalDisp * warp;

  // Chromatic aberration with noise-driven asymmetry
  let abNoise = fbm(uv * 6.0 + vec2<f32>(time * 0.1, 0.0), time) * 0.015;
  let abScale = 1.0 + aberration + abNoise;
  let rUV = uv - totalDisp * abScale;
  let gUV = uv - totalDisp;
  let bUV = uv - totalDisp * (2.0 - abScale);

  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, 1.0));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
