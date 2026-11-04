// ═══════════════════════════════════════════════════════════════════
//  Bismuth Crystal Growth — Phase-Field Hopper Crystal Solidification
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, phase-field-crystal,
//            hopper-crystals, thin-film-oxide-iridescence, semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-11-01
//  Ideas: hopper staircase from latent-heat isotherms; per-terrace oxide thickness; facet-locked glint
//  A packing: raw sim state (phase, temp, orientation, impurity); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
  return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let maxCoord = vec2<i32>(res) - vec2<i32>(1);
  let uv = vec2<f32>(gid.xy) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let supercoolingParam = u.zoom_params.x; // 0..1, def 0.5
  let anisoParam = u.zoom_params.y;        // 0..1, def 0.5
  let growthParam = u.zoom_params.z;       // 0..1, def 0.5
  let colorFreqParam = u.zoom_params.w;    // 0..1, def 0.5

  let supercooling = mix(0.15, 0.85, supercoolingParam);
  let anisotropy = mix(0.1, 0.65, anisoParam);
  let growthRate = mix(0.002, 0.015, growthParam);
  let colorFreq = colorFreqParam * 12.0 + 3.0;

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (gid.x == 0u && gid.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 36.0;
    let damping = 12.0;
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact previous state from dataTextureC
  let prevState = textureLoad(dataTextureC, coord, 0);
  var phase = prevState.r;
  var temp = prevState.g;
  var orientation = prevState.b;
  var impurity = prevState.a;

  // Initialize seed pattern
  if (time < 0.15 || (phase == 0.0 && temp == 0.0 && orientation == 0.0 && impurity == 0.0)) {
    phase = 0.0;
    temp = -0.3;
    orientation = 0.0;
    impurity = hash12(uv * 80.0) * 0.1;
    let centerDist = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    if (centerDist < 0.035) {
      phase = 1.0;
      temp = 0.0;
      orientation = atan2(uv.y - 0.5, (uv.x - 0.5) * aspect);
    }
  }

  phase = clamp(phase, 0.0, 1.0);
  temp = clamp(temp, -1.0, 1.0);
  impurity = clamp(impurity, 0.0, 1.0);

  // Exact neighbor loads from dataTextureC (4-connected stencil)
  let left  = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), maxCoord), 0);
  let right = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), maxCoord), 0);
  let down  = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), maxCoord), 0);
  let up    = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0);

  // Phase-field Laplacian & cubic 4-fold step anisotropy
  let lapPhase = left.r + right.r + down.r + up.r - 4.0 * phase;
  let gradPhase = vec2<f32>(right.r - left.r, up.r - down.r) * 0.5;
  let gradLen = length(gradPhase);
  let gradAngle = select(0.0, atan2(gradPhase.y, gradPhase.x), gradLen > 0.001);

  // 4-fold Hopper crystal cubic step anisotropy (90 degree ledges)
  let anisoStep = 1.0 + anisotropy * cos(4.0 * (gradAngle - orientation) + mids * 2.0);

  let drivingForce = temp + supercooling * (1.0 - 1.8 * impurity) + bass * 0.2;
  let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + drivingForce * 0.5);
  phase += phaseReaction * (growthRate * anisoStep) + lapPhase * (0.15 * growthRate);
  phase = clamp(phase, 0.0, 1.0);

  // Temperature diffusion & latent heat release
  let lapTemp = left.g + right.g + down.g + up.g - 4.0 * temp;
  let latentHeat = (phase - prevState.r) * 0.6;
  temp += lapTemp * 0.06 + latentHeat;
  temp = clamp(temp, -1.0, 1.0);

  // Crystal lattice orientation diffusion
  let lapOrient = left.b + right.b + down.b + up.b - 4.0 * orientation;
  orientation += lapOrient * 0.015 * phase;
  if (phase > 0.15 && phase < 0.85 && gradLen > 0.01) {
    orientation = mix(orientation, gradAngle, 0.06);
  }

  // Impurity segregation at solid-liquid interface
  let lapImpurity = left.a + right.a + down.a + up.a - 4.0 * impurity;
  let phaseChange = phase - prevState.r;
  impurity += lapImpurity * 0.02 - phaseChange * 0.12;
  impurity = clamp(impurity, 0.0, 1.0);

  // Mouse touch nucleation seed
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = smoothstep(0.06, 0.0, mouseDist) * (0.5 + held * 0.5);
  phase = mix(phase, 1.0, mouseInfluence);
  if (mouseInfluence > 0.01) {
    orientation = atan2(uv.y - mouse.y, (uv.x - mouse.x) * aspect);
    temp = mix(temp, 0.0, mouseInfluence);
  }

  // Click ripple nucleation shocks
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 1.8) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let nucleationWave = exp(-abs(rDist - age * 0.45) * 35.0) * exp(-age * 2.0);
    phase = mix(phase, 1.0, nucleationWave * 0.4);
  }
  phase = clamp(phase, 0.0, 1.0);

  // Store simulation state in dataTextureA
  textureStore(dataTextureA, coord, vec4<f32>(phase, temp, orientation, impurity));

  // ═══ Bismuth Hopper Visualization ═══
  let orientNorm = fract(orientation / TAU);
  let h6 = orientNorm * 6.0;
  let cc = 0.85;
  let xx = cc * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
  var baseCrystal = vec3<f32>(cc, xx, 0.3);
  if (h6 >= 1.0 && h6 < 2.0) { baseCrystal = vec3<f32>(xx, cc, 0.3); }
  else if (h6 >= 2.0 && h6 < 3.0) { baseCrystal = vec3<f32>(0.3, cc, xx); }
  else if (h6 >= 3.0 && h6 < 4.0) { baseCrystal = vec3<f32>(0.3, xx, cc); }
  else if (h6 >= 4.0 && h6 < 5.0) { baseCrystal = vec3<f32>(xx, 0.3, cc); }
  else if (h6 >= 5.0 && h6 < 6.0) { baseCrystal = vec3<f32>(cc, 0.3, xx); }

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let liquidColor = mix(src.rgb * 0.4, vec3<f32>(0.04, 0.07, 0.14) * (1.0 + temp * 0.5), 0.7);

  // Hopper step ledge pattern from phase contour
  let hopperStep = sin(phase * colorFreq * 4.0) * 0.5 + 0.5;
  let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
  let interfaceColor = vec3<f32>(0.92, 0.96, 1.0);

  var displayColor = mix(liquidColor, baseCrystal * (0.8 + hopperStep * 0.35), smoothstep(0.35, 0.65, phase));
  displayColor = mix(displayColor, interfaceColor, interfaceMask * 0.6);
  displayColor = mix(displayColor, vec3<f32>(0.85, 0.65, 0.45), impurity * 0.35);

  // ── Idea 1: hopper staircase from isotherms ───────────────────────
  // Inside the solid `phase` is ~1, so the ledges only lived on the interface.
  // The latent-heat wake in `temp` (already averaged with the four loaded
  // neighbours) steps inward behind the front like a hopper's recessed
  // terraces. Step count rides Color Frequency (its existing "ledge" role).
  // (Measured on SwiftShader: the solid's wake spans only ~0.15 in temp, hence
  // the gain; ~6 steps at the default Color Frequency.)
  let tWake = (temp * 4.0 + left.g + right.g + down.g + up.g) * 0.125;
  let terraceCoord = max(tWake + 0.4, 0.0) * max(colorFreq * 0.8, 2.0) * 6.0;
  let terraceId = floor(terraceCoord);
  let terraceFrac = fract(terraceCoord);
  let solidMask = smoothstep(0.6, 0.95, phase);
  let riserLit = exp(-terraceFrac * 18.0);
  let riserShade = smoothstep(0.82, 1.0, terraceFrac);
  displayColor = displayColor * (1.0 - solidMask * riserShade * 0.35);
  displayColor = displayColor + vec3<f32>(1.0, 0.96, 0.88) * solidMask * riserLit * 0.22;

  // Bismuth oxide thin-film rainbow iridescence
  let cosTheta = clamp(1.0 - length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0)) * 0.6, 0.0, 1.0);
  let F0_bismuth = vec3<f32>(0.82, 0.86, 0.92);
  let fresnel = fresnelMetal(cosTheta, F0_bismuth);

  // ── Idea 2: per-terrace oxide thickness ──────────────────────────
  // Each terrace is a plateau with its own oxide thickness, so the existing
  // oxide palette jumps colour at every riser instead of sweeping the crystal.
  let oxideThickness = (phase * colorFreq + time * 0.15 + treble * 0.4 + terraceId * 0.37 * solidMask) * TAU;
  let rainbowOxide = vec3<f32>(
    0.5 + 0.5 * cos(oxideThickness + 0.0),
    0.5 + 0.5 * cos(oxideThickness + 2.094),
    0.5 + 0.5 * cos(oxideThickness + 4.188)
  );

  displayColor = mix(displayColor, displayColor * (rainbowOxide * 1.5) + fresnel * 0.3, phase * 0.75);

  // Specular sheen on crystal step edges
  let stepEdge = abs(gradLen) * 3.0;
  displayColor += vec3<f32>(1.0, 0.98, 0.92) * (stepEdge * phase * 0.5);

  // ── Idea 3: facet-locked glint ───────────────────────────────────
  // Where the interface normal lies on a crystal axis (the same cos(4θ) term
  // as anisoStep) the ledge is a flat facet and mirrors a slowly turning light.
  let facetAlign = max(cos(4.0 * (gradAngle - orientation)), 0.0);
  let facetFlat = facetAlign * facetAlign * facetAlign * facetAlign;
  let lightSweep = 0.5 + 0.5 * cos(orientation * 2.0 - time * 0.6 + bass * 1.5);
  let ifaceStrength = smoothstep(0.01, 0.06, gradLen) * smoothstep(0.1, 0.4, phase);
  let facetGlint = facetFlat * lightSweep * lightSweep * ifaceStrength;
  displayColor = displayColor + vec3<f32>(0.85, 0.95, 1.0) * facetGlint * 0.55;

  // ACES Tonemap
  let finalRGB = aces(displayColor);

  // Semantic alpha: metallic solid presence + liquid transparency
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(mix(src.a, 0.45 + phase * 0.55, 0.8) + interfaceMask * 0.15 + facetGlint * 0.1, 0.35, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
