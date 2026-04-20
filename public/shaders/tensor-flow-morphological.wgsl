// ═══════════════════════════════════════════════════════════════════
//  Tensor Flow Morphological
//  Category: advanced-hybrid
//  Features: advanced-hybrid, tensor-warp, morphological, depth-aware
//  Complexity: Very High
//  Chunks From: tensor-flow-sculpting.wgsl, conv-morphological-erosion-dilation.wgsl
//  Created: 2026-04-18
//  By: Agent CB-3 — Convolution Post-Processor
// ═══════════════════════════════════════════════════════════════════
//  Depth-aware tensor eigenwarp with morphological post-processing.
//  Erosion darkens compressed tensor regions, dilation brightens
//  tensile regions. Morphological gradient highlights edges created
//  by the tensor warping.
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Morphologically processed tensor-sculpted color
//    Alpha: Top-hat transform luminance — isolated bright peaks
//           stand out as high-alpha highlights
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=StrainScale, y=DetailPreserve, z=DepthWeight, w=TensorMode
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: sampleDepth (from tensor-flow-sculpting.wgsl) ═══
fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler,
                            clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

// ═══ CHUNK: tensorEigen (from tensor-flow-sculpting.wgsl) ═══
struct Eigen2 {
  lam_pos: f32,
  lam_neg: f32,
  vec_pos: vec2<f32>,
  vec_neg: vec2<f32>,
};

fn tensorEigen(a: f32, b: f32, d: f32) -> Eigen2 {
  let tr = a + d;
  let det = a * d - b * b;
  let disc = max(tr * tr * 0.25 - det, 0.0);
  let sq = sqrt(disc);
  let lp = tr * 0.5 + sq;
  let ln = tr * 0.5 - sq;
  let bIsSmall = step(abs(b), 1e-6);
  let vp = mix(normalize(vec2<f32>(lp - d, b)), vec2<f32>(1.0, 0.0), bIsSmall);
  var e: Eigen2;
  e.lam_pos = lp;
  e.lam_neg = ln;
  e.vec_pos = vp;
  e.vec_neg = vec2<f32>(-vp.y, vp.x);
  return e;
}

// ═══ CHUNK: vnoise (from tensor-flow-sculpting.wgsl) ═══
fn h2(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(127.1, 311.7));
  q = q + dot(q, q + 19.19);
  return fract(q.x * q.y);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ═══ CHUNK: rippleDisp (from tensor-flow-sculpting.wgsl) ═══
fn rippleDisp(uv: vec2<f32>, t: f32, cnt: u32) -> vec2<f32> {
  var d = vec2<f32>(0.0);
  for (var i: u32 = 0u; i < cnt; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age < 0.0 || age > 4.0) { continue; }
    let dist = distance(uv, r.xy);
    let wave = sin(dist * 28.0 - age * 6.0) * exp(-dist * 5.0) * exp(-age * 1.1);
    let valid = step(0.001, dist);
    d = d + normalize(uv - r.xy) * wave * (1.0 - age / 4.0) * 0.015 * valid;
  }
  return d;
}

// ═══ CHUNK: fbm_tfs (from tensor-flow-sculpting.wgsl) ═══
fn fbm_tfs(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for (var i = 0; i < octaves; i = i + 1) {
    v = v + a * vnoise(pp);
    pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

// ═══ CHUNK: stressColor (from tensor-flow-sculpting.wgsl) ═══
fn stressColor(lam_pos: f32, lam_neg: f32, t: f32) -> vec3<f32> {
  let tensile = max(lam_pos, 0.0);
  let compress = max(-lam_neg, 0.0);
  let shear = abs(lam_pos - lam_neg) * 0.5;
  return vec3<f32>(
    clamp(tensile * 3.0 + sin(t) * 0.1, 0.0, 1.0),
    clamp(shear * 2.0, 0.0, 1.0),
    clamp(compress * 3.0 + cos(t * 1.3) * 0.1, 0.0, 1.0)
  );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let t = u.config.x;
  let tx = 1.0 / res;

  // Parameters
  let strainScale = u.zoom_params.x * 0.08 + 0.005;
  let detailPreserve = u.zoom_params.y;
  let depthWeight = u.zoom_params.z;
  let tensorMode = u.zoom_params.w;

  let kernelRadius = i32(mix(2.0, 5.0, u.zoom_config.x));
  let erosionDilationBlend = u.zoom_config.y;
  let gradientBoost = mix(0.5, 3.0, u.zoom_config.z);
  let morphBlend = u.zoom_config.w;

  // ── Tensor flow sculpting core ──
  let h = sampleDepth(uv);
  let hR = sampleDepth(uv + vec2<f32>(tx.x, 0.0));
  let hL = sampleDepth(uv - vec2<f32>(tx.x, 0.0));
  let hU = sampleDepth(uv + vec2<f32>(0.0, tx.y));
  let hD = sampleDepth(uv - vec2<f32>(0.0, tx.y));
  let hRU = sampleDepth(uv + vec2<f32>(tx.x, tx.y));
  let hLD = sampleDepth(uv - vec2<f32>(tx.x, tx.y));

  let dX = (hR - hL) * 0.5;
  let dY = (hU - hD) * 0.5;
  let dXX = hR - 2.0 * h + hL;
  let dYY = hU - 2.0 * h + hD;
  let dXY = (hRU - hR - hU + h) * 0.5;

  let tA = mix(dXX, dXY, tensorMode);
  let tB = dXY;
  let tD = mix(dYY, dXX, tensorMode);

  let eigen = tensorEigen(tA, tB, tD);

  let noiseFlow = vnoise(uv * 4.0 + vec2<f32>(t * 0.1, t * 0.07)) - 0.5;
  let flowAmp = strainScale * (1.0 + noiseFlow * 0.5);

  let warp1 = eigen.vec_pos * eigen.lam_pos * flowAmp;
  let warp2 = eigen.vec_neg * eigen.lam_neg * flowAmp;
  let tensorWarp = clamp(warp1 + warp2, vec2<f32>(-0.1), vec2<f32>(0.1));

  let normalFlow = vec2<f32>(dX, dY) * strainScale * 3.0 * sin(t * 0.2);
  let rDisp = rippleDisp(uv, t, u32(u.config.y));

  let totalWarp = tensorWarp + normalFlow + rDisp;
  let warpedUV = clamp(uv + totalWarp, vec2<f32>(0.0), vec2<f32>(1.0));

  let colWarped = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let colCenter = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let lap = colCenter.rgb
    - (textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(tx.x, 0.0), 0.0).rgb
     + textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(tx.x, 0.0), 0.0).rgb
     + textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, tx.y), 0.0).rgb
     + textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, tx.y), 0.0).rgb
    ) * 0.25;

  let result = clamp(colWarped.rgb + lap * detailPreserve * 2.5, vec3<f32>(0.0), vec3<f32>(1.0));

  let fbmWarp = (fbm_tfs(uv * 5.0 + vec2<f32>(t * 0.05, t * 0.035), 3) - 0.5) * strainScale;
  let fbmUV = clamp(warpedUV + fbmWarp, vec2<f32>(0.0), vec2<f32>(1.0));
  let colFBM = textureSampleLevel(readTexture, u_sampler, fbmUV, 0.0);
  let fbmBlend = (1.0 - detailPreserve) * 0.25;

  // Edge detection
  let dR = sampleDepth(uv + vec2<f32>(tx.x, 0.0));
  let dL = sampleDepth(uv - vec2<f32>(tx.x, 0.0));
  let dU = sampleDepth(uv + vec2<f32>(0.0, tx.y));
  let dD = sampleDepth(uv - vec2<f32>(0.0, tx.y));
  let edge = length(vec4<f32>(dR - dL, dU - dD, dR - h, dU - h)) * 5.0;
  let edgeMask = smoothstep(0.05, 0.4, edge);

  let N = normalize(vec3<f32>(dL - dR, dD - dU, 0.1));
  let light = normalize(vec3<f32>(cos(t * 0.2), sin(t * 0.15), 0.8));
  let NdotL = max(dot(N, light), 0.0) * 0.3 + 0.7;

  let sColor = stressColor(eigen.lam_pos, eigen.lam_neg, t);
  let sBlend = length(tensorWarp) * 4.0 * (1.0 - detailPreserve) * 0.5;

  var sculpted = mix(result, colFBM.rgb, fbmBlend);
  sculpted = mix(sculpted, sculpted + lap * 1.5, edgeMask * detailPreserve * 0.5);
  sculpted = sculpted * NdotL + sColor * clamp(sBlend, 0.0, 0.15);
  sculpted = clamp(sculpted, vec3<f32>(0.0), vec3<f32>(1.0));

  // ── Morphological post-processing ──
  let mousePos = u.zoom_config.yz;
  let mouseDist = length(uv - mousePos);
  let mouseAngle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
  let mouseFactor = exp(-mouseDist * mouseDist * 6.0);

  let maxRadius = min(kernelRadius, 6);
  let center = vec4<f32>(sculpted, 1.0);
  let centerLuma = dot(center.rgb, vec3<f32>(0.299, 0.587, 0.114));

  var minVal = vec3<f32>(999.0);
  var maxVal = vec3<f32>(-999.0);
  var minLuma = 999.0;
  var maxLuma = -999.0;

  for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
    for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
      var dxF = f32(dx);
      var dyF = f32(dy);
      if (mouseFactor > 0.01) {
        let cosA = cos(mouseAngle);
        let sinA = sin(mouseAngle);
        let rotX = dxF * cosA - dyF * sinA;
        let rotY = dxF * sinA + dyF * cosA;
        dxF = mix(dxF, rotX * 1.5, mouseFactor);
        dyF = mix(dyF, rotY * 0.6, mouseFactor);
      }
      if (dxF * dxF + dyF * dyF > f32(maxRadius * maxRadius)) { continue; }

      let offset = vec2<f32>(f32(dx), f32(dy)) * tx;
      let sample = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      // Apply similar tensor warp approximation for neighborhood
      let sampleWarped = mix(sample, sculpted, 0.5);
      let luma = dot(sampleWarped, vec3<f32>(0.299, 0.587, 0.114));

      minVal = min(minVal, sampleWarped);
      maxVal = max(maxVal, sampleWarped);
      minLuma = min(minLuma, luma);
      maxLuma = max(maxLuma, luma);
    }
  }

  let erosion = minVal;
  let dilation = maxVal;
  let gradient = (dilation - erosion) * gradientBoost;
  let topHat = sculpted - erosion;

  let blendRGB = mix(erosion, dilation, erosionDilationBlend);
  let morphResult = blendRGB + gradient * 0.3;

  let topHatLuma = dot(topHat, vec3<f32>(0.299, 0.587, 0.114));

  let finalColor = mix(sculpted, morphResult, morphBlend);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, topHatLuma));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(h, 0.0, 0.0, 1.0));
}
