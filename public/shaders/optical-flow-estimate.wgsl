// ═══════════════════════════════════════════════════════════════════
//  Optical Flow Dream
//  Category: simulation
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: 3x3 regularized Lucas-Kanade spatio-temporal structure tensor (§12.2A); sub-pixel clamped MacCormack dream advection (§12.2D) & edge-tangent curl deflection
//  A packing: linear HDR dream RGB + semantic trail coverage (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hist(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

// Sub-pixel bilinear sample over exact textureLoad(dataTextureC) taps
fn histBilinear(uvCoord: vec2<f32>, res: vec2<f32>, hi: vec2<i32>) -> vec4<f32> {
  let pos = clamp(uvCoord, vec2<f32>(0.0), vec2<f32>(1.0)) * res - vec2<f32>(0.5);
  let p0 = vec2<i32>(floor(pos));
  let f = fract(pos);
  let s00 = hist(p0, hi);
  let s10 = hist(p0 + vec2<i32>(1, 0), hi);
  let s01 = hist(p0 + vec2<i32>(0, 1), hi);
  let s11 = hist(p0 + vec2<i32>(1, 1), hi);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  let p = vec2<i32>(gid.xy);
  let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size);
  let invRes = 1.0 / res;
  let uv = (vec2<f32>(p) + 0.5) * invRes;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

  let cur = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let center = hist(p, hi);

  // ── Idea 1: 3x3 regularized Lucas-Kanade spatio-temporal structure tensor (§12.2A) ──
  // Resolves single-pixel aperture chatter and extracts local edge tangent & coherence
  var jxx = 0.0;
  var jyy = 0.0;
  var jxy = 0.0;
  var bxt = 0.0;
  var byt = 0.0;

  for (var wy = -1; wy <= 1; wy = wy + 1) {
    for (var wx = -1; wx <= 1; wx = wx + 1) {
      let off = vec2<i32>(wx, wy);
      let q = p + off;
      let wuv = clamp(uv + vec2<f32>(f32(wx), f32(wy)) * invRes, vec2<f32>(0.0), vec2<f32>(1.0));
      let wt = select(0.5, 1.0, wx == 0) * select(0.5, 1.0, wy == 0) * 0.25;

      let cHere = luma(hist(q, hi).rgb);
      let cR = luma(hist(q + vec2<i32>(1, 0), hi).rgb);
      let cL = luma(hist(q + vec2<i32>(-1, 0), hi).rgb);
      let cD = luma(hist(q + vec2<i32>(0, 1), hi).rgb);
      let cU = luma(hist(q + vec2<i32>(0, -1), hi).rgb);
      let ix = 0.5 * (cR - cL);
      let iy = 0.5 * (cD - cU);
      let liveHere = luma(textureSampleLevel(readTexture, u_sampler, wuv, 0.0).rgb);
      let it = liveHere - cHere;

      jxx += wt * ix * ix;
      jyy += wt * iy * iy;
      jxy += wt * ix * iy;
      bxt += wt * ix * it;
      byt += wt * iy * it;
    }
  }

  let reg = 0.0022;
  let a11 = jxx + reg;
  let a22 = jyy + reg;
  let det = max(a11 * a22 - jxy * jxy, 1e-6);
  let lkVec = vec2<f32>(-(a22 * bxt - jxy * byt), -(-jxy * bxt + a11 * byt)) / det;

  let tr = jxx + jyy;
  let disc = sqrt(max((jxx - jyy) * (jxx - jyy) * 0.25 + jxy * jxy, 0.0));
  let coh = (2.0 * disc) / max(tr, 1e-4);
  let edgeTheta = 0.5 * atan2(2.0 * jxy, jxx - jyy);
  let edgeTangent = vec2<f32>(-sin(edgeTheta), cos(edgeTheta));

  let flowScale = mix(0.25, 3.5, u.zoom_params.x);
  var flow = lkVec * flowScale * (0.012 + audio.x * 0.006);
  // Guide dream streamlines smoothly along coherent image contours
  flow += edgeTangent * dot(flow, edgeTangent) * coh * 0.42;

  let mq = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
  let md = length(mq) + 0.0001;
  let swirl = vec2<f32>(-mq.y, mq.x) / md * exp(-md * 10.0);
  flow += swirl * (0.003 + select(0.0, 0.028 + audio.y * 0.010, u.zoom_config.w > 0.5));

  var fronts = 0.0;
  let count = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < count; i = i + 1u) {
    let e = u.ripples[i];
    let age = time - e.z;
    let isLive = f32(age >= 0.0 && age < 1.4);
    let safeAge = clamp(age, 0.0, 1.4);
    let q = (uv - e.xy) * vec2<f32>(aspect, 1.0);
    let d = length(q);
    let ring = isLive * exp(-safeAge * 2.0) * exp(-abs(d - safeAge * 0.38) * 62.0);
    flow += normalize(q + vec2<f32>(0.0001)) * ring * 0.035;
    fronts += ring;
  }
  flow = clamp(flow, vec2<f32>(-0.08), vec2<f32>(0.08));

  // ── Idea 2: sub-pixel clamped MacCormack dream advection (§12.2D) & curved RGB dispersion ──
  let uvBack = clamp(uv - flow, vec2<f32>(0.0), vec2<f32>(1.0));
  let posBack = uvBack * res - vec2<f32>(0.5);
  let bp0 = vec2<i32>(floor(posBack));
  let n00 = hist(bp0, hi);
  let n10 = hist(bp0 + vec2<i32>(1, 0), hi);
  let n01 = hist(bp0 + vec2<i32>(0, 1), hi);
  let n11 = hist(bp0 + vec2<i32>(1, 1), hi);
  let minBox = min(min(n00, n10), min(n01, n11));
  let maxBox = max(max(n00, n10), max(n01, n11));

  let phiFwd = histBilinear(uvBack, res, hi);
  let phiRet = histBilinear(clamp(uvBack + flow, vec2<f32>(0.0), vec2<f32>(1.0)), res, hi);
  let adv = clamp(phiFwd + 0.5 * (center - phiRet), minBox, maxBox);

  let flowMag = length(flow);
  let flowDir = select(edgeTangent, flow / max(flowMag, 1e-5), flowMag > 1e-4);
  let chroma = mix(0.0, 1.8, u.zoom_params.z) * (1.0 + audio.z * 0.5);
  let splitUV = (flowDir * 3.0 + edgeTangent * coh * 1.2) * chroma * invRes;
  let rSample = histBilinear(uvBack + splitUV, res, hi).r;
  let bSample = histBilinear(uvBack - splitUV, res, hi).b;
  let dreamSample = vec3<f32>(rSample, adv.g, bSample);

  let decay = clamp(mix(0.80, 0.987, u.zoom_params.y) + audio.x * 0.01, 0.75, 0.995);
  let dreamMix = mix(0.25, 0.94, u.zoom_params.w);
  let hue = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + atan2(flow.y, flow.x) * 2.0 + time * (0.3 + audio.y));

  var hdr = mix(cur.rgb, dreamSample * decay, dreamMix);
  hdr += hue * (flowMag * 9.0 + coh * flowMag * 4.5 + fronts * 0.38);

  let alpha = clamp(cur.a * (1.0 - dreamMix * 0.25) + adv.a * decay * dreamMix + flowMag * 3.0 + fronts * 0.25, 0.0, 1.0);
  let state = vec4<f32>(clamp(hdr, vec3<f32>(0.0), vec3<f32>(8.0)), alpha);
  textureStore(dataTextureA, p, state);

  let mapped = aces(state.rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 1.0 - clamp(flowMag * 10.0, 0.0, 1.0), 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}
