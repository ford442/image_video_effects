// ═══════════════════════════════════════════════════════════════════
//  Holographic Edge Ripple
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: grating streaks (iridescence smeared 3 taps along edgeNormal, length by Holographic Shift); interference orders (thin-film phase cosTheta*(edgeConf+depth) with 3 orders so bands repeat across the edge width); true depth parallax (layer 2 sampled at uv + (uv-0.5)*baseSep*depth with its own edge mask)
//  A packing: linear pre-ACES RGBA (30% edge-gated exact-C feedback)
//  Chunks From: edge-detect, holographic-foil, damped-wave
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=EdgeThreshold, y=RippleSpeed, z=RippleDamping, w=HolographicShift

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const ORDERS: f32 = 3.0;   // thin-film interference orders across the edge width

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  let a = v * (v * 2.51 + 0.03);
  let b = v * (v * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2(123.34, 456.21));
  return fract(dot(q, vec2(12.9898, 78.233)));
}

// ═══ CHUNK: sampleLuma ═══
fn sampleLuma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  return dot(c, vec3(0.299, 0.587, 0.114));
}

// ═══ CHUNK: laplacian_edge_sdf ═══
fn laplacianEdge(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
  let c = sampleLuma(uv);
  let l = sampleLuma(uv + vec2(-ps.x, 0.0));
  let r = sampleLuma(uv + vec2( ps.x, 0.0));
  let up = sampleLuma(uv + vec2(0.0, -ps.y));
  let d = sampleLuma(uv + vec2(0.0,  ps.y));
  let lap = abs(l + r + up + d - 4.0 * c);
  let dx = r - l;
  let dy = d - up;
  let gradMag = length(vec2(dx, dy));
  let zeroCross = smoothstep(0.02, 0.08, lap) * smoothstep(0.01, 0.06, gradMag);
  return zeroCross;
}

// ═══ CHUNK: sobel_gradient ═══
fn sobelGradient(uv: vec2<f32>, ps: vec2<f32>) -> vec2<f32> {
  let tl = sampleLuma(uv + vec2(-ps.x, -ps.y));
  let tc = sampleLuma(uv + vec2( 0.0, -ps.y));
  let tr = sampleLuma(uv + vec2( ps.x, -ps.y));
  let cl = sampleLuma(uv + vec2(-ps.x,  0.0));
  let cr = sampleLuma(uv + vec2( ps.x,  0.0));
  let bl = sampleLuma(uv + vec2(-ps.x,  ps.y));
  let bc = sampleLuma(uv + vec2( 0.0,  ps.y));
  let br = sampleLuma(uv + vec2( ps.x,  ps.y));
  let gx = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
  let gy = -tl - 2.0 * cl - bl + tr + 2.0 * cr + br;
  return vec2(gx, gy);
}

// ═══ CHUNK: holographic_diffraction ═══
fn diffractionHue(theta: f32, shift: f32) -> vec3<f32> {
  let p = theta * 3.0 + shift * TAU;
  return 0.5 + 0.5 * sin(vec3(p, p + 2.094, p + 4.188));
}

// ═══ CHUNK: fresnel_iridescence ═══
// IDEA 2: interference orders — `film` = |cosTheta| * (edgeConf + depth) is the optical
// thickness; it advances the hue by ORDERS turns and modulates the intensity with a
// cos fringe, so the thin-film bands repeat ORDERS times across the edge width.
fn fresnelIridescence(cosThetaIn: f32, shift: f32, film: f32) -> vec3<f32> {
  let cosTheta = clamp(abs(cosThetaIn), 0.0, 1.0);
  let f0 = 0.04;
  let fresnel = f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
  let orderPhase = film * ORDERS;
  let hue = diffractionHue(acos(cosTheta) * 2.0 + orderPhase * TAU / 3.0, shift);
  let fringe = 0.65 + 0.35 * cos(orderPhase * TAU);
  return hue * fresnel * 2.0 * fringe;
}

// ═══ CHUNK: depth_layer_separation ═══
// IDEA 3: true depth parallax — layer 2 is built from the depth sampled at the parallax
// UV (uv + (uv-0.5)*baseSep*depth), so the second holographic sheet sits behind the first.
fn depthLayerSeparation(depth: f32, depth2: f32, shift: f32) -> vec3<f32> {
  let layer1 = diffractionHue(depth * 2.0 + shift, shift);
  let layer2 = diffractionHue(depth2 * 3.0 - shift * 0.5, shift + 0.3);
  let mixFactor = smoothstep(0.3, 0.7, depth);
  return mix(layer1, layer2, mixFactor);
}

fn finite3(v: vec3<f32>) -> vec3<f32> {
  return clamp(select(vec3<f32>(0.0), v, v == v), vec3<f32>(0.0), vec3<f32>(16.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let ps = 1.0 / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  // FIX: the extraBuffer pointer spring never persisted (read 0 every frame) and killed
  // the wave, secondary ripple and caustic. Hold ramps the pointer gate 0.4 -> 1.0.
  let mouseDown = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let heldRamp = 0.4 + 0.6 * mouseDown;

  // Truthful three-band audio
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Preserve existing params exactly
  let edgeThreshold = u.zoom_params.x * 0.5 + 0.05;
  let rippleSpeed = u.zoom_params.y * 5.0;
  let rippleDamp = u.zoom_params.z * 0.8 + 0.1;
  let holoShift = u.zoom_params.w * 2.0;

  // Continuous geometry (edge mapping)
  let edgeConf = laplacianEdge(uv, ps);
  let edgeMask = smoothstep(edgeThreshold * 0.3, edgeThreshold, edgeConf);
  let grad = sobelGradient(uv, ps);
  let edgeNormal = normalize(vec3(grad.x, grad.y, 0.05 + mid * 0.05));
  let acrossEdge = grad / max(length(grad), 1e-4);     // unit vector perpendicular to the edge

  let aspect = resolution.x / resolution.y;
  let mouseDist = length((uv - mouse) * vec2(aspect, 1.0));
  let mouseAttract = exp(-mouseDist * (4.0 - heldRamp * 2.0)) * heldRamp;

  // Capped click fronts (age from startTime in .z; .w is padding)
  var clickRipples = 0.0;
  let clickCount = min(u32(u.config.y), 10u);
  for (var i = 0u; i < clickCount; i = i + 1u) {
      let r = u.ripples[i];
      let dist = length((uv - r.xy) * vec2(aspect, 1.0));
      let age = time - r.z;
      if (age > 0.0 && age < 3.0) {
          let front = age * rippleSpeed * 0.5;
          let width = 0.1 + age * rippleDamp;
          let wave = sin((dist - front) * 20.0) * exp(-age * 2.0) * smoothstep(width, 0.0, abs(dist - front));
          clickRipples += wave * 0.5;
      }
  }
  clickRipples = clamp(clickRipples, -1.0, 1.0);

  let freq = edgeConf * 40.0 + 10.0;
  let phase = time * rippleSpeed * (1.0 + bass * 0.5);
  let envelope = exp(-rippleDamp * 3.0) * (1.0 + bass * 0.6) * mouseAttract;
  let wave = sin(freq - phase) * envelope + clickRipples;

  let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let bgLuma = dot(bg.rgb, vec3(0.299, 0.587, 0.114));

  let viewDir = normalize(vec3(uv - 0.5, 1.0));
  let cosTheta = clamp(dot(edgeNormal, viewDir), -1.0, 1.0);

  let shiftBase = holoShift + time * 0.1 + edgeConf * 2.0 + mid * 0.2;
  // |cosTheta| is only 0.04-0.16 near screen centre (edgeNormal.z = 0.05/|grad|),
  // so floor its contribution or the orders never complete a fringe there.
  let film = (edgeConf + depth) * clamp(abs(cosTheta) * 6.0, 0.3, 1.0);
  let holo = fresnelIridescence(cosTheta, shiftBase, film);
  let depthSep = depth * 0.3 + 0.1;   // baseSep

  // IDEA 1: grating streaks — the iridescence is smeared along the edge normal (across the
  // edge) with two extra edge-confidence taps; streak length grows with Holographic Shift and
  // each side tap carries a slightly shifted hue, like light spread by a diffraction grating.
  let streakLen = 1.5 + u.zoom_params.w * 4.0;
  let streakStep = acrossEdge * ps * streakLen;
  let confPlus = laplacianEdge(uv + streakStep, ps);
  let confMinus = laplacianEdge(uv - streakStep, ps);
  let maskPlus = smoothstep(edgeThreshold * 0.3, edgeThreshold, confPlus);
  let maskMinus = smoothstep(edgeThreshold * 0.3, edgeThreshold, confMinus);
  let holoPlus = fresnelIridescence(cosTheta, shiftBase + 0.12, film);
  let holoMinus = fresnelIridescence(cosTheta, shiftBase - 0.12, film);
  let gratingMask = clamp(max(edgeMask, max(maskPlus, maskMinus) * 0.8), 0.0, 1.0);
  let smeared = holo * edgeMask + (holoPlus * maskPlus + holoMinus * maskMinus) * 0.55;
  let diffraction = smeared * (1.0 + wave * 0.5) * depthSep;

  let displacedUV = uv + edgeNormal.xy * wave * 0.02 * edgeMask;
  let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  let secondaryRipple = sin(edgeConf * 80.0 + time * rippleSpeed * 1.3) * 0.3 * edgeMask * mouseAttract;
  let caustic = max(0.0, secondaryRipple) * diffractionHue(edgeConf * 6.0, holoShift) * 0.5 * (1.0 + treble * 0.4);

  // IDEA 3: parallax sample for the second depth layer, offset toward the screen edge by baseSep*depth.
  let parallaxUV = clamp(uv + (uv - 0.5) * depthSep * depth * 0.25, vec2(0.0), vec2(1.0));
  let depth2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, parallaxUV, 0.0).r;
  let edgeMask2 = smoothstep(edgeThreshold * 0.3, edgeThreshold, laplacianEdge(parallaxUV, ps));
  let layerWeight = smoothstep(0.3, 0.7, depth);
  let layeredHolo = depthLayerSeparation(depth, depth2, holoShift);
  let layerMask = mix(edgeMask, edgeMask2, layerWeight);
  let layerMix = layeredHolo * layerMask * 0.3 * (1.0 + bass * 0.3);

  let grain = hash21(uv * 500.0 + time) * 0.03 * edgeMask;

  // Exact textureLoad from dataTextureC (linear pre-ACES history; guard garbage on switch)
  let pastRgb = finite3(textureLoad(dataTextureC, coord, 0).rgb);

  var emission = mix(bg.rgb, displaced, edgeMask * 0.35)
               + diffraction * (0.6 + bass * 0.4)
               + caustic
               + layerMix
               + grain
               + clickRipples * vec3(0.2, 0.5, 1.0) * (1.0 + treble * 0.5);

  emission = mix(emission, pastRgb, 0.3 * edgeMask);
  emission = max(emission, vec3(0.0));

  // ACES on display only; A keeps the linear value
  let tonemapped = aces_tonemap(emission);

  // Semantic alpha
  var alpha = gratingMask * length(diffraction) * 2.5 + abs(clickRipples) * 2.0;
  alpha = clamp(alpha + bg.a * (1.0 - edgeMask * 0.5), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(tonemapped, alpha));
  textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(emission, alpha));
}
