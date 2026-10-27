// ═══════════════════════════════════════════════════════════════════
//  Digital Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: finite drops; glyph dissolve
//  A packing: reveal mask in A.r (C.r read back); A.a mirrors the mask
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn glyphShape(cellUV: vec2<f32>, id: f32) -> f32 {
  let bars = step(0.3, cellUV.x) * step(cellUV.x, 0.7) * step(0.2, cellUV.y);
  let dots = step(length(cellUV - vec2<f32>(0.5)), 0.18);
  return max(bars, dots * step(fract(id * 0.37), 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = u.zoom_config.w > 0.5;

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthReveal = mix(0.3, 1.0, depth);

  let density = u.zoom_params.x * bass_env(bass, mids);
  let revealSize = u.zoom_params.y * select(1.0, 1.3, held);
  let trailFade = u.zoom_params.z;
  let rainSpeed = u.zoom_params.w * (1.0 + treble * 0.5);

  let prevVal = textureLoad(dataTextureC, pixel, 0).r;

  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
  let brushRadius = revealSize * 0.3 + 0.05;
  let mouseValid = select(0.0, 1.0, mouse.x >= 0.0);
  let brush = mouseValid * smoothstep(brushRadius, brushRadius * 0.5, dist);

  let fadeFactor = 0.8 + trailFade * 0.19;
  var newVal = max(prevVal * fadeFactor, brush) * depthReveal;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let liveF = step(0.0, age) * step(age, 2.0);
    let rpDist = length((rp.xy - uv) * vec2<f32>(aspect, 1.0));
    let blob = 1.0 - smoothstep(0.0, 0.15, rpDist);
    newVal = max(newVal, blob * liveF * (1.0 - age * 0.5));
  }

  let gridSize = vec2<f32>(18.0 + density * 26.0, (18.0 + density * 26.0) * aspect);
  let cellUV = fract(uv * gridSize);
  let cellID = floor(uv * gridSize);
  let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (rainSpeed * 5.0 + 1.0);
  let verticalPos = cellID.y + time * colSpeed;
  let charID = floor(verticalPos);
  let dropVal = fract(verticalPos);
  let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);
  let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);
  let glyph = glyphShape(cellUV, hash22(vec2<f32>(cellID.x, charID)).x);
  // ── Idea: glyph dissolve — the reveal wipes each glyph from the top of its cell.
  let wipe = 1.0 - clamp(newVal, 0.0, 1.0);
  let glyphVis = glyph * (1.0 - smoothstep(wipe - 0.02, wipe + 0.05, cellUV.y));
  // ── Idea: finite drops — a hash-length run, then a gap. Density sets the grid, speed the fall.
  let cycle = fract(verticalPos * (0.12 + density * 0.02));
  let dropLen = 0.16 + hash22(vec2<f32>(cellID.x, 1.7)).x * 0.32;
  let inDrop = smoothstep(0.0, 0.04, cycle) * (1.0 - smoothstep(dropLen, dropLen + 0.06, cycle));

  let colPhase = hash22(vec2<f32>(cellID.x, 4.0)).x;
  var rainColor = vec3<f32>(0.05, 0.95, 0.32) * charBright * flicker * glyphVis * inDrop;
  rainColor = rainColor * (1.0 + treble * colPhase * 0.35);
  rainColor = rainColor + vec3<f32>(0.0, bass * 0.3 * charBright * glyphVis * inDrop, 0.0);
  let rare = step(0.98 - density * 0.1, hash22(vec2<f32>(cellID.x, charID)).y);
  rainColor = mix(rainColor, vec3<f32>(0.8 + treble * 0.2, 1.0, 0.8 + treble * 0.2), rare * inDrop);

  let depthGlow = mix(1.0, mix(0.6, 1.2, depth), 0.4);
  rainColor *= depthGlow;

  let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var finalColor = mix(rainColor, imageColor, clamp(newVal, 0.0, 1.0));
  finalColor = acesToneMap(finalColor * (0.95 + mids * 0.05));
  let alpha = clamp(newVal + charBright * glyphVis * inDrop * 0.2 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(newVal, 0.0, 0.0, newVal));
}
