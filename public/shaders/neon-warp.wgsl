// ═══════════════════════════════════════════════════════════════════
//  Neon Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha, depth-aware
//  Complexity: High
//  Upgraded: 2026-10-05, 2026-11-10
//  Ideas: convective plume (heat sources elongated upward by Diffusion); schlieren bands (rising sin bands modulate refraction inside a plume); inferior mirage (vertically mirrored tap about the hottest source where heat > 0.6); Gladstone–Dale density refraction (native: deflection ∝ ∇ρ with ρ ∝ 1/(1+g·heat), so the shoulder refracts more than the incandescent core); Planck-cooling afterglow (native: a decaying heat memory, rate keyed to Cooling, re-enters the blackbody ramp so a trail cools white→orange→red; the trail is bright behind a HELD pointer or after clicks and only a faint dim-red smear behind a free-moving unheld pointer, whose ember is 0.15 — nothing at all for a static pointer or bass alone; decay is per frame, i.e. trail length scales with fps like HEAD's 18% history)
//  A packing: linear pre-ACES RGB (18% advected exact-C history) + A.a = 13 + heat memory in 0..2 (validity band 12.5–15.5, clear of the 9.5–11.5 band that glitch-reveal / pixel-reveal / mosaic-reveal use; mem <= 2 stays under 16 so an rgba16float A keeps step 2^-7; HEAD stored the output alpha there and nothing read it). Output alpha is still the semantic heat-energy alpha.
//  Heat field is closed-form from pointer/ripples — not a raw A simulation
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

struct ThermalField {
  heat: f32,
  grad: vec2<f32>,
  pulse: f32,
  center: vec2<f32>,   // centre of the strongest contributing source (for the mirage)
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  let cool = t <= 6600.0;
  let r = select(1.29293618 * pow(max(tt - 60.0, 0.01), -0.1332047592), 1.0, cool);
  let g = select(1.12989086 * pow(max(tt - 60.0, 0.01), -0.0755148492), 0.39008157 * log(tt) - 0.63184144, cool);
  let b = select(1.0, select(0.0, 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408, t >= 2000.0), cool);
  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 1: convective plume — the gaussian is anisotropic: above the source
// (delta.y < 0, since y=0 is the top) its vertical variance is stretched by
// (1 + plume)², so every heat source trails a plume rising off the screen.
fn addSource(uv: vec2<f32>, center: vec2<f32>, aspect: f32, sigma: f32, amp: f32, plume: f32, field: ThermalField) -> ThermalField {
  var outf = field;
  let delta = vec2<f32>((uv.x - center.x) * aspect, uv.y - center.y);
  let upness = 1.0 - smoothstep(-0.015, 0.015, delta.y);
  let stretch = 1.0 + plume * upness;
  let sx = max(sigma, 1e-5);
  let sy = max(sigma * stretch * stretch, 1e-5);
  let r2 = delta.x * delta.x / sx + delta.y * delta.y / sy;
  let contribution = amp * exp(-r2);
  let gradAspect = contribution * (-2.0) * vec2<f32>(delta.x / sx, delta.y / sy);
  outf.heat = outf.heat + contribution;
  outf.grad = outf.grad + vec2<f32>(gradAspect.x / aspect, gradAspect.y);
  outf.center = select(outf.center, center, contribution > outf.pulse);
  outf.pulse = max(outf.pulse, contribution);
  return outf;
}

fn safeRGB(v: vec3<f32>) -> vec3<f32> {
  return clamp(select(vec3<f32>(0.0), v, v == v), vec3<f32>(0.0), vec3<f32>(16.0));
}

// Idea 4 tuning (Gladstone–Dale): ρ ∝ 1/(1 + GD_G·heat); GD_REF is the heat at which the
// deflection equals HEAD's (≈ the shoulder of a held source); GD_MAX caps the shoulder gain.
const GD_G: f32 = 1.5;
const GD_REF: f32 = 0.5;
const GD_MAX: f32 = 1.3;
// Idea 5 tuning (Planck-cooling afterglow): per-second heat-memory decay = Cooling · CA_RATE
// (60 fps cadence, like HEAD's 18 % history); CA_FLOOR is a linear floor so an rgba16float
// history (step 2^-7 at 10..16) cannot stall a faint trail; CA_MAX bounds the memory.
const CA_RATE: f32 = 1.3;
const CA_FLOOR: f32 = 0.008;
const CA_MAX: f32 = 2.0;
const CA_ON: f32 = 1.0;
// A.a marker: 13 + memory. Foreign alphas (0.7371, 1.0, the 9.5–11.5 reveal band) fall outside 12.5–15.5.
const CA_BASE: f32 = 13.0;
// Trail brightness: the mask opens at 0.02 so a free-moving ember (0.15) leaves a faint smear, and
// CA_GAIN keeps a held drag's trail well below the live ember so the swept disc does not blow out.
const CA_LO: f32 = 0.02;
const CA_HI: f32 = 0.30;
const CA_GAIN: f32 = 0.55;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;   // FIX: raw pointer, the extraBuffer spring never persisted
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;   // FIX: plasmaBuffer[4]/[8] were always 0

  let refractionStrength = mix(0.001, 0.04, u.zoom_params.x);
  let diffusion = mix(0.35, 1.8, u.zoom_params.y);
  let glowGain = mix(0.25, 2.6, u.zoom_params.z);
  let cooling = mix(0.35, 2.2, u.zoom_params.w);

  // Idea 1: plume length grows with Diffusion (default ≈ 2× taller than wide).
  let plume = 0.4 + diffusion * 0.6;

  var field: ThermalField;
  field.heat = 0.0;
  field.grad = vec2<f32>(0.0);
  field.pulse = 0.0;
  field.center = mouse;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let alive = age > 0.0 && age < 4.0;
    let sigma = 0.003 + diffusion * (0.02 + age * 0.04);
    let amp = exp(-age * cooling) * (1.0 + 0.5 * sin(age * 8.0));
    field = addSource(uv, ripple.xy, aspect, sigma, select(0.0, amp, alive), plume, field);
  }

  // FIX: idle cursor is a faint ember (0.15); holding brings the full source.
  let mouseAmp = select(0.15, 1.4, held);
  field = addSource(uv, mouse, aspect, 0.006 + diffusion * 0.015, mouseAmp, plume, field);

  for (var j = 0u; j < 3u; j = j + 1u) {
    let phase = time * 0.55 + f32(j) * 2.094;
    let center = vec2<f32>(0.5 + 0.32 * sin(phase * 1.17 + f32(j)), 0.5 + 0.28 * cos(phase * 0.91 + f32(j) * 1.7));
    let packet = 0.5 + 0.5 * sin(time * 2.3 + f32(j) * 2.1);
    let amp = bass * packet * 0.7 * exp(-cooling * 0.15);
    field = addSource(uv, center, aspect, 0.004 + diffusion * 0.012, amp, plume, field);
  }

  let heat = clamp(field.heat, 0.0, 4.0);

  // ── Idea 2: schlieren bands — inside a plume the refraction is modulated by
  // thin bands that rise (phase moves toward y=0) with time, scaled by heat.
  let bands = sin(uv.y * 90.0 + uv.x * 6.0 + time * 6.0 * (1.0 + mids * 0.5));
  let schlieren = 1.0 + 0.6 * bands * min(heat, 1.0);

  let whip = vec2<f32>(-field.grad.y, field.grad.x) * (0.35 + treble * 0.25);
  let advect = field.grad * 0.015 + whip * 0.02;
  let temperature = 300.0 + field.heat * 6000.0 + bass * 900.0;
  // ── Idea 4: Gladstone–Dale density refraction (native) ──────────────
  // Light bends with the density gradient, n−1 ∝ ρ ∝ 1/T, not with the temperature gradient:
  // deflection ∝ ∇heat/(1+g·heat)². HEAD displaced ∝ ∇heat everywhere; this rescales the same
  // vector by f(heat) = ((1+g·ref)/(1+g·heat))² (f = 1 at `ref`), so the cool shoulder of every
  // plume refracts harder and the white-hot core flattens. Refraction Strength keeps its role.
  let gdNum = 1.0 + GD_G * GD_REF;
  let gdDen = 1.0 + GD_G * heat;
  let gdScale = min((gdNum * gdNum) / (gdDen * gdDen), GD_MAX);
  let displacedUV = clamp(uv + (field.grad * (-0.3) + whip) * refractionStrength * schlieren * gdScale, vec2<f32>(0.0), vec2<f32>(1.0));

  var displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  // ── Idea 3: inferior mirage — where the field is hot (> 0.6) the image is
  // blended with a tap mirrored vertically about the hottest source's centre,
  // weighted by heat², like the inverted sky-pool over hot asphalt.
  let mirrorUV = clamp(vec2<f32>(displacedUV.x, 2.0 * field.center.y - displacedUV.y), vec2<f32>(0.0), vec2<f32>(1.0));
  let mirage = textureSampleLevel(readTexture, u_sampler, mirrorUV, 0.0);
  let mirageW = smoothstep(0.6, 0.9, heat) * min(heat * heat, 1.0) * 0.8;
  displaced = mix(displaced, mirage, mirageW);

  let histCoord = vec2<i32>(clamp(uv - advect, vec2<f32>(0.0), vec2<f32>(0.999)) * dims);
  let hist = safeRGB(textureLoad(dataTextureC, histCoord, 0).rgb);

  // ── Idea 5: Planck-cooling afterglow (native) ───────────────────────
  // A heated spot cools through the blackbody sequence. Keep a per-pixel heat memory
  // (A.a = 13 + memory, exact C load at this pixel, no advection) that decays at a rate keyed to
  // Cooling, and read the trail's colour off the SAME blackbody ramp at the decayed temperature:
  // white → yellow → orange → red → dark falls out of the ramp, no tint hack. mem is the max of
  // the live field and the decayed memory, so it is bounded by CA_MAX and never feeds above it.
  let memTexel = textureLoad(dataTextureC, coord, 0).a;
  let memValid = select(0.0, 1.0, memTexel > CA_BASE - 0.5 && memTexel < CA_BASE + 2.5);
  let memPrev = clamp(memTexel - CA_BASE, 0.0, CA_MAX) * memValid;
  let memDecay = exp(-cooling * CA_RATE / 60.0);
  let mem = max(min(field.heat, CA_MAX), max(memPrev * memDecay - CA_FLOOR, 0.0));
  // FIX: depth is the displaced depth lifted by the heat.
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r + heat * 0.05, 0.0, 1.0);

  let spectral = blackbodyRGB(temperature);
  var thermalGlow = spectral * smoothstep(0.06, 0.65, field.heat) * glowGain * (0.35 + 0.65 * field.pulse + 0.4 * bass) * (1.0 + 0.15 * bands * min(heat, 1.0));
  // Idea 5 (cont.): the cooled trail glows from the decayed temperature; max keeps the live ember as is.
  // Only evaluated where the memory clears the glow threshold (a coherent region, most pixels skip it).
  if (mem > CA_LO) {
    let trailGlow = blackbodyRGB(300.0 + mem * 6000.0) * smoothstep(CA_LO, CA_HI, mem) * glowGain * CA_GAIN * (0.35 + 0.65 * min(mem, 1.0));
    thermalGlow = max(thermalGlow, trailGlow * CA_ON);
  }
  let fogGlow = blackbodyRGB(temperature * 0.55 + 900.0) * field.heat * (0.03 + 0.07 * mids + mids * 0.04);
  var hdr = mix(displaced.rgb + thermalGlow + fogGlow, hist, 0.18);
  hdr = hdr + spectral * length(whip) * (0.12 + treble * 0.08);
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * 1.18;
  hdr = max(hdr, vec3<f32>(0.0));
  let alpha = clamp(displaced.a * 0.4 + max(field.heat, mem * CA_ON) * 0.55 + field.pulse * 0.2, 0.08, 0.98);

  // A holds the linear pre-ACES colour (read back as history) and, in .a, 13 + the heat memory
  // that Idea 5 re-reads; ACES on display only. The semantic alpha goes to writeTexture.
  textureStore(dataTextureA, coord, vec4<f32>(hdr, CA_BASE + mem));
  let rgb = acesToneMap(hdr * 1.05);
  textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
