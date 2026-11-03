// ═══════════════════════════════════════════════════════════════════
//  Cinematic Flare
//  Category: lighting-effects
//  Features: audio-reactive, depth-aware, mouse-driven, upgraded-rgba, click-reactive
//  Complexity: High
//  Upgraded: 2026-11-02
//  Ideas: lens dirt speckle occlusion along flare axis; veiling glare bloom between light and center; iris-polygon ghost chain along the light→centre axis; spectral (λ-scaled) diffraction spikes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

fn lensDirtSpeckle(axisUV: vec2<f32>, time: f32) -> f32 {
  let speckle1 = hash12(axisUV * 180.0 + time * 0.04);
  let speckle2 = hash12(axisUV * 420.0 - time * 0.03 + 17.0);
  let speckle = mix(speckle1, speckle2, 0.5);
  return mix(0.55, 1.0, smoothstep(0.72, 0.95, speckle));
}

fn veilingGlare(axisT: f32, lumaHot: f32, intensity: f32) -> f32 {
  let axisFog = exp(-abs(axisT - 0.5) * 6.5) * (1.0 - abs(axisT - 0.5) * 1.6);
  return axisFog * lumaHot * intensity * 0.35;
}

// Signed distance to a regular hexagon of inradius r (the 6-blade iris).
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
  let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
  var q = abs(p);
  q = q - 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
  q = q - vec2<f32>(clamp(q.x, -k.z * r, k.z * r), r);
  return length(q) * sign(q.y);
}

// Idea 2 (spectral spikes): `sharp` is per channel — the sinc lobe width scales with λ, so the
// red spike is wider than the blue one (G = HEAD's 8.0).
fn diffractionSpike(dir: vec2<f32>, intensity: f32, sharp: vec3<f32>) -> vec3<f32> {
  let angle = atan2(dir.y, dir.x);
  var spike = vec3<f32>(0.0);
  for (var b = 0; b < 6; b = b + 1) {
    let bladeAngle = f32(b) * 0.5235987756;
    // Wrap to (−π/2, π/2]: each blade spike is a full line through the light (HEAD only drew
    // the half of the starburst whose atan2 fell in 0..150°)
    var diff = angle - bladeAngle;
    diff = diff - 3.14159265 * round(diff / 3.14159265);
    let sinc = sin(diff * sharp) / (diff * sharp + vec3<f32>(0.001));
    spike = spike + sinc * sinc;
  }
  return spike * intensity * 0.15;
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

  let flareIntensity = (0.2 + u.zoom_params.x * 2.2) * (1.0 + bass * 0.45);
  let streakLen = 0.05 + u.zoom_params.y * 0.45;
  let chromaShift = 0.005 + u.zoom_params.z * 0.045;
  let threshold = 0.2 + u.zoom_params.w * 0.65;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let haze = mix(0.5, 1.0, depth);

  let mouse = u.zoom_config.yz;
  let hasMouse = mouse.x >= 0.0 && mouse.x <= 1.0 && mouse.y >= 0.0 && mouse.y <= 1.0;
  let lightPos = select(vec2<f32>(0.5, 0.5), mouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  let uvAspect = uv * aspectVec;
  let lightAspect = lightPos * aspectVec;
  let toLight = lightAspect - uvAspect;
  let lightDist = length(toLight);
  let lightDir = normalize(toLight + vec2<f32>(0.0001));

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLuma = dot(sourceColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let lumaHot = smoothstep(threshold, threshold + 0.25, sourceLuma);

  // Flare axis parameter: light source → image center (for dirt + veiling glare)
  let centerAspect = vec2<f32>(0.5, 0.5) * aspectVec;
  let axisSpan = max(length(centerAspect - lightAspect), 0.0001);
  let axisT = clamp(dot(uvAspect - lightAspect, centerAspect - lightAspect) / (axisSpan * axisSpan), 0.0, 1.0);
  let dirtOcclusion = lensDirtSpeckle(vec2<f32>(axisT, lightDist), time);

  // Click ripple interaction
  var rippleDeflect = vec2<f32>(0.0);
  var rippleLight = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.35 + bass * 0.1);
      let ring = sin((rd - front) * 65.0) * exp(-abs(rd - front) * 28.0) * exp(-age * 1.2);
      rippleDeflect += rDelta / max(rd, 0.0001) * ring * 0.015;
      rippleLight += abs(ring) * 0.2;
    }
  }

  // Anamorphic horizontal streak with Cauchy dispersion
  var streakAccum = vec3<f32>(0.0);
  let streakSamples = 14;
  let streakAxis = vec2<f32>(1.0, 0.0);
  let heldStreakBoost = select(1.0, 1.6, held);

  for (var s = 0; s < streakSamples; s = s + 1) {
    let t = (f32(s) / f32(streakSamples - 1)) - 0.5;
    let offsetUV = uv + streakAxis * (t * streakLen * heldStreakBoost) + rippleDeflect;
    let clampedUV = clamp(offsetUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);
    let sampleLuma = dot(sampleColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let hot = smoothstep(threshold, threshold + 0.2, sampleLuma);

    // Spectral dispersion across streak samples
    let disp = t * chromaShift;
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(offsetUV + vec2<f32>(disp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(offsetUV - vec2<f32>(disp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let dispersed = vec3<f32>(rSample, sampleColor.g, bSample);

    streakAccum += dispersed * hot;
  }
  // HEAD fix: HEAD divided by the summed hot weight, so one hot tap anywhere in the window gave
  // the full average colour — every highlight became a flat block with no falloff. Dividing by
  // the tap count makes the streak fade with the fraction of hot taps (same value when all are).
  let streak = streakAccum / f32(streakSamples) * flareIntensity * haze * dirtOcclusion;

  // Cooke triplet ghosts: 3 elements with anti-reflection coating colors
  var ghosts = vec3<f32>(0.0);
  let ghostCoeffs = array<f32, 3>(0.38, -0.24, 0.14);
  let ghostColors = array<vec3<f32>, 3>(
    vec3<f32>(1.0, 0.82, 0.65),
    vec3<f32>(0.65, 0.88, 1.0),
    vec3<f32>(0.95, 0.65, 0.9)
  );

  for (var g = 0; g < 3; g = g + 1) {
    let ghostUV = lightPos + (lightPos - uv) * ghostCoeffs[g] + rippleDeflect;
    let ghostSample = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let ghostLuma = dot(ghostSample.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let ghostHot = smoothstep(threshold + 0.05, threshold + 0.35, ghostLuma);
    let ghostDist = length((uv - ghostUV) * aspectVec);
    let ghostFalloff = exp(-ghostDist * 5.0);

    // Cauchy dispersion on ghosts
    let ghostDisp = chromaShift * (f32(g) + 1.0) * 0.5;
    let rG = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV + vec2<f32>(ghostDisp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bG = textureSampleLevel(readTexture, u_sampler, clamp(ghostUV - vec2<f32>(ghostDisp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let dispersedGhost = vec3<f32>(rG, ghostSample.g, bG);

    ghosts += dispersedGhost * ghostHot * ghostFalloff * ghostColors[g] * flareIntensity * 0.6 * dirtOcclusion;
  }

  // Idea 1: iris-polygon ghost chain. The light's own inter-element reflections land on the
  // light→centre axis at uv_g = c + (c − L)·s (s = −1 is the light, s = 1 its mirror image) and
  // are images of the 6-blade iris that makes the starburst: hexagons, brighter at the rim where
  // the coating reflection piles up, tinted with the Cooke coating colours.
  let irisS = array<f32, 4>(-0.45, 0.35, 0.8, 1.25);
  let irisR = array<f32, 4>(0.035, 0.06, 0.028, 0.085);
  var irisGhosts = vec3<f32>(0.0);
  for (var k = 0; k < 4; k = k + 1) {
    let gC = (centerAspect + (centerAspect - lightAspect) * irisS[k]) + rippleDeflect * aspectVec;
    let rad = irisR[k] * (1.0 + mids * 0.2);
    let hd = sdHexagon(uvAspect - gC, rad);
    let fill = smoothstep(0.004, -0.004, hd);
    let rimLift = 0.3 + 0.7 * smoothstep(-rad * 0.6, 0.0, hd);
    irisGhosts += ghostColors[k % 3] * fill * rimLift;
  }
  // Ghosts are images of the light, so they follow how hot the source under the pointer is
  // (a dim floor keeps the chain readable as a lens artefact)
  let lightLuma = dot(textureSampleLevel(readTexture, u_sampler, lightPos, 0.0).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let lightHot = smoothstep(threshold, threshold + 0.25, lightLuma);
  irisGhosts *= flareIntensity * 0.55 * haze * dirtOcclusion * (0.25 + 0.75 * lightHot);

  // 6-blade diffraction starburst from bright light source
  // Idea 2: spectral spikes. Diffraction angle ∝ λ, so each channel's spike is λ/550 as wide and
  // reaches λ/550 as far: red tips and edges outrun blue ones (G keeps HEAD's spike exactly).
  let lambdaRatio = vec3<f32>(650.0, 550.0, 450.0) / 550.0;
  let spike = diffractionSpike(lightDir, flareIntensity * (0.8 + treble * 0.4), 8.0 / lambdaRatio)
    * exp(-lightDist * 1.8 / lambdaRatio);

  // Mie scattering halo around light source
  let haloRadius = 7.0 / max(0.5 + bass * 0.5, 0.1);
  let halo = exp(-lightDist * lightDist * haloRadius) * flareIntensity * 0.65 * vec3<f32>(1.0, 0.92, 0.8);

  // Veiling glare: axis fog between light source and image center
  let veil = vec3<f32>(1.0, 0.94, 0.82) * veilingGlare(axisT, lumaHot, flareIntensity) * haze;

  // Combine flare components
  let flareTotal = streak + ghosts + irisGhosts + halo + spike + vec3<f32>(rippleLight) + veil;
  let goldAtmosphere = vec3<f32>(1.0, 0.85, 0.55) * mids * 0.3 * flareIntensity * haze;

  // Exact previous frame history load for persistence of vision
  let history = historyAt(uv - rippleDeflect * 0.5, resolution);

  var hdr = sourceColor.rgb + flareTotal + goldAtmosphere;
  hdr += history.rgb * 0.06;

  // Film grain
  let grain = (hash12(uv * resolution.xy + time * 10.0) - 0.5) * 0.025 * (1.0 + treble * 0.5);
  hdr += vec3<f32>(grain);

  let flareLuma = dot(flareTotal, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alpha = clamp(sourceColor.a * 0.5 + flareLuma * 0.5 * haze + rippleLight * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
