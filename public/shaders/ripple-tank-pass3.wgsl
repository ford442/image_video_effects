// ═══════════════════════════════════════════════════════════════════
//  Ripple Tank — Node 4: Jacobian Caustics & Chromatic Water Render
//  Category: simulation
//  Features: multi-pass, mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: bathymetric shoaling & Rayleigh sponge shore (Node 1); ray-sheet Jacobian focal caustics (`det(I + d_f * D^2 h)`) & Fresnel-Schlick / Beer-Lambert tank optics (§12.2F)
//  A packing: raw (height, velocity, foam energy, oscillator phase) — committed unchanged
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
    max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
    vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC,
    clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.283185 *
    (vec3<f32>(t) + vec3<f32>(0.00, 0.33, 0.67)));
}

fn focalIrradiance(hxx: f32, hyy: f32, hxy: f32, focalDepth: f32) -> f32 {
  let j = (1.0 + focalDepth * hxx) * (1.0 + focalDepth * hyy) - focalDepth * focalDepth * hxy * hxy;
  return 1.0 / max(j, 0.16);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let state = stateAt(pixel, dims);

  let left = stateAt(pixel + vec2<i32>(-1, 0), dims).r;
  let right = stateAt(pixel + vec2<i32>(1, 0), dims).r;
  let top = stateAt(pixel + vec2<i32>(0, -1), dims).r;
  let bottom = stateAt(pixel + vec2<i32>(0, 1), dims).r;
  let ul = stateAt(pixel + vec2<i32>(-1, -1), dims).r;
  let ur = stateAt(pixel + vec2<i32>(1, -1), dims).r;
  let dl = stateAt(pixel + vec2<i32>(-1, 1), dims).r;
  let dr = stateAt(pixel + vec2<i32>(1, 1), dims).r;

  let gradient = vec2<f32>(
    (right - left) + 0.5 * (ur - ul + dr - dl),
    (bottom - top) + 0.5 * (dl - ul + dr - ur)
  ) * 0.5;
  let normal = normalize(vec3<f32>(-gradient * 6.5, 0.14));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let refraction = normal.xy * (0.022 + audio.x * 0.012) * (0.65 + (1.0 - depth) * 0.35);
  let r = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + refraction * 1.18, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let g = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + refraction, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let b = textureSampleLevel(readTexture, u_sampler,
    clamp(uv + refraction * 0.78, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sourceRGB = vec3<f32>(r.r, g.g, b.b);
  let sourceAlpha = max(r.a, max(g.a, b.a));

  // ── Idea 2: 2D ray-sheet Jacobian focal caustics det(I + d_f * D^2 h) ──
  // Convex crests (hxx < 0, hyy < 0) focus overhead tank illumination (J < 1 -> bright cusps),
  // while concave troughs (hxx > 0, hyy > 0) diverge rays and gently dim the tank floor.
  let hxx = left + right - 2.0 * state.r;
  let hyy = top + bottom - 2.0 * state.r;
  let hxy = (dr - dl - ur + ul) * 0.25;
  let focalDepth = 2.8 + (1.0 - depth) * 1.8;
  let irrR = focalIrradiance(hxx, hyy, hxy, focalDepth * 0.90);
  let irrG = focalIrradiance(hxx, hyy, hxy, focalDepth * 1.00);
  let irrB = focalIrradiance(hxx, hyy, hxy, focalDepth * 1.11);
  let floorIrradiance = vec3<f32>(irrR, irrG, irrB);
  let causticCusp = max(floorIrradiance - vec3<f32>(1.0), vec3<f32>(0.0)) * (1.0 + audio.z * 0.75);

  // ── Idea 2: Beer-Lambert water-column extinction & Fresnel-Schlick sky reflection (§12.2F) ──
  let waterColumn = clamp(0.38 + state.r * 0.26 + (1.0 - depth) * 0.34, 0.06, 1.35);
  let beerTrans = exp(-waterColumn * vec3<f32>(0.44, 0.14, 0.055));
  let fresnel = 0.02 + 0.98 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);

  let amplitudeRaw = sqrt(state.r * state.r + state.g * state.g);
  let amplitude = amplitudeRaw / (0.12 + amplitudeRaw);
  let phase = atan2(state.g, state.r) * 0.15915494 + 0.5;
  let interference = spectral(phase + time * 0.055 + audio.y * 0.12);
  let lightDirection = normalize(vec3<f32>(0.42, 0.55, 0.82));
  let diffuse = max(dot(normal, lightDirection), 0.0);
  let specular = pow(max(dot(reflect(-lightDirection, normal),
    vec3<f32>(0.0, 0.0, 1.0)), 0.0), 48.0);

  var rgb = sourceRGB * beerTrans * clamp(floorIrradiance, vec3<f32>(0.58), vec3<f32>(1.35)) * (0.56 + diffuse * 0.50);
  rgb += interference * amplitude * (0.58 + audio.y * 0.28);
  rgb += vec3<f32>(0.32, 0.72, 1.05) * fresnel * (0.28 + audio.y * 0.14);
  rgb += vec3<f32>(1.0, 0.96, 0.86) * specular * 0.44;
  rgb += (vec3<f32>(0.42, 0.88, 1.08) * causticCusp * 0.26) + vec3<f32>(0.82, 0.93, 1.0) * state.b * 0.12;
  rgb = max(rgb, vec3<f32>(0.0));

  let causticLuma = dot(causticCusp, vec3<f32>(0.3333));
  let alpha = clamp(sourceAlpha * 0.52 + amplitude * 0.34 +
    state.b * 0.12 + fresnel * 0.08 + causticLuma * 0.04, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(aces(rgb), alpha));
  textureStore(writeDepthTexture, pixel,
    vec4<f32>(clamp(depth - state.r * 0.05 - state.b * 0.008, 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, state);
}
