// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples Coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11, 2026-11-09
//  Ideas: constructive crest doubling; orbital charge decay ring; refractive density lens (stored density slope bends the photo like a droplet); dispersive deep-water ring train behind each click front (§12.2D)
//  A packing: raw sim state (vel.xy, curl ω, density) in A; texels (0,0) = pointer spring (pos.xy, vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (corner texels; their C read is masked, invisible)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Pointer-spring state lives in two A texels (extraBuffer is re-uploaded zeroed every frame,
// so the old extraBuffer[133..138] spring never persisted and cursor motion stirred nothing).
const SENT: f32 = 0.7371;
const SPRING_OMEGA: f32 = 10.0;
const LENS_K: f32 = 0.0012;   // density-lens strength (uv displacement per unit density slope per uv)

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 { return Fp128(x, 0.0); }
fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  return Fp128(t, e - (t - s));
}
fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  return Fp128(t, e - (t - p));
}
fn fp128_val(x: Fp128) -> f32 { return x.base + x.mant; }

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact C load with the two state texels masked out (they hold spring state, not fluid).
fn cLoad(c: vec2<i32>, maxC: vec2<i32>) -> vec4<f32> {
  let cc = clamp(c, vec2<i32>(0), maxC);
  let isState = (cc.y == 0) && (cc.x < 2);
  return select(textureLoad(dataTextureC, cc, 0), vec4<f32>(0.0), isState);
}

fn load_bilinear(uv: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
  let p = uv * res - 0.5;
  let i0 = vec2<i32>(floor(p));
  let f = fract(p);
  let i1 = i0 + vec2<i32>(1, 1);
  let maxC = vec2<i32>(res) - vec2<i32>(1);
  let c00 = cLoad(i0, maxC);
  let c10 = cLoad(vec2<i32>(i1.x, i0.y), maxC);
  let c01 = cLoad(vec2<i32>(i0.x, i1.y), maxC);
  let c11 = cLoad(i1, maxC);
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

fn vortex_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (0.9 + speed * 2.5));
  return pow(max(0.0, 1.0 - abs(uv.x - head) * 12.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let speed = u.zoom_params.x * 5.0 + 1.0;
  let viscosity = mix(0.92, 0.99, u.zoom_params.y);
  let aberration = u.zoom_params.z * 0.05;
  let frequency = u.zoom_params.w * 50.0 + 10.0;

  // ── Pointer spring (RESCUE R1) ──────────────────────────────────
  // Critically-damped spring toward the raw cursor, state in A texels (0,0)/(1,0) read back
  // through C. Every thread integrates the same step from the same state; the two corner
  // threads persist it. Sentinel invalid (first frame / shader switch) → start on the cursor.
  let rawMouse = u.zoom_config.yz;
  let maxC = vec2<i32>(resolution) - vec2<i32>(1);
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  let sdt = clamp(fract(time - st1.x), 0.001, 0.05);   // fract(time) is stored: A can be rgba16float
  var springPos = select(rawMouse, st0.xy, stateOk);
  var springVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  let sAccel = (rawMouse - springPos) * (SPRING_OMEGA * SPRING_OMEGA) - springVel * (2.0 * SPRING_OMEGA);
  springVel += sAccel * sdt;
  springPos += springVel * sdt;
  // f16 rest-snap: once within 0.004 uv of the cursor and slow, a spring stored in rgba16float stalls
  // ~2e-3 short with a ~0.01 residual velocity that never decays (vel*dt < half an f16 ULP). Settle
  // exactly on the cursor instead, so a resting cursor stops stirring the fluid on every tier.
  let settled = all(abs(rawMouse - springPos) < vec2<f32>(0.004)) && length(springVel) < 0.06;
  springPos = select(springPos, rawMouse, settled);
  springVel = select(springVel, vec2<f32>(0.0), settled);
  let mousePos = springPos;
  // dead-band: f16 rounding of the stored spring leaves ~1e-4 residual velocity at rest
  let mouseVel = springVel * smoothstep(0.004, 0.02, length(springVel));
  let mouseSpeed = length(mouseVel);

  let px = vec2<f32>(1.0) / resolution;
  let prevState = cLoad(pixel, maxC);
  let prevVel = prevState.xy;
  let prevDens = prevState.w;

  let backUV = clamp(uv - prevVel * px * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = load_bilinear(backUV, resolution);
  var vel = advected.xy * viscosity;
  var dens = advected.w * viscosity;

  // Four axial neighbours of the previous fluid state: they give the true curl stored in A.z
  // (RESCUE R2: HEAD stored vel.x − vel.y there) and the density slope the lens below uses.
  let cR = cLoad(pixel + vec2<i32>(1, 0), maxC);
  let cL = cLoad(pixel + vec2<i32>(-1, 0), maxC);
  let cD = cLoad(pixel + vec2<i32>(0, 1), maxC);
  let cU = cLoad(pixel + vec2<i32>(0, -1), maxC);
  let curlNow = 0.5 * ((cR.y - cL.y) - (cD.x - cU.x));
  // Slope of the stored density per uv (previous frame), resolution independent.
  let densSlope = 0.5 * vec2<f32>(cR.w - cL.w, cD.w - cU.w) * resolution.y;

  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mDist = length(toMouse);
  let mouseRadius = mix(0.03f, 0.15f, 0.5f) * select(1.0f, 1.25f, held);
  let influence = smoothstep(mouseRadius, 0.0, mDist);
  vel = vel + mouseVel * influence * 0.5;
  vel = vel + vec2<f32>(-mouseVel.y, mouseVel.x) * influence * mouseSpeed;

  var crestPhaseSum = 0.0;
  var crestAmpSum = 0.0;
  var orbitHalo = 0.0;
  var trainDisp = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;

      // Idea 1 — constructive crest doubling: in-phase ripple overlap brightens crest
      let ringRadius = elapsed * 0.32;
      let ringBand = exp(-pow((rDist - ringRadius) * 14.0, 2.0));
      let ripplePhase = sin(fp128_val(fp128_mul(fp128(ringRadius), fp128(frequency))) - elapsed * speed * 2.0);
      crestPhaseSum = crestPhaseSum + ripplePhase * ringBand;
      crestAmpSum = crestAmpSum + ringBand;

      // Idea 4 — dispersive ring train (§12.2D deep-water dispersion): a point impulse on deep
      // water leaves a chirped train behind its front, phase φ = g·t²/(4r), local wavenumber
      // k = g·t²/(4r²). g is chosen so k equals the Frequency slider at the front (r = 0.32 t);
      // the wavelength then shrinks toward the origin. Inside radius 0.55·front the phase is
      // frozen so k stays below ~3.3× Frequency (no aliasing). The train refracts the image
      // along the ring normal (cos φ = slope) and joins the crest sums.
      let behind = ringRadius - rDist;
      let trainEnv = smoothstep(0.0, 0.03, behind) * exp(-behind * 7.0) * exp(-elapsed * 0.9)
                   * (1.0 - smoothstep(1.5, 2.0, elapsed));
      let trainPhase = 0.1024 * frequency * elapsed * elapsed / max(max(rDist, ringRadius * 0.55), 0.02);
      crestPhaseSum = crestPhaseSum + sin(trainPhase) * trainEnv * 0.8;
      crestAmpSum = crestAmpSum + trainEnv * 0.8;
      trainDisp = trainDisp + outward * cos(trainPhase) * trainEnv * 0.010 * (1.0 + bass * 0.4);

      // Idea 2 — orbital charge decay ring: click charges leave fading EM orbit halo
      let orbitAngle = elapsed * (2.2 + bass) + f32(i) * 1.047;
      let orbitPos = ripple.xy + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * ringRadius * 0.85;
      let orbitDist = length((uv - orbitPos) * vec2<f32>(aspect, 1.0));
      orbitHalo = orbitHalo + exp(-orbitDist * orbitDist * 900.0) * exp(-elapsed * 1.1) * ringBand;
    }
  }
  let inPhase = smoothstep(0.55, 0.95, abs(crestPhaseSum) / max(crestAmpSum, 0.001));
  let crestDouble = inPhase * crestAmpSum * (1.0 + mids * 0.35);

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  vel = vel * smoothstep(0.05, 0.1, edgeDist);
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uvCorrected, mouseCorrected);
  let quantizedDist = floor(dist * 20.0) / 20.0;
  let wavePhase = fp128_sum(fp128_mul(fp128(quantizedDist), fp128(frequency)), fp128_mul(fp128(-time), fp128(speed)));
  let wave = sin(fp128_val(wavePhase));
  let strength = 1.0 / (dist * 5.0 + 0.5);
  let packet = vortex_packet(uv, time, speed);
  let displacement = vec2<f32>(wave) * strength * 0.01 + vel * 0.05 + vec2<f32>(packet * 0.008, 0.0) + trainDisp
    // ── Idea 3: refractive density lens — the density bump the cursor and clicks raise is the
    // fluid's surface; its slope bends the photo like a convex droplet (samples pulled toward
    // the peak, so the wake magnifies what is under it). Zero density slope = zero change.
    + densSlope * LENS_K * (1.0 + bass * 0.3);

  var displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let effAberration = aberration * (1.0 + dens) * (1.0 + treble * 0.2);
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(effAberration, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(effAberration, 0.0), 0.0).b;

  var color = vec3<f32>(r, g, b);
  color = color * mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.3);
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  color = color + vec3<f32>(0.9, 0.95, 1.0) * pow(specNoise, 20.0) * influence * dens * 3.0;
  color = color + vec3<f32>(0.2, 0.9, 1.0) * packet * (0.15 + mids * 0.2);
  color = color + vec3<f32>(0.95, 1.0, 0.85) * crestDouble * 0.35;
  color = color + vec3<f32>(0.35, 0.75, 1.0) * orbitHalo * (0.4 + treble * 0.25);
  color = acesToneMap(color);

  let alpha = clamp(dens * 0.4 + length(vel) * 0.5 + crestDouble * 0.2 + orbitHalo * 0.15 + packet * 0.15 + bass * 0.06, 0.06, 0.96);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // A: raw sim state (vel.xy, true curl, density) — texels (0,0)/(1,0) carry the pointer spring.
  var aOut = vec4<f32>(vel, curlNow, dens);
  if (pixel.y == 0 && pixel.x == 0) { aOut = vec4<f32>(springPos, springVel); }
  if (pixel.y == 0 && pixel.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
  textureStore(dataTextureA, pixel, aOut);
  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
