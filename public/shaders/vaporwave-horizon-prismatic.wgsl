// ═══════════════════════════════════════════════════════════════════
//  Vaporwave Horizon Prismatic
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: perspective-filtered neon grid (analytic pixel footprint, far lines fade to mean density instead of aliasing); sun reflection on the mirror floor (striped half-disc re-evaluated at the mirrored point, glitter-row shimmer + glitter path); energy-conserving phosphor bloom (§12.2F, grid colour mixed with its own 8-tap blur)
//  A packing: ACES display RGBA (CRT phosphor persistence). Texels (0,0) = (fract scrollPhase, heldSmooth, 0, 1) and (1,0) = (fract lastTime, 0, 0, 0.7371 sentinel) are STATE, not pixels (their phosphor read is masked; their displayed output is normal). B unused; depth passes through source depth.
//  Retro synthwave perspective grid with 4-band Cauchy spectral reflection and sunset sky.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

const SENT: f32 = 0.7371;
// Neon colours (unit, glowIntensity applied by the caller)
const NEON_CYAN: vec3<f32> = vec3<f32>(0.05, 0.95, 1.0) * 1.8;
const NEON_MAGENTA: vec3<f32> = vec3<f32>(1.0, 0.1, 0.8) * 2.2;

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  // texels (0,0)/(1,0) hold scroll state, not phosphor
  let isState = (coord.y == 0) && (coord.x < 2);
  return select(textureLoad(dataTextureC, coord, 0), vec4<f32>(0.0), isState);
}

// ── Idea 1: perspective-filtered grid line ───────────────────────────
// Same smoothstep line as before, widened by the pixel footprint `fw` (grid units per
// pixel) and band-limited: once a pixel spans more than the line, the amplitude settles
// at the line's mean density `lw` instead of aliasing. Foreground (fw << lw) is HEAD.
fn lineCov(g: f32, lw: f32, fw: f32) -> f32 {
  let base = smoothstep(lw + 0.5 * fw, 0.0, g);
  let amp = clamp(lw / max(fw, 1e-4), lw, 1.0);
  return base * amp;
}

// Floor grid at a floor-space uv (uv.y > horizon). Returns unit neon colour (rgb) and coverage (a).
fn gridAt(uv: vec2<f32>, horizon: f32, curve: f32, rip: vec2<f32>, K: f32, phase: f32, px: vec2<f32>) -> vec4<f32> {
  let dy = max(uv.y - horizon, 0.001);
  let zDepth = 1.0 / dy;
  let xOffset = curve * dy * dy;
  let xr = uv.x - 0.5 - xOffset + rip.x;
  let gridU = xr * zDepth * K + 0.5;
  let gridV = zDepth * K + phase + rip.y * 10.0;

  let gx = abs(fract(gridU) - 0.5);
  let gy = abs(fract(gridV) - 0.5);
  let lw = 0.06 * (1.0 + dy * 0.5);

  // analytic footprint: dV/dy = -K/dy^2 ; dU/dx = K/dy ; dU/dy = -2 curve K - xr K / dy^2
  let fwV = K * zDepth * zDepth * px.y;
  let fwU = K * zDepth * px.x + (2.0 * abs(curve) * K + abs(xr) * K * zDepth * zDepth) * px.y;
  let cov = clamp(lineCov(gx, lw, fwU) + lineCov(gy, lw, fwV), 0.0, 1.0);

  // intersection tint: far away the cells average out, so use the mean distance (0.25)
  let gxF = mix(gx, 0.25, clamp(fwU, 0.0, 1.0));
  let gyF = mix(gy, 0.25, clamp(fwV, 0.0, 1.0));
  let tint = mix(NEON_CYAN, NEON_MAGENTA, gxF * gyF * 4.0);
  return vec4<f32>(tint * cov, cov);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let gridSpeed = 0.2 + u.zoom_params.x * 2.5;
  let glowIntensity = (0.25 + u.zoom_params.y * 2.2) * (1.0 + bass * 0.45);
  let gridScale = 0.3 + u.zoom_params.z * 1.8;
  let warpAmount = 0.1 + u.zoom_params.w * 1.6;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let horizon = select(0.52, clamp(rawMouse.y, 0.2, 0.8), hasMouse);
  let mouseX = select(0.5, rawMouse.x, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // ── R1: scroll phase + held ease are integrated state (A texels (0,0)/(1,0)) ──
  // HEAD scrolled with time*gridSpeed*heldBoost, so pressing the button teleported the
  // grid by 0.5*time*gridSpeed. Every thread integrates the same step from the same
  // two C texels; fract(time)/fract(phase) keep it exact on rgba16float tiers.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stOk = abs(st1.w - SENT) < 0.001;
  let heldT = select(0.0, 1.0, held);
  var dtS = clamp(fract(time - st1.x), 0.0, 0.5);
  dtS = select(dtS, 0.016, dtS > 0.25);
  let heldPrev = select(heldT, st0.y, stOk);
  let heldS = mix(heldPrev, heldT, 1.0 - exp(-dtS / 0.15));
  let phasePrev = select(fract(time * gridSpeed), st0.x, stOk);
  let scrollPhase = fract(phasePrev + select(0.0, dtS, stOk) * gridSpeed * (1.0 + 0.5 * heldS));
  let heldBoost = 1.0 + 0.5 * heldS;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var rippleGlow = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.34 + bass * 0.12);
      let wave = sin((rd - front) * 58.0) * exp(-abs(rd - front) * 25.0) * exp(-age * 1.1);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.025;
      rippleGlow += abs(wave) * 0.2;
    }
  }

  let curve = (mouseX - 0.5) * 3.0 * warpAmount;

  var outRGB = vec3<f32>(0.0);
  var alpha = 1.0;

  if (uv.y < horizon) {
    // ═══ SKY REGION ═══
    let skyNormY = uv.y / max(horizon, 0.01);
    let skyUV = vec2<f32>(uv.x, skyNormY) + rippleOffset;
    let bgSky = textureSampleLevel(readTexture, u_sampler, clamp(skyUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // Sunset gradient (deep violet top to fiery magenta/orange bottom)
    let violet = vec3<f32>(0.12, 0.04, 0.28);
    let magenta = vec3<f32>(0.85, 0.12, 0.55);
    let orange = vec3<f32>(1.0, 0.55, 0.15) * (1.0 + mids * 0.3);
    let skyGradient = mix(violet, mix(magenta, orange, pow(skyNormY, 2.0)), skyNormY);

    // Glowing retro sun disc centered on horizon
    let sunPos = vec2<f32>(0.5, horizon);
    let sunDelta = (uv - sunPos) * aspectVec;
    let sunDist = length(sunDelta);
    let sunRadius = 0.22 * heldBoost;
    let sunDisc = smoothstep(sunRadius, sunRadius - 0.015, sunDist);

    // Horizontal retro blinds stripes across the sun
    let stripeY = fract((uv.y - horizon + sunRadius) * 24.0);
    let stripeGap = smoothstep(0.0, 0.35, skyNormY) * 0.45;
    let stripeMask = step(stripeGap, stripeY);
    let stripedSun = sunDisc * stripeMask;

    // Sun gradient (yellow top, magenta bottom)
    let sunColor = mix(vec3<f32>(1.2, 0.9, 0.2), vec3<f32>(1.0, 0.15, 0.5), (uv.y - (horizon - sunRadius)) / (2.0 * sunRadius));
    let sunGlow = exp(-sunDist * 8.0) * glowIntensity * 0.75 * vec3<f32>(1.0, 0.3, 0.6);

    outRGB = mix(bgSky * 0.6 + skyGradient * 0.7, sunColor * 1.5, stripedSun) + sunGlow;
    alpha = 0.92;
  } else {
    // ═══ FLOOR REGION (Prismatic Perspective Grid) ═══
    let dy = max(uv.y - horizon, 0.001);
    let zDepth = 1.0 / dy;
    let K = 0.4 + gridScale * 0.6;
    let px = vec2<f32>(1.0) / resolution;

    // Grid (Idea 1: footprint-filtered) with Idea 3: energy-conserving phosphor bloom.
    let gCentre = gridAt(uv, horizon, curve, rippleOffset, K, scrollPhase, px);
    // 8 taps on two rings (1.6 and 3.6 px-ish of a 230 px frame, resolution-relative)
    let ringA = 0.007;
    let ringB = 0.016;
    let ax = vec2<f32>(1.0 / aspect, 1.0);
    var spread = vec3<f32>(0.0);
    for (var k: i32 = 0; k < 4; k = k + 1) {
      let ang = f32(k) * 1.5707963;
      let d = vec2<f32>(cos(ang), sin(ang)) * ax;
      spread += gridAt(uv + d * ringA, horizon, curve, rippleOffset, K, scrollPhase, px).rgb * 0.15;
      spread += gridAt(uv + d * ringB, horizon, curve, rippleOffset, K, scrollPhase, px).rgb * 0.10;
    }
    // out = src*(1-k) + blur*k : the halo is paid for by the line core (weights sum to 1)
    let gridColor = mix(gCentre.rgb, spread, 0.4) * glowIntensity;
    let gridVal = gCentre.a;

    // 4-band spectral Cauchy reflection
    let reflY = clamp(horizon - dy, 0.0, 1.0);
    let reflUV = vec2<f32>(uv.x, reflY);

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var reflColor = vec3<f32>(0.0);
    let cauchyB = 0.04 * warpAmount;

    for (var i: i32 = 0; i < 4; i = i + 1) {
      let lambda = WAVELENGTHS[i];
      let ior = cauchyIOR(lambda, 1.45, cauchyB);
      let dispOffset = (reflUV - vec2<f32>(0.5, horizon)) * (1.0 - 1.0 / ior) * 0.2;
      let sampleUV = clamp(reflUV + dispOffset, vec2<f32>(0.0), vec2<f32>(1.0));
      let sampleCol = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      let spectralWeight = wavelengthToRGB(lambda);
      reflColor += spectralWeight * dot(sampleCol, spectralWeight) * 0.45;
    }

    // ── Idea 2: sun reflection on the mirror floor ──────────────────
    // The photo is mirrored through reflY but the sun (synthesised in the sky branch) was
    // not. Re-evaluate the striped half-disc at the mirrored point, break it into
    // horizontal glitter rows, and let a narrow glitter path run toward the viewer.
    let rSunR = 0.22 * heldBoost;
    let rowPh = dy * 260.0 - time * 2.2;
    let jx = sin(rowPh) * 0.010 * smoothstep(0.0, 0.1, dy);
    let mdx = (uv.x - 0.5 + jx) * aspect;
    let mDist = sqrt(mdx * mdx + dy * dy);
    let rDisc = smoothstep(rSunR, rSunR - 0.015, mDist);
    let rStripeY = fract((rSunR - dy) * 24.0);
    let rSkyN = clamp(reflY / max(horizon, 0.01), 0.0, 1.0);
    let rStripe = step(smoothstep(0.0, 0.35, rSkyN) * 0.45, rStripeY);
    let rSunCol = mix(vec3<f32>(1.2, 0.9, 0.2), vec3<f32>(1.0, 0.15, 0.5), clamp((reflY - (horizon - rSunR)) / (2.0 * rSunR), 0.0, 1.0));
    let rowHash = hash12(vec2<f32>(floor(dy * 120.0), floor(time * 5.0)));
    let pathW = 0.03 + dy * 0.12;
    let path = exp(-(mdx * mdx) / (pathW * pathW)) * step(0.55, rowHash) * exp(-dy * 3.0) * smoothstep(0.0, 0.04, dy);
    let sunRefl = (rDisc * rStripe * rSunCol * 1.5 * 0.55 + path * vec3<f32>(1.0, 0.45, 0.75) * 0.7)
                * (1.0 + bass * 0.2) * (1.0 + 0.3 * rippleGlow);

    // Reflection blend with floor
    let reflectionFade = smoothstep(0.0, 0.35, dy);
    let floorBase = reflColor * 0.65 * reflectionFade + sunRefl;

    // Volumetric distance fog near horizon
    let fogDist = zDepth * 0.25;
    let fogDensity = exp(-fogDist * 0.8);
    let fogColor = vec3<f32>(0.45, 0.08, 0.4) * (1.0 + mids * 0.3);

    outRGB = mix(fogColor, floorBase + gridColor, 1.0 - fogDensity * 0.85);
    alpha = clamp(0.85 + gridVal * 0.15, 0.0, 1.0);
  }

  // Exact previous frame history load for CRT phosphor glow
  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = outRGB + vec3<f32>(rippleGlow);
  hdr += history.rgb * 0.06;

  // CRT scanlines
  let scanline = 0.94 + 0.06 * sin(uv.y * resolution.y * 3.14159);
  hdr *= scanline;

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  var aOut = result;
  if (coord.y == 0 && coord.x == 0) { aOut = vec4<f32>(scrollPhase, heldS, 0.0, 1.0); }
  if (coord.y == 0 && coord.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
