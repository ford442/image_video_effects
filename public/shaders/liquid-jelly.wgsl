// ═══════════════════════════════════════════════════════════════════
//  Liquid Jelly (Deep-polished Batch 59; Kelvin-Voigt foundation from Batch 51)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  A/C packing: display RGBA, exact bounded advected history. B unused.
//  extraBuffer[133..138]: sprung pointer position/velocity + init flag.
//  Upgraded: 2026-08-23
//
//  Batch 67 — fast motion / psychedelic / high energy:
//    A. Finite-speed shear wave. A real gel does not deform everywhere at
//       once; a shear disturbance travels at c = sqrt(G/rho). Click fronts
//       are gated on arrival time r/c, so the wobble visibly races outward
//       instead of appearing simultaneously across the frame.
//    B. Jiggle overshoot streaks — the refraction tap is smeared backwards
//       along the displacement direction, length proportional to the local
//       shear rate and clamped, so fast wobbles leave motion trails.
//    Colour: IQ candy palette keyed to gel thickness with per-band FFT hue
//    offsets and prismatic dispersion, replacing a warm/cool two-tone lerp.
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Viscoelastic Kelvin-Voigt harmonic modal oscillation
fn viscoelasticModalFlow(p: vec2<f32>, time: f32, elast: f32, damp: f32) -> vec2<f32> {
  let omega1 = 2.4 + elast * 0.8;
  let omega2 = 3.2 + elast * 1.1;
  let k1 = 4.0;
  let k2 = 6.0;
  let dispX = sin(p.y * k1 + time * omega1) * cos(p.x * k2 - time * omega2 * 0.7);
  let dispY = cos(p.x * k1 - time * omega1 * 0.85) * sin(p.y * k2 + time * omega2);
  return vec2<f32>(dispX, dispY) * (0.0035 / (1.0 + damp * 0.5));
}

// IQ cosine palette — high-chroma candy ramp keyed to a scalar quantity.
fn candy(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.2831853 * (
        vec3<f32>(1.0, 0.9, 1.1) * t + vec3<f32>(0.10, 0.42, 0.78)));
}

// Push channel spread away from luma so multi-hue mixes stay vivid rather
// than averaging toward grey.
fn vivify(c: vec3<f32>, amount: f32) -> vec3<f32> {
    let luma = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return max(vec3<f32>(0.0), mix(vec3<f32>(luma), c, 1.0 + amount));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let damping = mix(0.8, 3.8, u.zoom_params.x);
  let elasticity = mix(2.5, 14.0, u.zoom_params.y);
  let wobbleStrength = mix(0.006, 0.075, u.zoom_params.z);
  let tintShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  // A bounded critically damped pointer gives the gel an elastic recovery
  // target. Only (0,0) advances state; every pixel consumes the prior frame.
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var sprungMouse = u.zoom_config.yz;
  var springVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) {
    sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    springVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var springPos = sprungMouse;
    var springVel = springVelocity;
    let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { springPos = u.zoom_config.yz; springVel = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    springVel += ((u.zoom_config.yz - springPos) * (95.0 + elasticity * 4.0) - springVel * (18.0 + damping * 2.0)) * dt;
    springPos += springVel * dt;
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let foreground = 1.0 - smoothstep(0.72, 0.98, centerDepth);

  // Four smooth mechanisms: Kelvin-Voigt modes, fast shear, lobe orbit, soliton ridge.
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let modalFlow = viscoelasticModalFlow(pAspect, time, elasticity, damping) * foreground;
  let gelatinShear = vec2<f32>(
    sin(pAspect.y * 11.0 + time * (3.1 + audio.x * 3.0)),
    cos(pAspect.x * 10.0 - time * (2.7 + audio.y * 2.4))
  ) * (0.0018 / (1.0 + damping * 0.3)) * foreground;
  let lobeCenter = vec2<f32>(0.22 * sin(time * 2.1), 0.16 * cos(time * 2.7));
  let lobeDelta = pAspect - lobeCenter;
  let lobeDist = max(length(lobeDelta), 0.0001);
  let lobePulse = exp(-lobeDist * lobeDist * 18.0) * sin(lobeDist * 25.0 - time * 7.0);
  let soliton = 1.0 / cosh(clamp((pAspect.x + 0.22 * sin(pAspect.y * 8.0) - sin(time * 1.7) * 0.48) * 8.0, -8.0, 8.0));
  let lobeFlow = vec2<f32>(lobeDelta.x / aspect, lobeDelta.y) / lobeDist * lobePulse * wobbleStrength * 0.24;
  let solitonFlow = vec2<f32>(0.0, cos(pAspect.y * 13.0 + time * 4.0)) * soliton * wobbleStrength * 0.16;

  var displacement = modalFlow + gelatinShear + lobeFlow + solitonFlow;
  var wobbleEnergy = abs(lobePulse) * 0.32 + soliton * 0.42;
  var edgeEnergy = soliton * 0.28;

  // Interactive pointer drag / spring mass tether
  let mousePos = sprungMouse;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let tetherEnvelope = exp(-mouseDist * mix(7.0, 3.2, u.zoom_params.z));
  let tetherPhase = sin(time * elasticity * 1.2 - mouseDist * 14.0);
  let tetherForce = (mouseDelta / mouseDist) * tetherPhase * tetherEnvelope * (0.012 + wobbleStrength * 0.4) * (1.0 + isMouseDown * 2.5);
  displacement += vec2<f32>(tetherForce.x / aspect, tetherForce.y) * foreground;
  wobbleEnergy += tetherEnvelope * abs(tetherPhase);

  // 50-ripple shockwaves with Kelvin-Voigt damped response
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 3.8) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;

      // ── Fast motion A: finite shear-wave speed ────────────────────────
      // c = sqrt(G / rho) for a shear wave in an elastic solid; rho is folded
      // into the constant. Nothing moves until the front arrives, so the
      // deformation races outward at a visible, clamped speed instead of
      // appearing across the whole frame at once.
      let shearSpeed = clamp(sqrt(max(elasticity, 0.01)) * 0.16 + audio.x * 0.10, 0.05, 0.9);
      let arrival = rDist / shearSpeed;
      let sinceArrival = age - arrival;
      let arrived = step(0.0, sinceArrival);
      let front = arrived * smoothstep(0.0, 0.05, sinceArrival);

      let spring = sin(max(sinceArrival, 0.0) * (elasticity + audio.x * 5.0) - rDist * 18.0)
                 * exp(-max(sinceArrival, 0.0) * damping);
      let shape = exp(-rDist * mix(16.0, 4.5, u.zoom_params.z));
      let local = spring * shape * front;

      displacement += vec2<f32>(rDir.x / aspect, rDir.y) * local * wobbleStrength * (1.0 + audio.x * 0.65) * foreground;
      wobbleEnergy += abs(local);
      edgeEnergy += abs(spring) * front * pow(clamp(1.0 - abs(rDist - 0.15) * 7.5, 0.0, 1.0), 3.0);
    }
  }

  // Optical refraction and subsurface scattering
  let displacedUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));

  // ── Fast motion B: jiggle overshoot streaks ──────────────────────────
  // Smear the refraction tap backwards along the direction of travel. The
  // streak length tracks the local shear rate and is clamped, so a violent
  // wobble leaves a trail without the sample ever leaving the frame.
  let shearRate = clamp(length(displacement) * 26.0 + wobbleEnergy * 0.35, 0.0, 1.0);
  let streakDir = select(vec2<f32>(0.0), normalize(displacement), length(displacement) > 1e-5);
  let streakLen = clamp(shearRate * (0.010 + wobbleStrength * 0.35), 0.0, 0.045);
  var smear = vec4<f32>(0.0);
  var smearW = 0.0;
  for (var s = 0u; s < 5u; s = s + 1u) {
    let t = f32(s) / 4.0;
    let w = 1.0 - t * 0.72;
    let tapUV = clamp(displacedUV + streakDir * streakLen * t, vec2<f32>(0.0), vec2<f32>(1.0));
    smear += textureSampleLevel(readTexture, u_sampler, tapUV, 0.0) * w;
    smearW += w;
  }
  let baseColor = smear / max(smearW, 1e-4);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor((uv - displacement * (0.35 + 0.25 * u.zoom_params.x)) * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // The previous semantic alpha behaves as a coarse gel thickness field. Exact
  // neighboring C loads add persistent height slope to the analytic wobble.
  let histDims = vec2<i32>(resolution);
  let histL = textureLoad(dataTextureC, clamp(histCoord + vec2<i32>(-1, 0), vec2<i32>(0), histDims - vec2<i32>(1)), 0).a;
  let histR = textureLoad(dataTextureC, clamp(histCoord + vec2<i32>(1, 0), vec2<i32>(0), histDims - vec2<i32>(1)), 0).a;
  let histD = textureLoad(dataTextureC, clamp(histCoord + vec2<i32>(0, -1), vec2<i32>(0), histDims - vec2<i32>(1)), 0).a;
  let histU = textureLoad(dataTextureC, clamp(histCoord + vec2<i32>(0, 1), vec2<i32>(0), histDims - vec2<i32>(1)), 0).a;
  let historySlope = vec2<f32>(histL - histR, histD - histU) * (2.0 + elasticity * 0.25);
  // 2.5D surface normal & Fresnel rim
  let normal = normalize(vec3<f32>(-displacement * 28.0 + historySlope, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.045);

  let thickness = clamp(0.12 + length(displacement) * 22.0 + wobbleEnergy * 0.12, 0.0, 1.8);

  // Palette keyed to gel THICKNESS, with a per-band FFT hue offset so the
  // colour field reacts across the spectrum instead of pumping on one level,
  // and prismatic dispersion along the direction of travel.
  let bandIdx = u32(clamp(uv.x, 0.0, 0.999) * 8.0);
  let band = clamp(plasmaBuffer[bandIdx + 1u].x, 0.0, 1.0);
  let hue = fract(thickness * 0.55 + tintShift + time * 0.06
                  + band * 0.22 + shearRate * 0.30);
  let disperse = clamp(shearRate * 0.05, 0.0, 0.05);
  let scatterTint = vivify(vec3<f32>(
      candy(hue - disperse).r,
      candy(hue).g,
      candy(hue + disperse).b), 0.6);
  let absorption = exp(-thickness * vec3<f32>(1.6, 1.05, 0.6));

  let bioLime = vec3<f32>(0.48, 1.0, 0.18) * soliton * (0.08 + audio.z * 0.2);
  var rgb = mix(scatterTint, baseColor.rgb, absorption) + scatterTint * edgeEnergy * (0.2 + audio.y * 0.42) + fresnel * vec3<f32>(0.22, 0.34, 0.42) + bioLime;

  let trailMix = clamp((0.06 + u.zoom_params.x * 0.2) * clamp(history.a, 0.0, 1.0), 0.03, 0.3);
  rgb = mix(rgb, history.rgb, trailMix);
  rgb = acesToneMapping(rgb);

  let alpha = clamp(baseColor.a * foreground * (0.75 + thickness * 0.18) + edgeEnergy * 0.15 + fresnel * 0.12, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let outDepth = clamp(centerDepth + length(displacement) * 0.25 - wobbleEnergy * 0.05, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
