// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Tensor Vortex — Spectral Flow and Deformation Invariants
//  Category: liquid-effects
//  Features: analytic divergence-free spectrum, velocity-gradient tensor,
//            Q criterion, principal strain, Rankine pointer, FFT energy cascade,
//            temporal metal memory, ACES, semantic transmission
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
  zoom_params: vec4<f32>,  // x=flow scale, y=surface tension, z=specular, w=transmission
  ripples: array<vec4<f32>, 50>,
};

struct TensorFlow {
  velocity: vec2<f32>,
  jacobian: vec4<f32>, // du/dx, du/dy, dv/dx, dv/dy
};

const TAU: f32 = 6.28318530717958647692;

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let m2 = dot(v, v);
  if (m2 < 1e-10) { return vec2<f32>(0.0); }
  return v * inverseSqrt(m2);
}

// Each term is the curl of an analytic stream function. Its divergence is
// identically zero and its full Jacobian is accumulated without finite noise
// differences, retaining precision at high resolution and large time values.
fn spectralTensorFlow(p: vec2<f32>, time: f32, scale: f32) -> TensorFlow {
  var velocity = vec2<f32>(0.0);
  var jacobian = vec4<f32>(0.0);
  for (var i = 0u; i < 6u; i = i + 1u) {
    let fi = f32(i);
    let angle = fi * 2.39996322972865332 + 0.37;
    let frequency = scale * exp2(fi * 0.62);
    let k = vec2<f32>(cos(angle), sin(angle)) * frequency;
    let band = plasmaBuffer[i + 1u].x;
    let amplitude = (0.020 / pow(frequency, 1.32)) * (0.65 + band * 1.8);
    let phase = dot(k, p) + time * (0.24 + 0.09 * fi) * select(-1.0, 1.0, (i & 1u) == 0u);
    let s = sin(phase);
    let c = cos(phase);

    // v = (dψ/dy, -dψ/dx), ψ = A sin(k·p + phase).
    velocity += vec2<f32>(k.y, -k.x) * amplitude * c;
    jacobian += vec4<f32>(-k.y * k.x, -k.y * k.y,
                           k.x * k.x,  k.x * k.y) * amplitude * s;
  }
  var out: TensorFlow;
  out.velocity = velocity;
  out.jacobian = jacobian;
  return out;
}

fn rankineVortex(delta: vec2<f32>, core: f32, circulation: f32) -> vec2<f32> {
  let r2 = max(dot(delta, delta), 1e-9);
  let core2 = max(core * core, 1e-7);
  let profile = select(1.0 / sqrt(r2), sqrt(r2) / core2, r2 < core2);
  return safeNormalize(vec2<f32>(-delta.y, delta.x)) * circulation * profile;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn schlickFresnel(cosTheta: f32, f0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  return f0 + (1.0 - f0) * m2 * m2 * m;
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

  let flowScale = mix(1.4, 7.0, clamp(u.zoom_params.x * 0.5, 0.0, 1.0));
  let surfaceTension = clamp(u.zoom_params.y * 0.5, 0.0, 1.0);
  let specularGain = clamp(u.zoom_params.z / 3.0, 0.0, 1.0);
  let transmission = clamp(u.zoom_params.w, 0.0, 1.0);

  let mouse = (u.zoom_config.yz - 0.5) * aspectVec;
  let held = step(0.5, u.zoom_config.w);
  let base = spectralTensorFlow(p, time, flowScale);
  let pointerCore = mix(0.18, 0.055, surfaceTension);
  let pointerCirculation = held * (0.004 + 0.018 * (0.4 + bass));
  let pointerFlow = rankineVortex(p - mouse, pointerCore, pointerCirculation);
  var velocity = base.velocity + pointerFlow;

  // The pointer's inexpensive analytic field is differentiated symmetrically
  // and added to the exact spectral Jacobian.
  let ex = vec2<f32>(texel.x * aspect, 0.0);
  let ey = vec2<f32>(0.0, texel.y);
  let ptrE = rankineVortex(p + ex - mouse, pointerCore, pointerCirculation);
  let ptrW = rankineVortex(p - ex - mouse, pointerCore, pointerCirculation);
  let ptrN = rankineVortex(p + ey - mouse, pointerCore, pointerCirculation);
  let ptrS = rankineVortex(p - ey - mouse, pointerCore, pointerCirculation);
  var jacobian = base.jacobian + vec4<f32>(
    (ptrE.x - ptrW.x) / max(2.0 * ex.x, 1e-6),
    (ptrN.x - ptrS.x) / max(2.0 * ey.y, 1e-6),
    (ptrE.y - ptrW.y) / max(2.0 * ex.x, 1e-6),
    (ptrN.y - ptrS.y) / max(2.0 * ey.y, 1e-6));

  var ringGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.5) {
      let delta = p - (rp.xy - 0.5) * aspectVec;
      let r = max(length(delta), 1e-4);
      let front = r - age * 0.52;
      let envelope = exp(-front * front * 170.0) * exp(-age * 1.3);
      velocity += safeNormalize(vec2<f32>(-delta.y, delta.x)) * envelope * (0.008 + bass * 0.012);
      ringGlow += envelope * envelope;
    }
  }
  ringGlow = min(ringGlow, 1.2);

  let duDx = jacobian.x;
  let duDy = jacobian.y;
  let dvDx = jacobian.z;
  let dvDy = jacobian.w;
  let sxx = duDx;
  let syy = dvDy;
  let sxy = 0.5 * (duDy + dvDx);
  let vorticity = dvDx - duDy;
  let strainNorm2 = sxx * sxx + syy * syy + 2.0 * sxy * sxy;
  let rotationNorm2 = 0.5 * vorticity * vorticity;
  let qCriterion = 0.5 * (rotationNorm2 - strainNorm2);

  let strainTrace = sxx + syy;
  let strainDisc = sqrt(max((sxx - syy) * (sxx - syy) + 4.0 * sxy * sxy, 0.0));
  let lambdaMax = 0.5 * (strainTrace + strainDisc);
  let lambdaMin = 0.5 * (strainTrace - strainDisc);
  let anisotropy = abs(lambdaMax - lambdaMin);
  let principal = safeNormalize(vec2<f32>(lambdaMax - syy, sxy));

  // Surface tension suppresses the highest-strain displacement without erasing
  // its specular ridge, mimicking a cohesive metallic film.
  let cohesive = 1.0 / (1.0 + surfaceTension * anisotropy * 0.22);
  velocity *= cohesive;
  let departure = clamp(uv + velocity / aspectVec * (0.22 + 0.10 * bass), vec2<f32>(0.001), vec2<f32>(0.999));
  let normal = normalize(vec3<f32>(-(jacobian.x + jacobian.y) * 0.035,
                                    -(jacobian.z + jacobian.w) * 0.035, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let lightDir = normalize(vec3<f32>(-0.45, -0.55, 0.82));
  let halfDir = normalize(viewDir + lightDir);
  let specular = pow(max(dot(normal, halfDir), 0.0), mix(18.0, 120.0, surfaceTension))
                 * (0.18 + 1.25 * specularGain);
  let fresnel = schlickFresnel(max(normal.z, 0.0), mix(0.04, 0.72, specularGain));

  let spread = safeNormalize(principal / aspectVec) * (0.0006 + treble * 0.0032)
             * clamp(anisotropy * 0.08, 0.0, 1.5);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(departure + spread, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, departure, 0.0);
  let b = textureSampleLevel(readTexture, u_sampler, clamp(departure - spread, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let plate = vec3<f32>(r, g.g, b);

  let vortexCore = smoothstep(-0.03, 0.10, qCriterion);
  let shearRidge = smoothstep(0.08, 0.65, anisotropy);
  let phase = abs(vorticity) * 0.055 + anisotropy * 0.08 - time * 0.035;
  let metal = 0.5 + 0.5 * cos(TAU * (vec3<f32>(phase) + vec3<f32>(0.00, 0.24, 0.58)));
  var color = mix(plate, metal, clamp(0.18 + vortexCore * 0.42 + shearRidge * 0.25, 0.0, 0.78));
  color += vec3<f32>(1.0, 0.94, 0.82) * specular;
  color += metal * fresnel * (0.08 + 0.22 * mids);
  color += vec3<f32>(0.50, 0.72, 1.0) * ringGlow * (0.18 + bass * 0.3);

  let previous = textureLoad(dataTextureC, coord, 0);
  color = mix(color, previous.rgb, clamp(previous.a * (0.035 + 0.09 * surfaceTension), 0.0, 0.14));
  color = acesFilm(color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, departure, 0.0).r;
  let substance = clamp(vortexCore * 0.45 + shearRidge * 0.4 + specular * 0.25 + ringGlow * 0.25, 0.0, 1.0);
  let alpha = clamp(mix(g.a * (0.55 + 0.35 * transmission), 1.0, substance) * (1.0 - depth * 0.16), 0.0, 1.0);
  let outColor = vec4<f32>(color, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + substance * 0.12, 0.0, 1.0), 0.0, 0.0, 0.0));
}
