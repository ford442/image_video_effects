// ═══════════════════════════════════════════════════════════════════
//  cursor-aura-explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic-aberration, prism, glow, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: limb dispersion; core spends the photo
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  A glowing cursor aura that acts as a chromatic prism.
//  Inside the aura radius, R/G/B channels separate by pseudo-
//  wavelength. The aura edge glows with spectral colors, and
//  click ripples launch chromatic shockwaves.
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

  let radius = u.zoom_params.x * 0.5;
  let intensity = u.zoom_params.y;
  let prismStrength = mix(0.02, 0.12, u.zoom_params.z);
  let dispersion = mix(0.5, 3.0, u.zoom_params.w);

  var mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uvCorrected, mouseCorrected);

  let currentRadius = radius + sin(time * 3.0) * 0.02;
  let mask = 1.0 - smoothstep(currentRadius, currentRadius + 0.05, dist);

  // ── Idea 1: limb dispersion. The rim throws colour; the core keeps a smaller split.
  let limb = smoothstep(currentRadius * 0.42, max(currentRadius, 0.001), dist);
  let dispAmt = prismStrength * mix(0.22, 1.0, limb);
  let rUV = prismDisplace(uv, mousePos, -1.0 * dispersion, dispAmt);
  let gUV = prismDisplace(uv, mousePos, 0.0, dispAmt);
  let bUV = prismDisplace(uv, mousePos, 1.0 * dispersion, dispAmt);

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
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let effectIntensity = 1.0 + mouseDown * 1.5;

  // Base edge detection / high pass
  let offset = 1.0 / resolution.x;
  let left = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-offset, 0.0), 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0);
  let top = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -offset), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset), 0.0);
  let edges = abs(left - right) + abs(top - bottom);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV + rOffset * effectIntensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV + gOffset * effectIntensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV + bOffset * effectIntensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chroma = vec3<f32>(r, g, b);
  let lum = dot(chroma, vec3<f32>(0.299, 0.587, 0.114));
  let saturated = mix(vec3<f32>(lum), chroma, 1.5);
  let effectColor = edges.rgb * 2.0 + vec3<f32>(0.0, 0.5, 1.0) * intensity;
  let insideRgb = mix(effectColor, saturated, 0.6);
  var rgb = mix(baseColor.rgb, insideRgb, mask);

  let ring = smoothstep(currentRadius - 0.01, currentRadius, dist) * smoothstep(currentRadius + 0.01, currentRadius, dist);
  let ringHue = fract(dist * 5.0 + time * 0.5);
  let ringColor = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (ringHue + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (ringHue + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (ringHue + 0.67))
  );
  rgb = rgb + ringColor * ring * intensity * 2.0;

  // ── Idea 2: the core spends the photo, then the existing glow is added.
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let core = exp(-mouseDist * mouseDist * 100.0);
  let photoLuma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
  rgb = mix(rgb, vec3<f32>(photoLuma) * 0.42, clamp(core * 0.9, 0.0, 0.72));
  rgb = rgb + vec3<f32>(0.5, 0.3, 0.8) * core * prismStrength * 8.0;

  let totalDisp = length(rUV - gUV) + length(gUV - bUV);
  let alpha = clamp(baseColor.a * (1.0 - mask) + mask * (0.25 + totalDisp * 4.0) + ring * intensity, 0.0, 1.0);
  let display = acesToneMap(max(rgb, vec3<f32>(0.0)));
  let coord = vec2<i32>(global_id.xy);
  let outColor = vec4<f32>(display, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
