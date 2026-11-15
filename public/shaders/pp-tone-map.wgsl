// ═══════════════════════════════════════════════════════════════════
//  PP Tone Map
//  Category: post-processing
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06, 2026-11-15
//  Ideas: continuous algorithm mix; hue-preserving contrast; underexposure toe (§12.2A); hue-stable highlight shoulder
//  A packing: display RGBA (tone-mapped; no second ACES)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn uncharted2Tonemap(x: vec3<f32>) -> vec3<f32> {
  let A = 0.15; let B = 0.50; let C = 0.10; let D = 0.20; let E = 0.02; let F = 0.30;
  let W = 11.2;
  let whiteScale = 1.0 / (((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F);
  var c = ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
  c *= whiteScale;
  return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn reinhardToneMap(x: vec3<f32>) -> vec3<f32> {
  return x / (1.0 + x);
}

fn agxToneMap(x: vec3<f32>) -> vec3<f32> {
  let sigmoid = (x * (x * 0.8 + 0.1)) / (x * (x * 0.7 + 0.4) + 0.05);
  return clamp(sigmoid, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applyExposure(color: vec3<f32>, exposure: f32) -> vec3<f32> {
  let scaled = color * pow(2.0, exposure);
  // ── Idea 3: underexposure toe (§12.2A) ─────────────────────────
  // Below middle exposure, shadows roll off. At exposure ≥ 0 the four curves see `scaled` unchanged.
  let under = max(-exposure, 0.0);
  let k = under * 0.22;
  let safe = max(scaled, vec3<f32>(0.0));
  let toe = safe * (1.0 + k) / (safe + vec3<f32>(k + 1e-4));
  return mix(scaled, toe, step(0.001, under));
}

fn applyContrastHue(color: vec3<f32>, contrast: f32) -> vec3<f32> {
  let l = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let newL = (l - 0.5) * contrast + 0.5;
  return color * (newL / max(l, 1e-4));
}

fn applySaturation(color: vec3<f32>, saturation: f32) -> vec3<f32> {
  let l = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  return mix(vec3<f32>(l), color, saturation);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let bass = plasmaBuffer[0].x;

  let algorithm = clamp(u.zoom_params.x, 0.0, 1.0);
  let exposure = (u.zoom_params.y - 0.5) * 4.0 + bass * 0.15;
  let contrast = max(u.zoom_params.z * 2.0, 0.01);
  let saturation = u.zoom_params.w * 2.0;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = applyExposure(src.rgb, exposure);

  let c0 = acesToneMap(color);
  let c1 = uncharted2Tonemap(color);
  let c2 = reinhardToneMap(color);
  let c3 = agxToneMap(color);
  let t = algorithm * 3.0;
  var ldr = mix(c0, c1, clamp(t, 0.0, 1.0));
  ldr = mix(ldr, c2, clamp(t - 1.0, 0.0, 1.0));
  ldr = mix(ldr, c3, clamp(t - 2.0, 0.0, 1.0));

  ldr = applyContrastHue(ldr, contrast);
  ldr = applySaturation(ldr, saturation);
  // ── Idea 4: hue-stable highlight shoulder ──────────────────────
  // The hottest channel used to hit 1 first and shift the hue. Mid-grey contrast is unchanged.
  let peak = max(ldr.r, max(ldr.g, ldr.b));
  let shoulder = smoothstep(0.78, 1.05, peak);
  let lSh = dot(max(ldr, vec3<f32>(0.0)), vec3<f32>(0.2126, 0.7152, 0.0722));
  ldr = mix(ldr, vec3<f32>(lSh), shoulder * 0.4);
  ldr = clamp(ldr, vec3<f32>(0.0), vec3<f32>(1.0));

  let rolloff = smoothstep(0.55, 1.0, dot(ldr, vec3<f32>(0.2126, 0.7152, 0.0722)));
  let alpha = clamp(src.a * 0.6 + rolloff * 0.4, 0.0, 1.0);
  let outCol = vec4<f32>(ldr, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
