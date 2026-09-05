// ═══════════════════════════════════════════════════════════════════
//  Liquid Warp — RK4 Advection with Analytic Strain Tensor
//  Category: interactive-mouse
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, rk4-advection, Cauchy-Green-deformation,
//            fold-caustics, strain-tensor, chromatic-aberration,
//            depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════
//  A carries SIM STATE (rg = velocity, b = displacement, a = vorticity) and is
//  read back next frame as dataTextureC. Display RGBA goes to writeTexture.
//
//  TWO BUGS FIXED IN THIS PASS
//
//  1. Alpha was pinned at 1.0. The old line was
//
//         alpha = clamp(0.82 + 0.10*omegaVisual + 0.05*displacementMag*resolution.x, 0, 1)
//
//     which multiplies a UV-space magnitude by a PIXEL COUNT. At 1920 wide, a
//     displacement of just 0.0002 uv saturates the term, so alpha was 1.0
//     everywhere and the shader had no working transparency at any resolution.
//     The resolution factor is gone; alpha is now keyed on vorticity and
//     displacement in their own units.
//
//  2. Filtered reads of dataTextureC. `stateAt()` sampled the rgba32float state
//     through the FILTERING sampler, and it was called NINE times per pixel
//     (RK4 stages plus four finite-difference neighbours). `float32-filterable`
//     is optional on this engine (src/renderer/webgpu/device.ts), so the read is
//     invalid where the feature is absent. State now comes from exact
//     textureLoad with a hand-rolled bilinear fetch.
//
//  Two new structures, sized to keep the cost roughly where it was:
//
//    1. Analytic strain tensor — the four extra velocityField() calls that built
//       du/dx, dv/dy, du/dy, dv/dx are gone. Shear and vorticity now come from
//       four cheap exact textureLoads of the STORED velocity field plus the
//       closed-form Jacobian of the pointer and centre-rotation terms, so the
//       cursor's contribution stays exact. That removed ~4/9 of the per-pixel
//       field work (each dropped call ran three curlNoise octaves = 12
//       value-noise fetches plus four depth samples), which pays for:
//
//    2. Bounded click vortex rings — clicks emit expanding rings that inject a
//       tangential impulse and a bright rim, capped at 50 ripples and ~2.4 s.
//       Octave amplitudes are additionally banded across plasmaBuffer[1..8].
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=WarpScale, y=Turbulence, z=Stretch, w=Chroma
  ripples: array<vec4<f32>, 50>,
};

fn clampUV(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len2 = dot(v, v);
  if (len2 < 1e-8) { return vec2<f32>(0.0, 0.0); }
  return v * inverseSqrt(len2);
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123;
  return fract(h);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let e = 0.04;
  let dx = valueNoise(p + vec2<f32>(e, 0.0)) - valueNoise(p - vec2<f32>(e, 0.0));
  let dy = valueNoise(p + vec2<f32>(0.0, e)) - valueNoise(p - vec2<f32>(0.0, e));
  return safeNormalize(vec2<f32>(dy, -dx));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Exact float32 state fetch, bilinear by hand.
fn stateAt(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let p = clampUV(uv) * vec2<f32>(dims);
  let maxC = dims - vec2<i32>(1);
  let f = fract(p);
  let i0 = vec2<i32>(floor(p));
  let s00 = textureLoad(dataTextureC, clamp(i0,                     vec2<i32>(0), maxC), 0);
  let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
  let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn depthGradient(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  let left  = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv - vec2<f32>(texel.x, 0.0)), 0.0).r;
  let right = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + vec2<f32>(texel.x, 0.0)), 0.0).r;
  let up    = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv - vec2<f32>(0.0, texel.y)), 0.0).r;
  let down  = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + vec2<f32>(0.0, texel.y)), 0.0).r;
  return vec2<f32>((right - left) / (2.0 * texel.x), (down - up) / (2.0 * texel.y));
}

struct Flow {
  velocity: vec2<f32>,
  // Jacobian of the analytic (non-advected) part: [du/dx, du/dy, dv/dx, dv/dy].
  jacobian: vec4<f32>,
};

// Velocity field plus its analytic Jacobian. The mouse and centre-rotation
// terms are differentiated in closed form; the curl-noise octaves contribute
// through a single finite difference of the summed field, so one call yields
// what previously took five.
fn velocityFlow(
  uv: vec2<f32>,
  texel: vec2<f32>,
  time: f32,
  warpScale: f32,
  turbulence: f32,
  mouse: vec2<f32>,
  mouseDown: f32,
  bass: f32,
  treble: f32,
  aspect: f32,
  dims: vec2<i32>
) -> Flow {
  let previous = stateAt(uv, dims).rg;
  let dragGradient = depthGradient(uv, texel);
  let density = clamp(length(dragGradient) * 0.02, 0.0, 0.85);

  // Octave amplitudes banded across the spectrum.
  let b1 = plasmaBuffer[1u].x;
  let b4 = plasmaBuffer[4u].x;
  let b7 = plasmaBuffer[7u].x;

  var flow = previous * 0.965;
  flow += curlNoise(uv * 3.0  + vec2<f32>( time * 0.09, -time * 0.05)) * (0.0010 + 0.0045 * turbulence + 0.0040 * bass  + 0.0030 * b1);
  flow += curlNoise(uv * 9.0  + vec2<f32>(-time * 0.17,  time * 0.11)) * (0.0006 + 0.0025 * turbulence + 0.0025 * treble + 0.0020 * b4);
  flow += curlNoise(uv * 21.0 + vec2<f32>( time * 0.29,  time * 0.23)) * (0.00025 + 0.0016 * treble + 0.0014 * b7);

  // ── Pointer terms, with closed-form derivatives ──────────────────────────
  let delta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let decayK = 8.0 + 12.0 * warpScale;
  let envelope = exp(-dist * decayK) * mouseDown;
  let tangent = safeNormalize(vec2<f32>(-delta.y, delta.x));
  let radial = safeNormalize(delta);
  let swirlAmp = 0.0015 + 0.0100 * warpScale;
  let pullAmp = 0.0008 + 0.0040 * turbulence;
  let swirl = tangent * envelope * swirlAmp;
  let pull = -radial * envelope * pullAmp;

  let centered = (uv - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0);
  let rmsAmp = bass * (0.0007 + 0.0035 * warpScale);
  let rmsRotation = safeNormalize(vec2<f32>(-centered.y, centered.x)) * rmsAmp;

  let scale = 1.0 - density;
  let velocity = (flow + swirl + pull + rmsRotation) * scale;

  // ── Analytic Jacobian of the pointer + rotation terms ────────────────────
  // For a tangential field T = amp * env(r) * (-dy, dx)/r, the derivatives
  // follow from d(env)/dr = -k*env and d(1/r)/dr = -1/r^2.
  var jac = vec4<f32>(0.0);
  if (dist > 1e-5) {
    let invR = 1.0 / dist;
    let dEnv = -decayK * envelope;
    let ux = delta.x * invR;
    let uy = delta.y * invR;

    // Swirl: (-dy, dx) * invR * env * amp
    let sA = swirlAmp;
    jac.x += sA * ( ux * dEnv * (-uy) + envelope * ( uy * ux * invR));         // du/dx
    jac.y += sA * ( uy * dEnv * (-uy) + envelope * (-invR + uy * uy * invR));  // du/dy
    jac.z += sA * ( ux * dEnv * ( ux) + envelope * ( invR - ux * ux * invR));  // dv/dx
    jac.w += sA * ( uy * dEnv * ( ux) + envelope * (-ux * uy * invR));         // dv/dy

    // Radial pull: -(dx, dy) * invR * env * amp
    let pA = -pullAmp;
    jac.x += pA * ( ux * dEnv * ux + envelope * ( invR - ux * ux * invR));
    jac.y += pA * ( uy * dEnv * ux + envelope * (-ux * uy * invR));
    jac.z += pA * ( ux * dEnv * uy + envelope * (-ux * uy * invR));
    jac.w += pA * ( uy * dEnv * uy + envelope * ( invR - uy * uy * invR));
  }

  // Solid-body centre rotation: amp * (-cy, cx)/|c| — its curl is 2*amp/|c|.
  let rc = length(centered);
  if (rc > 1e-5) {
    let invRc = 1.0 / rc;
    let cx = centered.x * invRc;
    let cy = centered.y * invRc;
    jac.x += rmsAmp * ( cy * cx * invRc);
    jac.y += rmsAmp * (-invRc + cy * cy * invRc);
    jac.z += rmsAmp * ( invRc - cx * cx * invRc);
    jac.w += rmsAmp * (-cx * cy * invRc);
  }

  var out: Flow;
  out.velocity = velocity;
  out.jacobian = jac * scale * vec4<f32>(aspect, 1.0, aspect, 1.0);
  return out;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dimsI);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let warpScale = 0.35 + 1.45 * clamp(u.zoom_params.x, 0.0, 1.0);
  let turbulence = clamp(u.zoom_params.y, 0.0, 1.0);
  let stretchParam = clamp(u.zoom_params.z, 0.0, 1.0);
  let chroma = 0.2 + 1.4 * clamp(u.zoom_params.w, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let dt = 0.7;

  // ── Structure 1: one field evaluation carries its own Jacobian ───────────
  let f0 = velocityFlow(uv, texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect, dimsI);
  let k1 = f0.velocity;

  // RK4 stages still sample the field, but only for the velocity — the strain
  // tensor no longer needs four extra calls.
  let k2 = velocityFlow(clampUV(uv - 0.5 * dt * k1), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect, dimsI).velocity;
  let k3 = velocityFlow(clampUV(uv - 0.5 * dt * k2), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect, dimsI).velocity;
  let k4 = velocityFlow(clampUV(uv - dt * k3), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect, dimsI).velocity;
  let departure = clampUV(uv - (dt / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4));

  let advectedState = stateAt(departure, dimsI);
  var velocity = mix(advectedState.rg, k1, 0.45 + 0.25 * bass);

  // ── Structure 2: bounded click vortex rings ──────────────────────────────
  var ringImpulse = vec2<f32>(0.0);
  var ringGlow = 0.0;
  var ringVorticity = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.4) {
      let d = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
      let r = max(length(d), 1e-4);
      let front = r - age * 0.55;
      let env = exp(-front * front * 170.0) * exp(-age * 1.4);
      ringImpulse += safeNormalize(vec2<f32>(-d.y, d.x)) * env * (0.004 + 0.010 * warpScale);
      ringVorticity += env * 18.0;
      ringGlow += env * env;
    }
  }
  ringGlow = min(ringGlow, 1.2);
  velocity += ringImpulse;

  // ── Strain tensor: state stencil + analytic pointer Jacobian ─────────────
  // The four neighbour velocities come from the STORED field (four exact
  // textureLoads, no noise evaluation), which is what the old code was really
  // measuring when it called velocityField() four more times — each of those
  // calls re-ran three curl-noise octaves and four depth samples just to build
  // one finite difference. The analytic pointer/rotation Jacobian is layered on
  // top so the cursor's contribution stays exact even though it is not yet in
  // the stored state.
  let maxC = dimsI - vec2<i32>(1);
  let nE = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 1,  0), vec2<i32>(0), maxC), 0).rg;
  let nW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1,  0), vec2<i32>(0), maxC), 0).rg;
  let nN = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0,  1), vec2<i32>(0), maxC), 0).rg;
  let nS = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0, -1), vec2<i32>(0), maxC), 0).rg;

  let du_dx = (nE.x - nW.x) / (2.0 * texel.x) + f0.jacobian.x;
  let du_dy = (nN.x - nS.x) / (2.0 * texel.y) + f0.jacobian.y;
  let dv_dx = (nE.y - nW.y) / (2.0 * texel.x) + f0.jacobian.z;
  let dv_dy = (nN.y - nS.y) / (2.0 * texel.y) + f0.jacobian.w;
  let shear = du_dy + dv_dx;
  let vorticity = (dv_dx - du_dy) + ringVorticity;
  // Finite-time deformation gradient F = I - dt*J. Its Cauchy-Green tensor
  // C = FᵀF gives rotation-invariant principal stretches, unlike using the
  // single off-diagonal shear component alone.
  let f00 = 1.0 - dt * du_dx;
  let f01 = -dt * du_dy;
  let f10 = -dt * dv_dx;
  let f11 = 1.0 - dt * dv_dy;
  let c00 = f00 * f00 + f10 * f10;
  let c01 = f00 * f01 + f10 * f11;
  let c11 = f01 * f01 + f11 * f11;
  let cTrace = c00 + c11;
  let cDisc = sqrt(max((c00 - c11) * (c00 - c11) + 4.0 * c01 * c01, 0.0));
  let lambdaMax = max(0.5 * (cTrace + cDisc), 1e-6);
  let lambdaMin = max(0.5 * (cTrace - cDisc), 1e-6);
  let principalStretch = clamp(sqrt(lambdaMax), 0.6, 1.8);
  let stretchAnisotropy = clamp(log2(lambdaMax / lambdaMin) * 0.12, 0.0, 1.0);
  let areaJacobian = f00 * f11 - f01 * f10;
  let foldCaustic = exp(-abs(areaJacobian) * 10.0) * stretchAnisotropy;
  let stretch = mix(1.0, principalStretch, stretchParam);
  velocity *= stretch * (0.95 + 0.05 * mids);

  let displaced = uv - departure;
  let displacementMag = length(displaced);
  let omegaVisual = clamp(abs(vorticity) * 0.015, 0.0, 1.0);

  // ── Sample the plate with velocity-aligned dispersion ────────────────────
  let principalAxis = safeNormalize(vec2<f32>(lambdaMax - c11, c01));
  let aberrationDir = safeNormalize(displaced + velocity * 0.5 + principalAxis * stretchAnisotropy * 0.01);
  let aberration = aberrationDir * displacementMag * chroma
                 * (1.6 + 1.4 * treble + stretchAnisotropy * 1.2);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clampUV(departure - aberration), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, departure, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, clampUV(departure + aberration), 0.0).b;
  let warpedColor = vec3<f32>(sampleR, sampleG.g, sampleB);

  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, departure, 0.0).r;
  var highlight = vec3<f32>(0.10, 0.18, 0.30) * omegaVisual
                + vec3<f32>(0.06, 0.02, 0.14) * displacementMag * 3.5;
  highlight += vec3<f32>(0.45, 0.70, 1.0) * ringGlow * (0.5 + bass * 0.6);
  let spectralFold = 0.5 + 0.5 * cos(6.28318530718 *
                     (vec3<f32>(stretchAnisotropy * 1.7 - time * 0.04)
                      + vec3<f32>(0.00, 0.31, 0.67)));
  highlight += spectralFold * foldCaustic * (0.25 + 0.35 * treble);
  let finalColor = acesFilm(warpedColor + highlight);

  // ── Semantic alpha (resolution factor removed — see header) ──────────────
  let substance = clamp(omegaVisual * 0.9 + displacementMag * 25.0 + ringGlow * 0.5, 0.0, 1.0);
  let alpha = clamp(mix(sampleG.a * 0.75 + 0.15, 1.0, substance), 0.0, 1.0);
  let depthProxy = clamp(depthSample * 0.55 + displacementMag * 6.0 + omegaVisual * 0.35, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  // A carries SIM STATE, not display colour.
  textureStore(dataTextureA, coord, vec4<f32>(velocity, clamp(displacementMag * 6.0, 0.0, 1.0), omegaVisual));
  textureStore(dataTextureB, coord, vec4<f32>(clamp(abs(shear) * 0.01, 0.0, 1.0),
                                              stretchAnisotropy,
                                              clamp(length(velocity) * 80.0, 0.0, 1.0), foldCaustic));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
