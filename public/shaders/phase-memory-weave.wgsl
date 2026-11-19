// ═══════════════════════════════════════════════════════════════════
//  Phase Memory Weave v4 — Optimizer pass
//  Category: generative
//  Features: ginzburg-landau, allen-cahn, multi-scale-memory,
//            opalescent-interfaces, audio-driven, mouse-thermal,
//            mouse-driven, audio-reactive, upgraded-rgba, phase-vortex-cores,
//            memory-ghost-contours
//  Upgrades: fast-atan2, branchless-audio, early-exit, named-consts,
//            TAU-constant, pm-alpha, reduced-sqrt-calls
//  v4: gradient-keyed opalescence (mix ~0.3), latch-proof memory
//      (clamp ~1.2 + epsilon decay), expanding gaussian mouse heat
//      ring (bounded uniform ripples), shader-specific
//      slider rewiring (phase bias / memory kernel / turbulence /
//      ring forcing)
//  Upgraded: 2026-11-19
//  Ideas: phase-vortex cores with chirality tint; memory ghost contours where history disagrees with now
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
const MEM_CLAMP: f32 = 1.2;      // luma-echo-warp lesson: memory never exceeds this
const MEM_DECAY: f32 = 0.9985;   // tiny epsilon decay: buffer cannot latch
const RING_LIFETIME: f32 = 2.5;  // seconds a mouse heat ring stays active

// ── Fast atan2 (max error ~0.0015 rad, saves ~2 cycles vs builtin) ─
fn fast_atan2(y: f32, x: f32) -> f32 {
  let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
  let s = a * a;
  var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
  if (abs(y) > abs(x)) { r = 1.5707963 - r; }
  if (x < 0.0) { r = 3.1415927 - r; }
  if (y < 0.0) { r = -r; }
  return r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn thinFilmIridescence(phase: f32, d: f32) -> vec3<f32> {
  let phi = phase * TAU;
  return vec3<f32>(
    0.5 + 0.5 * cos(phi + d * 3.0),
    0.5 + 0.5 * cos(phi + d * 5.0 + 1.0),
    0.5 + 0.5 * cos(phi + d * 7.0 + 2.5)
  );
}

// ── Opalescent palette: thin-film cosine keyed on phase gradient ───
fn opalescentPalette(phase: f32, gradMag: f32, t: f32) -> vec3<f32> {
  let shift = phase * TAU + gradMag * 2.0 + t * 0.35;
  return vec3<f32>(
    0.5 + 0.5 * cos(shift),
    0.5 + 0.5 * cos(shift + 2.0943951),
    0.5 + 0.5 * cos(shift + 4.1887902)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let time = u.config.x * 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x; // Phase: fluid ↔ crystalline bias
  let p2 = u.zoom_params.y; // Memory Strength: kernel blend + lerp rate
  let p3 = u.zoom_params.z; // Turbulence: GL epsilon + chaotic jitter
  let p4 = u.zoom_params.w; // Mouse Disturbance: thermal + ring forcing

  // HEAD sprung the cursor through extraBuffer[133..138], which the host
  // re-uploads every frame, so the spring never ran; use the cursor directly.
  let mouse = rawMouse;

  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let maxCoord = dims - vec2<i32>(1);
  let cur = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), maxCoord), 0);
  let psiR = cur.r;
  let psiI = cur.g;
  let slowMem = cur.b;
  let rho2 = psiR * psiR + psiI * psiI;
  let rho = sqrt(rho2);
  let theta = fast_atan2(psiI, psiR);

  // Neighbor samples for laplacian + curvature
  let rx = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(1, 0), vec2<i32>(0), maxCoord), 0);
  let lx = textureLoad(dataTextureC, clamp(pixel - vec2<i32>(1, 0), vec2<i32>(0), maxCoord), 0);
  let uy = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0);
  let dy = textureLoad(dataTextureC, clamp(pixel - vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0);

  let lapR = rx.r + lx.r + uy.r + dy.r - 4.0 * psiR;
  let lapI = rx.g + lx.g + uy.g + dy.g - 4.0 * psiI;

  // Phase gradient magnitude (drives opalescent interface shimmer)
  let gradR = vec2<f32>(rx.r - lx.r, uy.r - dy.r);
  let gradI = vec2<f32>(rx.g - lx.g, uy.g - dy.g);
  let gradMag = sqrt(dot(gradR, gradR) + dot(gradI, gradI)) * 0.5;

  // Bounded aspect-correct thermal rings from the engine click queue.
  let ringSpeed = 0.20 + p4 * 0.45;        // p4: ring expansion rate
  let ringWidth = 0.018 + p4 * 0.03;       // p4: gaussian ring width
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  var ringForcing = 0.0;
  var ringActivity = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let ringAge = u.config.x - ripple.z; // ripple.z is in raw seconds (HEAD compared against time*0.5: rings never fired)
    if (ringAge < 0.0 || ringAge > RING_LIFETIME) { continue; }
    let ringFade = 1.0 - ringAge / RING_LIFETIME;
    let ringDelta = (length((uv - ripple.xy) * aspectVec) - ringAge * ringSpeed) / max(ringWidth, 1e-4);
    let ringGauss = exp(-0.5 * ringDelta * ringDelta) * ringFade;
    // Per-frame nudge (applied every frame the front passes): HEAD's 0.4..1.6
    // was tuned while rings were dead and floods the frame to crystal once live.
    ringForcing += ringGauss * select(-1.0, 1.0, (i & 1u) == 0u) * (0.4 + p4 * 1.2) * 0.12;
    ringActivity += ringGauss;
  }

  // Ginzburg-Landau / Allen-Cahn dynamics
  // p1 (Phase) shifts the equilibrium amplitude: fluid ↔ crystalline
  let phaseBias = (p1 - 0.5) * 0.5;
  let equilibrium = 1.0 + phaseBias * 0.4;
  let epsilon  = 0.035 + p3 * 0.04;        // p3: interface energy
  let mobility = 0.15 + mids * 0.6;        // mids: grain boundary mobility
  let reaction = rho * (equilibrium * equilibrium - rho2);
  // Rescue: HEAD scaled the laplacian by epsilon*mobility (~0.005/frame),
  // so domains never coarsened past pixel scale and per-pixel jitter won:
  // the picture was white noise on seed stripes. Diffusion now runs at
  // 3*epsilon (0.105..0.225, under the 0.25 explicit-Euler limit); mids
  // mobility still drives the local reaction.
  let diffusion = epsilon * 3.0;
  let dR = lapR * diffusion / mobility - reaction * psiR;
  let dI = lapI * diffusion / mobility - reaction * psiI;

  // Memory kernel (exponential-decay blend, clamped pre-tint, latch-proof)
  let memoryBlend = clamp(mix(psiR, slowMem * MEM_DECAY, 0.6), -MEM_CLAMP, MEM_CLAMP);
  let memStrength = 0.2 + p2 * 0.7;        // p2: how strongly history pulls
  let newR = mix(psiR + dR * mobility, memoryBlend, memStrength * 0.08);
  let newI = mix(psiI + dI * mobility, theta * 0.1, memStrength * 0.03);

  // Branchless audio seeding (replaces bass>0.55 per-pixel branch)
  // (HEAD: fract(dot(uv, k) + t) is a linear ramp → diagonal seed stripes.)
  let seedValue = fract(sin(dot(uv * 37.0, vec2<f32>(12.9898, 78.233)) + time * 0.2) * 43758.5453) - 0.5;
  let initializationSeed = select(0.0, seedValue * 0.12, rho2 < 1e-7);
  let seedNoise = initializationSeed + max(bass - 0.55, 0.0) * seedValue * 0.4;

  // Turbulent jitter, gated to the fluid state (p3: chaos strength)
  let fluidGate = smoothstep(0.7, 0.3, rho);
  // Smooth (bilinear value-noise, ~1/14 frame cells) instead of per-pixel hash:
  // HEAD's jitter was white noise every frame and drowned the domains.
  let tq = uv * 14.0 + vec2<f32>(time * 0.7, -time * 0.5);
  let ti = floor(tq); let tf = fract(tq); let tw = tf * tf * (3.0 - 2.0 * tf);
  let th = vec4<f32>(
    fract(sin(dot(ti, vec2<f32>(12.9898, 78.233))) * 43758.5453),
    fract(sin(dot(ti + vec2<f32>(1.0, 0.0), vec2<f32>(12.9898, 78.233))) * 43758.5453),
    fract(sin(dot(ti + vec2<f32>(0.0, 1.0), vec2<f32>(12.9898, 78.233))) * 43758.5453),
    fract(sin(dot(ti + vec2<f32>(1.0, 1.0), vec2<f32>(12.9898, 78.233))) * 43758.5453));
  let turbSeed = mix(mix(th.x, th.y, tw.x), mix(th.z, th.w, tw.x), tw.y) - 0.5;
  let turbulence = turbSeed * p3 * 0.3 * fluidGate;

  // Capillary waves + mouse thermal injection (branchless select)
  let capillary = sin(uv.x * 30.0 + time * 4.0)
                * cos(uv.y * 24.0 - time * 3.5)
                * treble * 0.06;
  let mouseDist = length(uv - mouse);
  let thermal = smoothstep(0.15, 0.0, mouseDist) * mouseDown * (1.0 + p4 * 2.0);
  let thermalEffect = thermal * sin(time * 0.7) * 0.75;

  let finalR = clamp(newR + seedNoise + capillary + turbulence
                   + thermalEffect + ringForcing, -1.2, 1.2);
  let finalI = newI + capillary * 0.5;
  let finalRho = sqrt(finalR * finalR + finalI * finalI);
  let finalTheta = fast_atan2(finalI, finalR);

  // Curvature via neighbor magnitudes (4 sqrts kept for accuracy)
  let rhoRx = sqrt(rx.r * rx.r + rx.g * rx.g);
  let rhoLx = sqrt(lx.r * lx.r + lx.g * lx.g);
  let rhoUy = sqrt(uy.r * uy.r + uy.g * uy.g);
  let rhoDy = sqrt(dy.r * dy.r + dy.g * dy.g);
  let curvature = abs((rhoRx + rhoLx + rhoUy + rhoDy) - 4.0 * finalRho);

  // Multi-scale memory accumulation: epsilon decay + clamp (no latch)
  let memLerp = 0.05 + p2 * 0.12;          // p2: memory write rate
  let newSlow = clamp(mix(slowMem * MEM_DECAY, finalR, memLerp), -MEM_CLAMP, MEM_CLAMP);
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;

  // ── Early exit for quiescent background pixels ─────────────────
  if (finalRho < 0.03 && curvature < 0.02) {
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalR, finalI, newSlow, ringActivity));
    textureStore(writeTexture, gid.xy, vec4<f32>(acesToneMap(source.rgb * 0.08), source.a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(sourceDepth, 0.0, 0.0, 0.0));
    return;
  }

  // State writeback for slot chaining
  textureStore(dataTextureA, gid.xy, vec4<f32>(finalR, finalI, newSlow, clamp(finalRho + curvature + ringActivity, 0.0, 1.0)));

  // Opalescent thin-film interference + subsurface
  let irid = thinFilmIridescence(finalTheta, curvature * 5.0)
           * smoothstep(0.1, 0.4, curvature) * 0.8;
  let fluidMask  = smoothstep(0.5 + phaseBias * 0.3, 0.2 + phaseBias * 0.3, finalRho);
  let crystalMask = smoothstep(0.3 + phaseBias * 0.3, 0.7 + phaseBias * 0.3, finalRho);
  let caustic = pow(sin(finalTheta * 8.0 + time) * 0.5 + 0.5, 3.0) * fluidMask;
  let subsurface = crystalMask * vec3<f32>(0.85, 0.82, 0.75) * (0.6 + finalRho * 0.5);

  let fluidCol  = vec3<f32>(0.15, 0.35, 0.65) * (0.5 + caustic * 0.8);
  let crystalCol = vec3<f32>(0.92, 0.88, 0.72) * (0.5 + finalRho * 0.6);
  var baseCol = mix(fluidCol, crystalCol, crystalMask) + irid + subsurface;

  // Opalescent interface iridescence keyed on phase-gradient magnitude
  // (mix ~0.3: domain boundaries shimmer like opal, base palette dominant)
  let opal = opalescentPalette(finalTheta, gradMag * 4.0, time);
  let opalMask = smoothstep(0.06, 0.30, gradMag) * smoothstep(0.05, 0.25, curvature);
  baseCol = mix(baseCol, opal, opalMask * 0.3);

  // Memory sheen: multi-scale history visible as a faint pre-tint glow
  let memSheen = clamp(slowMem * MEM_DECAY + finalR * 0.15, -MEM_CLAMP, MEM_CLAMP);
  baseCol += vec3<f32>(0.05, 0.07, 0.10) * memSheen * (0.4 + p2 * 0.6);

  // ── Idea 1: phase-vortex cores ─────────────────────────────────
  // GL fields carry topological defects: points where the phase winds by
  // ±2π around a loop. Sum wrapped phase steps around the 4-neighbour
  // ring; |winding|≈1 marks a core. +1 glows warm, −1 cool.
  let thR = fast_atan2(rx.g, rx.r);
  let thU = fast_atan2(uy.g, uy.r);
  let thL = fast_atan2(lx.g, lx.r);
  let thD = fast_atan2(dy.g, dy.r);
  let w1 = thU - thR; let w2 = thL - thU; let w3 = thD - thL; let w4 = thR - thD;
  let wrapd = vec4<f32>(w1, w2, w3, w4) - TAU * round(vec4<f32>(w1, w2, w3, w4) / TAU);
  let winding = (wrapd.x + wrapd.y + wrapd.z + wrapd.w) / TAU;
  let core = smoothstep(0.5, 0.9, abs(winding)) * (1.0 - smoothstep(0.0, 0.6, finalRho));
  let coreTint = select(vec3<f32>(0.35, 0.7, 1.4), vec3<f32>(1.5, 0.9, 0.35), winding > 0.0);
  baseCol += coreTint * core * (0.6 + treble * 0.5);

  // ── Idea 2: memory ghost contours ──────────────────────────────
  // Where the slow memory disagrees with the present field, etch faint
  // iso-lines of the remembered state: old domain walls linger as ghosts.
  let memDiff = abs(slowMem - finalR);
  let ghostBand = smoothstep(0.84, 0.96, abs(fract(slowMem * 4.0) - 0.5) * 2.0);
  let ghost = ghostBand * smoothstep(0.08, 0.4, memDiff) * (0.3 + p2 * 0.7);
  baseCol = mix(baseCol, vec3<f32>(0.75, 0.8, 0.95), ghost * 0.35);

  let tone = acesToneMap(baseCol * (0.7 + finalRho * 0.8));

  // Alpha encodes bloom weight (curvature = interface glow)
  let effectEnergy = clamp(finalRho * 0.9 + curvature * 0.5 + ringActivity * 0.4, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(sourceDepth, 0.0, 0.0, 0.0));
}
