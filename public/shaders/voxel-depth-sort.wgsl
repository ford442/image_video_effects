// ═══════════════════════════════════════════════════════════════════
//  Voxel Depth Sort v2
//  Category: image
//  Features: mouse-driven, click-reactive, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-02, 2026-11-15
//  Ideas: extruded isometric X/Y voxel side walls; upslope neighbour depth-sort shadow & C.x column settle
//  A packing: raw voxel fields (settledColumn, topMask, depthConf, finalAlpha)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelCoord = vec2<f32>(global_id.xy);
  let time = u.config.x;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) {
    mouse = rawMouse;
    mouseVelocity = vec2<f32>(0.0);
  }
  let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
  let omega = 8.0;
  mouseVelocity += ((rawMouse - mouse) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
  mouse += mouseVelocity * dt;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = mouse.x;
    extraBuffer[134] = mouse.y;
    extraBuffer[135] = mouseVelocity.x;
    extraBuffer[136] = mouseVelocity.y;
    extraBuffer[137] = 1.0;
    extraBuffer[138] = time;
  }
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;

  let blockPixels = 4.0 + u.zoom_params.x * 48.0;
  let extrusion = u.zoom_params.y;
  let bgDarken = u.zoom_params.z;
  let blockGap = u.zoom_params.w;

  let isoRot = (mouse.x - 0.5) * 1.2;
  let isoTilt = (mouse.y - 0.5) * 0.8;

  let cell = floor(pixelCoord / blockPixels);
  let local = fract(pixelCoord / blockPixels) - 0.5;
  let blockCenter = (cell + 0.5) * blockPixels;
  let blockUV = clamp(blockCenter / resolution, vec2<f32>(0.0), vec2<f32>(1.0));

  var clickLift = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let radius = length((blockUV - ripple.xy) * vec2<f32>(aspect, 1.0));
      let wave = exp(-abs(radius - age * 0.18) * 55.0) * exp(-age * 1.4);
      clickLift = max(clickLift, wave);
    }
  }
  let cellHash = hash11(cell.x * 17.0 + cell.y * 113.0);
  let maxBins = max(arrayLength(&plasmaBuffer), 1u);
  let fftBin = min((u32(cellHash * 8.0) % 8u) + 1u, maxBins - 1u);
  let fftVoice = clamp(plasmaBuffer[fftBin].x, 0.0, 1.0);

  let coord = vec2<i32>(global_id.xy);
  let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, blockUV, 0.0).r;
  let shiftedUV = clamp(blockUV + vec2<f32>(0.0, -(sourceDepth + bass * 0.15 + clickLift * 0.35) * extrusion * 0.14), vec2<f32>(0.0), vec2<f32>(1.0));
  let sampledTex = textureSampleLevel(readTexture, u_sampler, shiftedUV, 0.0);
  let blockColor = sampledTex.rgb;
  let luma = luminance(blockColor);
  let targetColumn = clamp(max(luma, sourceDepth) + clickLift * extrusion * 0.45, 0.0, 1.0);

  // ── Idea 2 (part a): physical pinscreen column settle from exact C.x ───
  let prevField = textureLoad(dataTextureC, coord, 0);
  let settleRate = select(0.18, 0.58, targetColumn > prevField.x);
  let column = select(targetColumn, mix(prevField.x, targetColumn, settleRate), prevField.w > 0.01);

  let rotLocal = vec2<f32>(
    local.x * cos(isoRot) - local.y * sin(isoRot),
    local.x * sin(isoRot) + local.y * cos(isoRot)
  );
  let perspective = 1.0 - isoTilt * 0.3;
  let projLocal = vec2<f32>(rotLocal.x * aspect * perspective, rotLocal.y * perspective);

  // ── Idea 1: extruded isometric X/Y voxel side walls ────────────────────
  let halfFace = 0.5 - blockGap * 0.45;
  let extVec = vec2<f32>(sin(isoRot) * 0.34, -0.32 - isoTilt * 0.26) * column * extrusion;
  let capLocal = projLocal - extVec * 0.55;
  let inset = max(abs(capLocal.x), abs(capLocal.y));
  let topMask = 1.0 - smoothstep(halfFace - 0.025, halfFace, inset);

  let extLen2 = max(dot(extVec, extVec), 1e-5);
  let sweepT = clamp(dot(projLocal + extVec * 0.45, extVec) / extLen2, 0.0, 1.0);
  let shaftLocal = (projLocal + extVec * 0.45) - extVec * sweepT;
  let shaftInset = max(abs(shaftLocal.x), abs(shaftLocal.y));
  let wallMask = (1.0 - smoothstep(halfFace - 0.02, halfFace + 0.015, shaftInset)) * (1.0 - topMask) * step(0.008, length(extVec));
  let isXWall = step(abs(shaftLocal.y), abs(shaftLocal.x));
  let wallShade = mix(0.36, 0.58, isXWall) * (0.68 + 0.32 * sweepT);

  // ── Idea 2 (part b): upslope neighbour height step-shadow ──────────────
  let stepSignX = select(-1.0, 1.0, sin(isoRot) < 0.15);
  let neighUV = clamp(((cell + vec2<f32>(stepSignX, -1.0) + 0.5) * blockPixels) / resolution, vec2<f32>(0.0), vec2<f32>(1.0));
  let neighDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, neighUV, 0.0).r;
  let neighColor = textureSampleLevel(readTexture, u_sampler, neighUV, 0.0).rgb;
  let neighColumn = clamp(max(luminance(neighColor), neighDepth), 0.0, 1.0);
  let heightDiff = max(neighColumn - column, 0.0) * extrusion;
  let shadowAxis = -capLocal.y * 0.72 + capLocal.x * stepSignX * 0.38;
  let stepShadow = smoothstep(halfFace - heightDiff * 0.95, halfFace, shadowAxis) * clamp(heightDiff * 2.1, 0.0, 0.68);

  let shadowMask = (1.0 - clamp(topMask + wallMask, 0.0, 1.0)) * (0.35 + bgDarken * 0.45);

  let ao = 1.0 - smoothstep(0.2, halfFace, inset) * 0.35 * topMask;
  let softShadow = (smoothstep(0.0, 0.5, sourceDepth) * 0.25 + stepShadow * 0.75) * topMask;

  let rim = smoothstep(halfFace - 0.16, halfFace - 0.01, inset) * topMask;
  let spectral = mix(
    vec3<f32>(0.16, 0.60, 1.0),
    vec3<f32>(1.0, 0.45, 0.20),
    bass * 0.5 + audio.z * 0.25
  );

  let sss = vec3<f32>(0.25, 0.55, 0.90) * column * topMask * (0.15 + bass * 0.15);

  var backgroundColor = mix(blockColor * (1.0 - bgDarken * 0.80), vec3<f32>(0.02, 0.03, 0.05), bgDarken * 0.70);
  backgroundColor = backgroundColor * (1.0 - shadowMask);

  let wallColor = (blockColor * wallShade + spectral * 0.08 * (1.0 - sweepT)) * (1.0 - stepShadow * 0.55);

  var topColor = blockColor * (0.65 + 0.60 * column) * ao;
  topColor = topColor + spectral * rim * (0.14 + audio.y * 0.24 + bass * 0.18 + fftVoice * 0.18);
  topColor = topColor + vec3<f32>(0.08, 0.10, 0.14) * extrusion * (1.0 + bass * 0.2);
  topColor = (topColor + sss) * (1.0 - clamp(softShadow, 0.0, 0.82));

  let pillarColor = mix(backgroundColor, wallColor, wallMask);
  let hdrOut = mix(pillarColor, topColor, topMask);
  let finalColor = aces_tonemap(max(hdrOut, vec3<f32>(0.0)));
  let voxelCover = clamp(topMask + wallMask * 0.85, 0.0, 1.0);
  let depthConf = clamp(sourceDepth + column * 0.3, 0.0, 1.0);
  let occlusion = shadowMask * 0.5 + (1.0 - ao) * 0.3 + stepShadow * 0.2;
  let finalAlpha = clamp((sampledTex.a * 0.15 + depthConf * 0.85) * (1.0 - occlusion * 0.6) * (0.45 + voxelCover * 0.53), 0.25, 0.98);
  let pillarDepth = mix(column * sweepT, min(1.0, column + extrusion * 0.60 + bass * 0.12 + clickLift * 0.18), topMask);
  let depthOut = clamp(mix(sourceDepth * (1.0 - bgDarken * 0.50), pillarDepth, voxelCover), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(column, topMask, depthConf, finalAlpha));
}
