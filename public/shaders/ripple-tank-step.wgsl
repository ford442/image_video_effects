// ═══════════════════════════════════════════════════════════════════
//  Ripple Tank — Node 1: Bathymetric Dispersive Wave Integration
//  Category: simulation
//  Features: multi-pass, mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: bathymetric scene-depth wave shoaling (§12.2D) & Rayleigh sponge shore; ray-sheet Jacobian focal caustics & Fresnel-Schlick / Beer-Lambert tank optics (§12.2F)
//  A packing: raw (height, velocity, foam energy, oscillator phase)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn laplacian(pixel: vec2<i32>, dims: vec2<i32>) -> f32 {
  let center = stateAt(pixel, dims).r;
  var sum = -28.0 * center;
  sum += 4.0 * stateAt(pixel + vec2<i32>(1, 0), dims).r;
  sum += 4.0 * stateAt(pixel + vec2<i32>(-1, 0), dims).r;
  sum += 4.0 * stateAt(pixel + vec2<i32>(0, 1), dims).r;
  sum += 4.0 * stateAt(pixel + vec2<i32>(0, -1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(1, 1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(1, -1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(-1, 1), dims).r;
  sum += 2.0 * stateAt(pixel + vec2<i32>(-1, -1), dims).r;
  sum += stateAt(pixel + vec2<i32>(2, 0), dims).r;
  sum += stateAt(pixel + vec2<i32>(-2, 0), dims).r;
  sum += stateAt(pixel + vec2<i32>(0, 2), dims).r;
  sum += stateAt(pixel + vec2<i32>(0, -2), dims).r;
  return sum / 14.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let state = stateAt(pixel, dims);

  // ── Idea 1: bathymetric scene-depth wave shoaling (§12.2D Dispersion) ──
  // Submerged foreground silhouettes reduce local water depth h_b, slowing phase speed c ~ sqrt(h_b)
  let sceneDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let shoalFactor = sqrt(clamp(1.06 - sceneDepth * 0.54, 0.38, 1.0));
  let waveSpeed = mix(0.08, 0.45, u.zoom_params.x) * (1.0 + audio.y * 0.035) * shoalFactor;
  let damping = mix(0.975, 0.9995, u.zoom_params.y) - audio.z * 0.0008;
  let boundaryReflect = clamp(u.zoom_params.w, 0.0, 1.0);

  let curvature = laplacian(pixel, dims);
  var velocity = (state.g + waveSpeed * waveSpeed * curvature) * damping;
  var height = state.r + velocity;
  var foam = max(state.b * (0.965 + audio.x * 0.012), abs(curvature) * 0.32);

  // ── Idea 1: Rayleigh velocity-sponge beach vs. Neumann reflecting tank wall ──
  let edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let shoreBand = 1.0 - smoothstep(0.0, 0.075, edgeDistance);
  let absorbAmount = shoreBand * (1.0 - boundaryReflect);
  velocity *= 1.0 - absorbAmount * 0.18;
  height *= 1.0 - absorbAmount * 0.045;
  foam *= 1.0 - absorbAmount * 0.08;

  textureStore(dataTextureA, pixel, vec4<f32>(
    clamp(height, -1.5, 1.5),
    clamp(velocity, -0.8, 0.8),
    clamp(foam, 0.0, 1.5),
    state.a));
}
