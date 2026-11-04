// ═══════════════════════════════════════════════════════════════════
//  interactive-rgb-split-explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic, prism, ripple, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: interactive-rgb-split.wgsl, mouse-chromatic-explosion.wgsl
//  Upgraded: 2026-11-01
//  Ideas: radial split along the pointer; falloff lip on the existing gate
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Prismatic RGB channel separation controlled by mouse distance.
//  Combines localized radial/directional split with wavelength-based
//  prism dispersion. Click ripples launch chromatic shockwaves.
//  Alpha stores total chromatic displacement.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let prismStrength = mix(0.02, 0.12, u.zoom_params.x) * (1.0 + bass * 0.5);
  let falloff = u.zoom_params.y;
  let rippleStrength = u.zoom_params.z;
  let saturationBoost = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Localized amount from interactive-rgb-split falloff
  let uv_aspect = uv * vec2<f32>(aspect, 1.0);
  let center_aspect = mousePos * vec2<f32>(aspect, 1.0);
  let dist = distance(uv_aspect, center_aspect);
  let falloffOn = falloff > 0.0;
  let gated = prismStrength * smoothstep(0.8, 0.0, dist * max(falloff, 0.0) * 2.0);
  var amount = select(prismStrength, gated, falloffOn);
  // ── Idea 2: falloff lip. Falloff 0 still leaves the split ungated.
  let fallDist = dist * max(falloff, 0.0) * 2.0;
  let lip = smoothstep(0.25, 0.55, fallDist) * smoothstep(0.95, 0.55, fallDist) * select(0.0, 1.0, falloffOn);
  amount = amount * mix(1.0, 1.7, lip);

  // ── Idea 1: radial split along the pointer, same amount as the tangential prism.
  let toPointer = uv - mousePos;
  let radialDir = toPointer / max(length(toPointer), 1e-4);
  let radial = radialDir * amount * 1.35;
  let rUV = prismDisplace(uv, mousePos, -1.0, amount) - radial;
  let gUV = prismDisplace(uv, mousePos, 0.0, amount);
  let bUV = prismDisplace(uv, mousePos, 1.0, amount) + radial;

  // Ripple chromatic shockwaves
  let rippleCount = min(u32(u.config.y), 50u);
  var rOffset = vec2<f32>(0.0);
  var gOffset = vec2<f32>(0.0);
  var bOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * rippleStrength * 0.03;
      gOffset = gOffset + dir * wave * rippleStrength * 0.03;
      bOffset = bOffset + dir * bWave * rippleStrength * 0.03;
    }
  }

  let intensity = 1.0 + mouseDown * 1.5 + bass * 0.8;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV + rOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV + gOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV + bOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Saturation boost
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.0 + saturationBoost);

  // Spectral glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  color = color + vec3<f32>(0.5, 0.3, 0.8) * glow * (1.0 + bass * 0.7);

  // Mids drive a spectral corona ring expanding from the cursor
  let ringDelta = mouseDist * 6.0 - mids * 3.0;
  let ring = exp(-ringDelta * ringDelta * 4.0) * mids;
  color = color + vec3<f32>(1.0, 0.55, 0.2) * ring * 0.5;

  let totalDisp = length(rUV - gUV) + length(gUV - bUV) + length(rOffset) + length(gOffset) + length(bOffset);
  let alpha = clamp(totalDisp * 5.0 + ring * 0.4, 0.0, 1.0);
  let display = acesToneMap(max(color, vec3<f32>(0.0)));
  let outColor = vec4<f32>(display, alpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
