// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Swirl — Lamb-Oseen Vortex Laboratory
//  Category: distortion
//  Features: spring pointer, viscous vortex core, vortex pairing, strain
//            caustics, FFT circulation, bounded click wakes, temporal sheen
//  Upgraded: 2026-08-23
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=time, y=rippleCount, zw=resolution
  zoom_config: vec4<f32>,  // x=time, yz=mouse UV, w=held
  zoom_params: vec4<f32>,  // x=strength, y=radius, z=smoothness, w=auto rotation
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let m2 = dot(v, v);
  if (m2 < 1e-10) { return vec2<f32>(0.0); }
  return v * inverseSqrt(m2);
}

fn rotate2(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Lamb-Oseen: finite angular velocity at the eye, 1/r circulation outside.
fn oseenVelocity(delta: vec2<f32>, circulation: f32, coreRadius: f32) -> vec2<f32> {
  let r2 = max(dot(delta, delta), 1e-8);
  let core2 = max(coreRadius * coreRadius, 1e-6);
  let profile = (1.0 - exp(-r2 / core2)) / sqrt(r2);
  return safeNormalize(vec2<f32>(-delta.y, delta.x)) * circulation * profile;
}

fn flowField(p: vec2<f32>, center: vec2<f32>, time: f32, strength: f32,
             radius: f32, rotation: f32, lowBand: f32, highBand: f32) -> vec2<f32> {
  var velocity = oseenVelocity(p - center, strength * (0.75 + lowBand), radius);
  let orbit = radius * (1.6 + 0.35 * sin(time * 0.31));
  let axis = rotate2(vec2<f32>(orbit, 0.0), time * rotation);
  velocity += oseenVelocity(p - center - axis, -strength * (0.32 + 0.25 * highBand), radius * 0.55);
  velocity += oseenVelocity(p - center + axis,  strength * (0.28 + 0.22 * highBand), radius * 0.48);
  return velocity;
}

fn historyBilinear(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let maxC = dims - vec2<i32>(1);
  let base = vec2<i32>(floor(p));
  let f = fract(p);
  let s00 = textureLoad(dataTextureC, clamp(base, vec2<i32>(0), maxC), 0);
  let s10 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
  let s01 = textureLoad(dataTextureC, clamp(base + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
  let s11 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<f32>(dimsI);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let texel = 1.0 / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let p = (uv - 0.5) * aspectVec;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let lowBand = 0.5 * (plasmaBuffer[1u].x + plasmaBuffer[2u].x);
  let highBand = 0.5 * (plasmaBuffer[7u].x + plasmaBuffer[8u].x);

  let strength = mix(0.002, 0.018, clamp(u.zoom_params.x, 0.0, 1.0));
  let radius = mix(0.035, 0.22, clamp(u.zoom_params.y, 0.0, 1.0));
  let smoothness = mix(0.45, 1.8, clamp(u.zoom_params.z, 0.0, 1.0));
  let autoRotation = mix(-0.35, 1.15, clamp(u.zoom_params.w, 0.0, 1.0));

  let rawMouse = u.zoom_config.yz;
  if (gid.x == 0u && gid.y == 0u) {
    var centerUV = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (dot(centerUV, centerUV) < 1e-8) { centerUV = rawMouse; }
    var velocityUV = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let stiffness = mix(38.0, 92.0, smoothness / 1.8);
    velocityUV += ((rawMouse - centerUV) * stiffness - velocityUV * 14.0) * 0.016;
    velocityUV = clamp(velocityUV, vec2<f32>(-2.5), vec2<f32>(2.5));
    centerUV += velocityUV * 0.016;
    extraBuffer[133] = centerUV.x; extraBuffer[134] = centerUV.y;
    extraBuffer[135] = velocityUV.x; extraBuffer[136] = velocityUV.y;
  }
  let center = (vec2<f32>(extraBuffer[133], extraBuffer[134]) - 0.5) * aspectVec;
  let pointerVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]) * aspectVec;
  let held = step(0.5, u.zoom_config.w);

  // Midpoint integration retains tight orbital detail better than a single
  // Euler offset when the strength slider approaches its upper range.
  let rotationRate = autoRotation * (0.35 + 0.65 * mids);
  let flow0 = flowField(p, center, time, strength * (1.0 + held * 0.45), radius,
                        rotationRate, lowBand, highBand);
  let midP = p - 0.5 * flow0;
  var flow = flowField(midP, center, time, strength * (1.0 + held * 0.45), radius,
                       rotationRate, lowBand, highBand);
  flow += pointerVelocity * exp(-dot(p - center, p - center) / max(radius * radius, 1e-5)) * 0.006 * held;

  var ringGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.3) {
      let rippleP = (rp.xy - 0.5) * aspectVec;
      let delta = p - rippleP;
      let r = max(length(delta), 1e-4);
      let front = r - age * 0.52;
      let envelope = exp(-front * front * 190.0) * exp(-age * 1.35);
      flow += safeNormalize(vec2<f32>(-delta.y, delta.x)) * envelope * strength * 1.6;
      ringGlow += envelope * envelope;
    }
  }
  ringGlow = min(ringGlow, 1.25);

  // Velocity-gradient tensor from the analytic vortex field. These four calls
  // are cheap closed-form evaluations and expose shear/vorticity for shading.
  let ex = vec2<f32>(texel.x * aspect, 0.0);
  let ey = vec2<f32>(0.0, texel.y);
  let eFlow = flowField(p + ex, center, time, strength, radius, rotationRate, lowBand, highBand);
  let wFlow = flowField(p - ex, center, time, strength, radius, rotationRate, lowBand, highBand);
  let nFlow = flowField(p + ey, center, time, strength, radius, rotationRate, lowBand, highBand);
  let sFlow = flowField(p - ey, center, time, strength, radius, rotationRate, lowBand, highBand);
  let duDx = (eFlow.x - wFlow.x) / max(2.0 * ex.x, 1e-6);
  let dvDx = (eFlow.y - wFlow.y) / max(2.0 * ex.x, 1e-6);
  let duDy = (nFlow.x - sFlow.x) / max(2.0 * ey.y, 1e-6);
  let dvDy = (nFlow.y - sFlow.y) / max(2.0 * ey.y, 1e-6);
  let vorticity = dvDx - duDy;
  let shear = sqrt((duDx - dvDy) * (duDx - dvDy) + (duDy + dvDx) * (duDy + dvDx));
  let caustic = smoothstep(0.02, 0.55, shear * radius);

  let departure = clamp(uv - flow / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let direction = safeNormalize(flow / aspectVec);
  let dispersion = direction * (0.0007 + treble * 0.0035) * clamp(abs(vorticity) * radius, 0.0, 1.5);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(departure + dispersion, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, departure, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(departure - dispersion, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  var color = vec3<f32>(sampleR, sampleG.g, sampleB);

  let history = historyBilinear(departure * dims, dimsI);
  let persistence = clamp(0.06 + smoothness * 0.08 + caustic * 0.12, 0.0, 0.28);
  color = mix(color, history.rgb, persistence * history.a);
  let spectral = 0.5 + 0.5 * cos(TAU * (vec3<f32>(abs(vorticity) * 0.08 - time * 0.06) + vec3<f32>(0.00, 0.33, 0.67)));
  color += spectral * caustic * (0.08 + 0.16 * highBand);
  color += vec3<f32>(0.55, 0.78, 1.0) * ringGlow * (0.16 + bass * 0.28);
  color = acesFilm(color);

  let substance = clamp(length(flow) * 22.0 + caustic * 0.45 + ringGlow * 0.4, 0.0, 1.0);
  let alpha = clamp(mix(sampleG.a * 0.7 + 0.12, 1.0, substance), 0.0, 1.0);
  let outColor = vec4<f32>(color, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, departure, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
