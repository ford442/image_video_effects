// ═══════════════════════════════════════════════════════════════════
//  CRT Clear Zone v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal,
//            beam-raster, misconvergence, halation, degauss, ACES
//  Ideas:    1. electron-beam raster — a visible beam sweep; freshly hit lines glow and
//               fade through the C phosphor
//            2. corner misconvergence + halation — R/B guns drift apart toward the corners,
//               and bright areas bloom in the glass
//            3. degauss purity rim — colour-purity blotches ring the clear zone, and a
//               click "degausses" it with a decaying wobble
//  Complexity: High
//  Chunks From: crt-clear-zone, electron-beam, shadow-mask
//  Upgraded: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn barrel_distort(uv: vec2<f32>, amt: f32) -> vec2<f32> {
  let centered = uv - 0.5;
  let r2 = dot(centered, centered);
  let r4 = r2 * r2;
  let f = 1.0 + r2 * amt * 0.5 + r4 * amt * amt * 0.15;
  return centered * f + 0.5;
}

fn gaussian_spread(uv: vec2<f32>, res: vec2<f32>, spread: f32) -> vec3<f32> {
  let e = spread / res;
  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let c1 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(e.x, 0.0), 0.0).rgb;
  let c2 = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(e.x, 0.0), 0.0).rgb;
  let c3 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, e.y), 0.0).rgb;
  let c4 = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, e.y), 0.0).rgb;
  return c0 * 0.4 + (c1 + c2 + c3 + c4) * 0.15;
}

fn shadow_mask(uv: vec2<f32>, res: vec2<f32>) -> vec3<f32> {
  // Half-pixel phase: at the undistorted centre uv·res lands on integers, and
  // without the offset the green slot was skipped on every other row.
  let maskUV = (uv * res + 0.5) * 0.5;
  let slotX = fract(maskUV.x * 0.5);
  let slotY = fract(maskUV.y);
  let r = smoothstep(0.33, 0.0, abs(slotX - 0.17)) * smoothstep(0.5, 0.0, abs(slotY - 0.25));
  let g = smoothstep(0.33, 0.0, abs(slotX - 0.5)) * smoothstep(0.5, 0.0, abs(slotY - 0.75));
  let b = smoothstep(0.33, 0.0, abs(slotX - 0.83)) * smoothstep(0.5, 0.0, abs(slotY - 0.25));
  // The raw slot pattern averages ~0.22 transmission, which left the CRT area
  // dim and magenta at HEAD. Normalise to unit mean and blend it in at 35%.
  return mix(vec3<f32>(1.0), vec3<f32>(r, g, b) * (1.6 / 0.225), 0.35);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let aspect = resolution.x / max(resolution.y, 1.0);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let distortion = mix(0.05, 1.8, clamp(u.zoom_params.x, 0.0, 1.0)) * (1.0 + bass * 0.15);
  let aberration = mix(0.001, 0.022, clamp(u.zoom_params.y, 0.0, 1.0));
  let clearRadius = mix(0.08, 0.45, clamp(u.zoom_params.z, 0.0, 1.0));
  let scanlineInt = mix(0.08, 0.75, clamp(u.zoom_params.w, 0.0, 1.0)) * (1.0 + bass * 0.25 + mids * 0.12);

  let crtUV = barrel_distort(uv, distortion);
  let in_bounds = crtUV.x >= 0.0 && crtUV.x <= 1.0 && crtUV.y >= 0.0 && crtUV.y <= 1.0;
  let clampedCrt = clamp(crtUV, vec2<f32>(0.0), vec2<f32>(1.0));

  let spread = 0.8 + depth * 1.5;
  let blurred = gaussian_spread(clampedCrt, resolution, spread);

  // Idea 2a: corner misconvergence. The three guns converge at the centre and
  // drift apart toward the corners: R/B split widens with r², and the blue gun
  // sags vertically as well.
  let rc = clampedCrt - 0.5;
  let conv = 0.35 + dot(rc, rc) * 5.0;
  let rOff = vec2<f32>(aberration * (1.0 + distortion * 0.3), aberration * 0.2 * rc.y) * conv;
  let bOff = vec2<f32>(-aberration * (1.0 + distortion * 0.2), aberration * 0.5 * rc.y) * conv;
  let crtR = blurred.r * 0.65 + textureSampleLevel(readTexture, u_sampler, clamp(clampedCrt + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r * 0.35;
  let crtG = blurred.g;
  let crtB = blurred.b * 0.65 + textureSampleLevel(readTexture, u_sampler, clamp(clampedCrt + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b * 0.35;
  var crtColor = vec3<f32>(crtR, crtG, crtB);

  let mask = shadow_mask(clampedCrt, resolution);
  crtColor = crtColor * mask;

  let moire = sin(clampedCrt.x * resolution.x * 0.35) * sin(clampedCrt.y * resolution.y * 0.35) * 0.04 + 0.96;
  crtColor = crtColor * moire;

  let scanline = sin(clampedCrt.y * resolution.y * 0.5 + time * 10.0 + bass * 5.0) * 0.5 + 0.5;
  crtColor = crtColor * (1.0 - scanline * scanlineInt);

  // Idea 1: electron-beam raster. A slowed-down beam sweeps the tube top to
  // bottom; lines it just hit are hot and the rest settle, while C keeps the
  // phosphor glow behind it. The beam line itself is a thin bright stroke.
  let beamY = fract(time * (0.45 + bass * 0.2));
  let beamAge = fract(beamY - clampedCrt.y);
  let beamHot = exp(-beamAge * 7.0);
  crtColor = crtColor * (0.85 + 0.4 * beamHot) + vec3<f32>(0.9, 0.95, 1.0) * smoothstep(0.004, 0.0, beamAge) * 0.25;

  // Idea 2b: halation. Light scattered in the faceplate glass blooms around
  // bright areas with a warm cast.
  // Bright-pass ring of 8 taps at ~10 px, so light spills past the edges of
  // highlights into the dark around them.
  var halo = vec3<f32>(0.0);
  let hr = (10.0 + depth * 6.0) / resolution;
  for (var k = 0; k < 8; k = k + 1) {
    let a = f32(k) * 0.785398;
    let tap = textureSampleLevel(readTexture, u_sampler, clamp(clampedCrt + vec2<f32>(cos(a), sin(a)) * hr, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    halo += max(tap - vec3<f32>(0.55), vec3<f32>(0.0));
  }
  let halation = halo * 0.125 * 1.2 * vec3<f32>(1.0, 0.8, 0.65) * (0.6 + treble * 0.4);
  crtColor += halation;

  let corner = clampedCrt.x * clampedCrt.y * (1.0 - clampedCrt.x) * (1.0 - clampedCrt.y);
  crtColor = crtColor * pow(max(corner * 16.0, 0.001), 0.18 + distortion * 0.08);
  crtColor = select(vec3<f32>(0.0), crtColor, in_bounds);

  // Exact C load (HEAD used a filtering sampler on rgba32float history).
  let prev = textureLoad(dataTextureC, coords, 0);
  let phosphorDecay = prev.rgb * 0.78;

  let cleanColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Idea 3: degauss purity rim. A click "degausses" the tube, so the clear-zone
  // rim wobbles in a decaying oscillation.
  var degauss = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let age = time - u.ripples[i].z;
    if (age >= 0.0 && age < 2.5) { degauss += sin(age * 28.0) * exp(-age * 2.2); }
  }
  let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let ang = atan2(toMouse.y, toMouse.x);
  let dist = length(toMouse) * (1.0 + degauss * 0.06 * sin(ang * 3.0 + time * 4.0));
  let clearMask = smoothstep(clearRadius, max(clearRadius - 0.06, 0.001), dist);
  let edge = smoothstep(clearRadius + 0.025, clearRadius, dist) - smoothstep(clearRadius, max(clearRadius - 0.025, 0.001), dist);
  let glowColor = vec3<f32>(0.25, 0.85, 1.0) * edge * 2.5;

  // Purity blotches: just outside the rim, the beam lands on the wrong
  // phosphor, giving slow magenta/green patches that swirl around it.
  let blotch = hash21(floor(vec2<f32>(ang * 1.6 + time * 0.3, dist * 9.0)));
  let ring = smoothstep(clearRadius + 0.14, clearRadius + 0.02, dist) * (1.0 - clearMask);
  let purity = mix(vec3<f32>(1.0), select(vec3<f32>(1.15, 0.8, 1.1), vec3<f32>(0.85, 1.15, 0.9), blotch > 0.5),
                   ring * (0.55 + abs(degauss) * 0.8));
  crtColor = crtColor * purity;

  var finalColor = mix(crtColor, cleanColor, clearMask) + glowColor;
  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(clearMask * 0.95 + (1.0 - clearMask) * (luma * 0.45 + f32(in_bounds) * 0.2) + edge * 0.35 + treble * 0.04, 0.0, 1.0);

  // Phosphor persistence in display space (C holds ACES output), CRT area only.
  let phosphor = phosphorDecay * vec3<f32>(0.9, 0.7, 0.5) * (1.0 - clearMask) * f32(in_bounds);
  let finalPixel = vec4<f32>(max(aces_tonemap(finalColor), phosphor), alpha);
  let outDepth = depth + (1.0 - clearMask) * 0.05;

  textureStore(writeTexture, coords, finalPixel);
  textureStore(dataTextureA, global_id.xy, finalPixel);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
