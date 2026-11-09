// ═══════════════════════════════════════════════════════════════════
//  Cyber Lattice Bilateral
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11, 2026-11-09
//  Ideas: node capacitive discharge; seam snap highlight; data packets; chromatic line split; cell occupancy fill
//  A packing: pre-ACES linear RGB (0..4) + alpha; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
  var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
  return vec3<f32>(h, d, q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - 3.0);
  return c.z * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn hexMetrics(p: vec2<f32>) -> vec3<f32> {
  let q = vec2<f32>(p.x * 1.7320508 + p.y, p.y * 2.0);
  let pi = floor(q);
  let pf = fract(q);
  let distEdge = min(min(pf.x, 1.0 - pf.x), min(pf.y, 1.0 - pf.y));
  let vertDist = length(pf - vec2<f32>(0.5));
  return vec3<f32>(distEdge, vertDist, hash12(pi));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Rescue: extraBuffer[133..138] is zeroed by the engine every frame, so the
  // old spring never persisted — it was the raw cursor. Removed the fake state.
  let smoothMouse = mouse;

  let gridScale = 10.0 + u.zoom_params.x * 50.0 * (1.0 + bass * 0.15);
  let distortStrength = u.zoom_params.y * (1.0 + mids * 0.2);
  let glowIntensity = u.zoom_params.z * (1.0 + treble * 0.25);
  let radius = mix(0.08, 0.45, u.zoom_params.w);

  let distVec = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let mouseInfluence = smoothstep(radius, 0.0, dist);

  let distortion = mouseInfluence * distortStrength * sin(time * 5.0 + bass * 2.0) * select(1.0, 1.35, held);
  let gridUV = uv + (uv - smoothMouse) * distortion;

  let gridX = abs(fract(gridUV.x * gridScale) - 0.5);
  let gridY = abs(fract(gridUV.y * gridScale) - 0.5);
  let gridLine = min(gridX, gridY);

  let thickness = mix(0.03, 0.08, glowIntensity);
  let currentThickness = thickness + mouseInfluence * 0.08;
  let gridMask = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, gridLine);

  // New idea: chromatic line split — R and B grid lines are drawn from UVs
  // pushed further / less along the warp, so lines fringe red/blue where the
  // cursor bends the lattice hardest.
  let splitAmt = abs(distortion) * 0.05;
  let gUVr = gridUV + (uv - smoothMouse) * splitAmt * 4.0;
  let gUVb = gridUV - (uv - smoothMouse) * splitAmt * 4.0;
  let lineR = min(abs(fract(gUVr.x * gridScale) - 0.5), abs(fract(gUVr.y * gridScale) - 0.5));
  let lineB = min(abs(fract(gUVb.x * gridScale) - 0.5), abs(fract(gUVb.y * gridScale) - 0.5));
  let maskR = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, lineR);
  let maskB = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, lineB);

  // New idea: data packets — short bright dashes sliding along the grid
  // lines; each line has a hashed speed and direction, treble speeds them up.
  let cellId = floor(gridUV * gridScale);
  let onV = gridX < gridY;  // nearer a vertical line → packet runs along y
  let laneId = select(cellId.y, cellId.x, onV);
  let laneH = hash12(vec2<f32>(laneId, select(3.1, 7.7, onV)));
  let laneDir = select(-1.0, 1.0, laneH > 0.5);
  let along = select(gridUV.x, gridUV.y, onV) * gridScale;
  let packetPh = fract(along * 0.25 - time * laneDir * (0.6 + laneH * 1.4) * (1.0 + treble * 1.5) + laneH * 13.0);
  let packet = smoothstep(0.0, 0.03, packetPh) * (1.0 - smoothstep(0.03, 0.12, packetPh)) * gridMask * step(0.35, laneH);

  let spatialSigmaBase = mix(0.08, 0.9, 0.5 - u.zoom_params.y * 0.25);
  let colorSigma = mix(0.04, 0.8, 0.35 + mids * 0.2);
  let hueShiftAmt = mix(0.05, 0.35, u.zoom_params.z) * (1.0 + treble * 0.15);

  let mouseFactor = exp(-dist * dist * 8.0) * 0.5;
  let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

  var rippleSharpness = 0.0;
  var nodeDischarge = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rElapsed = time - ripple.z;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
      rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
      // Idea 1 — node capacitive discharge at hex vertices on ripple overlap
      let rippleHex = hexMetrics(gridUV * gridScale);
      let atVertex = smoothstep(0.12, 0.0, rippleHex.y);
      nodeDischarge = nodeDischarge + wave * atVertex * exp(-rElapsed * 2.5) * (1.0 + treble * 0.4);
    }
  }
  let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);

  // Idea 2 — seam snap highlight: bilateral edge weight peaks on hex seam lines
  let hexInfo = hexMetrics(gridUV * gridScale);
  let seamSnap = smoothstep(0.06, 0.0, hexInfo.x);

  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let bRadius = i32(ceil(finalSigma * 2.5));
  let maxRadius = min(bRadius, 7);

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighbor = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
      let colorDist = length(neighbor.rgb - center.rgb);
      let neighborHex = hexMetrics((clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0))) * gridScale);
      let seamBoost = 1.0 + seamSnap * smoothstep(0.05, 0.0, neighborHex.x) * 2.5;
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001)) * seamBoost;
      let weight = spatialWeight * rangeWeight;
      accumColor += neighbor.rgb * weight;
      accumWeight += weight;
    }
  }

  var result = select(center.rgb, accumColor / accumWeight, accumWeight > 0.001);

  if (hueShiftAmt > 0.0) {
    let hsv = rgb2hsv(result);
    let newHue = fract(hsv.x + hueShiftAmt + dist * 0.3 + time * 0.05 + select(0.0, 0.15, held));
    result = hsv2rgb(vec3<f32>(newHue, hsv.y, hsv.z));
  }

  var glowColor = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), select(0.0, 1.0, held));
  let totalGlow = glowIntensity * (0.5 + 0.5 * mouseInfluence) * (1.0 + bass * 0.2);

  var finalColor = mix(result, glowColor, gridMask * totalGlow);
  if (gridMask > 0.5) {
    finalColor = glowColor * totalGlow * 1.5;
  }

  // New idea: cell occupancy fill — each lattice cell samples the image at
  // its centre and lights a faint quantised tint, like a coarse LED panel.
  let cellUV = (cellId + 0.5) / gridScale;
  let cellLum = dot(textureSampleLevel(readTexture, u_sampler, clamp(cellUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let occupancy = floor(cellLum * 4.0) / 4.0;
  finalColor += glowColor * occupancy * (1.0 - gridMask) * 0.12 * (0.6 + glowIntensity);

  finalColor += vec3<f32>(1.0, 0.1, 0.3) * max(maskR - gridMask, 0.0) * totalGlow * 0.9;
  finalColor += vec3<f32>(0.2, 0.3, 1.0) * max(maskB - gridMask, 0.0) * totalGlow * 0.9;
  finalColor += vec3<f32>(1.0, 1.0, 0.85) * packet * (1.2 + treble * 0.8);

  finalColor += glowColor * nodeDischarge * 1.4;
  finalColor += vec3<f32>(0.2, 0.95, 1.0) * seamSnap * totalGlow * 0.35;

  let prevDream = textureLoad(dataTextureC, coord, 0).rgb;
  let dreamMix = mix(0.06, 0.22, u.zoom_params.z) * (1.0 - gridMask * 0.6);
  finalColor = mix(finalColor, prevDream, dreamMix);

  // Rescue: A used to hold the ACES display while C fed it back pre-ACES
  // (re-grade loop). A now stores pre-grade linear colour.
  let lin = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(4.0));
  finalColor = acesToneMap(lin * (0.95 + bass * 0.06));

  let alpha = clamp(center.a * (1.0 - gridMask * 0.2) + gridMask * totalGlow * 0.35 + nodeDischarge * 0.25 + seamSnap * 0.12 + mouseInfluence * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(lin, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
