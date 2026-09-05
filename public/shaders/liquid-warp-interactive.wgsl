// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Warp Interactive — Spectral Curl and Depth-Boundary Flow
//  Category: distortion
//  Features: analytic curl spectrum, RK2 advection, depth Coanda flow,
//            strain caustics, viscous temporal memory, FFT bands, click fronts,
//            chromatic refraction, ACES, semantic alpha
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
  zoom_params: vec4<f32>,  // x=distortion, y=flow speed, z=flow scale, w=viscosity
  ripples: array<vec4<f32>, 50>,
};

struct FlowDetail {
  velocity: vec2<f32>,
  jacobian: vec4<f32>, // du/dx, du/dy, dv/dx, dv/dy
};

const TAU: f32 = 6.28318530717958647692;

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let m2 = dot(v, v);
  if (m2 < 1e-10) { return vec2<f32>(0.0); }
  return v * inverseSqrt(m2);
}

// Analytic stream-function spectrum. Unlike finite-difference noise curl, this
// returns a divergence-free velocity and its f32 Jacobian in one four-wave pass.
fn spectralFlow(p: vec2<f32>, time: f32, speed: f32, scale: f32) -> FlowDetail {
  var velocity = vec2<f32>(0.0);
  var jacobian = vec4<f32>(0.0);
  for (var i = 0u; i < 4u; i = i + 1u) {
    let fi = f32(i);
    let angle = fi * 2.39996322972865332 + 0.61;
    let frequency = scale * exp2(fi * 0.72);
    let k = vec2<f32>(cos(angle), sin(angle)) * frequency;
    let band = 0.5 * (plasmaBuffer[i * 2u + 1u].x + plasmaBuffer[i * 2u + 2u].x);
    let amplitude = (0.095 / pow(frequency, 1.25)) * (0.55 + band * 1.45);
    let phase = dot(k, p) + time * speed * (0.17 + fi * 0.08)
                * select(-1.0, 1.0, (i & 1u) == 0u);
    let s = sin(phase);
    let c = cos(phase);
    velocity += vec2<f32>(k.y, -k.x) * amplitude * c;
    jacobian += vec4<f32>(-k.y * k.x, -k.y * k.y,
                           k.x * k.x,  k.x * k.y) * amplitude * s;
  }
  var out: FlowDetail;
  out.velocity = velocity;
  out.jacobian = jacobian;
  return out;
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
  return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let maxC = dimsI - vec2<i32>(1);
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

  let distortion = mix(0.001, 0.032, clamp(u.zoom_params.x, 0.0, 1.0));
  let flowSpeed = mix(0.35, 3.6, clamp(u.zoom_params.y, 0.0, 1.0));
  let flowScale = mix(2.0, 17.0, clamp(u.zoom_params.z, 0.0, 1.0));
  let viscosity = clamp(u.zoom_params.w, 0.0, 1.0);
  let held = step(0.5, u.zoom_config.w);
  let mouse = (u.zoom_config.yz - 0.5) * aspectVec;

  let base = spectralFlow(p, time, flowSpeed, flowScale);
  let midpoint = p - base.velocity * distortion * 0.5;
  let midFlow = spectralFlow(midpoint, time, flowSpeed, flowScale);
  var velocity = midFlow.velocity;
  let jacobian = midFlow.jacobian;

  let mouseDelta = p - mouse;
  let mouseDist = max(length(mouseDelta), 1e-4);
  let mouseEnvelope = exp(-mouseDist * mix(16.0, 7.0, 1.0 - viscosity));
  let tangent = safeNormalize(vec2<f32>(-mouseDelta.y, mouseDelta.x));
  let radial = safeNormalize(mouseDelta);
  velocity += tangent * mouseEnvelope * (0.06 + mids * 0.08) * (0.35 + held);
  velocity -= radial * mouseEnvelope * held * (0.04 + bass * 0.09);

  // Depth-gradient boundary: the tangential term makes the flow attach to
  // scene silhouettes (a compact Coanda approximation) instead of crossing
  // them as if the depth buffer were absent.
  let dE = textureLoad(readDepthTexture, clamp(coord + vec2<i32>( 1,  0), vec2<i32>(0), maxC), 0).r;
  let dW = textureLoad(readDepthTexture, clamp(coord + vec2<i32>(-1,  0), vec2<i32>(0), maxC), 0).r;
  let dN = textureLoad(readDepthTexture, clamp(coord + vec2<i32>( 0, -1), vec2<i32>(0), maxC), 0).r;
  let dS = textureLoad(readDepthTexture, clamp(coord + vec2<i32>( 0,  1), vec2<i32>(0), maxC), 0).r;
  let depthGradient = vec2<f32>(dE - dW, dS - dN) * 0.5;
  let boundary = smoothstep(0.01, 0.18, length(depthGradient));
  let boundaryTangent = safeNormalize(vec2<f32>(-depthGradient.y, depthGradient.x));
  let aligned = select(-1.0, 1.0, dot(velocity, boundaryTangent) >= 0.0);
  velocity = mix(velocity, boundaryTangent * aligned * length(velocity), boundary * (0.25 + viscosity * 0.45));

  var ringGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.2) {
      let delta = p - (rp.xy - 0.5) * aspectVec;
      let r = max(length(delta), 1e-4);
      let front = r - age * 0.55;
      let envelope = exp(-front * front * 180.0) * exp(-age * 1.3);
      velocity += safeNormalize(vec2<f32>(-delta.y, delta.x)) * envelope * (0.07 + bass * 0.09);
      ringGlow += envelope * envelope;
    }
  }
  ringGlow = min(ringGlow, 1.2);

  let duDx = jacobian.x;
  let duDy = jacobian.y;
  let dvDx = jacobian.z;
  let dvDy = jacobian.w;
  let vorticity = dvDx - duDy;
  let shear = sqrt((duDx - dvDy) * (duDx - dvDy) + (duDy + dvDx) * (duDy + dvDx));
  let strainCaustic = smoothstep(0.10, 1.4, shear * distortion * flowScale);

  let departure = clamp(uv + velocity / aspectVec * distortion, vec2<f32>(0.001), vec2<f32>(0.999));
  let flowDir = safeNormalize(velocity / aspectVec);
  let chroma = flowDir * (0.0007 + treble * 0.0042) * (0.4 + strainCaustic);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(departure + chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, departure, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(departure - chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  var color = vec3<f32>(sampleR, sampleG.g, sampleB);

  let previous = historyBilinear(departure * dims, dimsI);
  let memory = mix(0.025, 0.24, viscosity) * previous.a;
  color = mix(color, previous.rgb, memory);
  let interference = 0.5 + 0.5 * cos(TAU *
    (vec3<f32>(abs(vorticity) * 0.06 + shear * 0.025 - time * 0.045)
     + vec3<f32>(0.00, 0.31, 0.67)));
  color += interference * strainCaustic * (0.08 + 0.18 * treble);
  color += vec3<f32>(0.42, 0.70, 1.0) * ringGlow * (0.16 + 0.28 * bass);
  color += vec3<f32>(0.10, 0.24, 0.18) * boundary * (0.08 + 0.12 * mids);
  color = acesFilm(color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, departure, 0.0).r;
  let substance = clamp(length(velocity) * distortion * 18.0 + strainCaustic * 0.45
                        + ringGlow * 0.35 + boundary * 0.15, 0.0, 1.0);
  let alpha = clamp(mix(sampleG.a * 0.68 + 0.14, 1.0, substance), 0.0, 1.0);
  let outColor = vec4<f32>(color, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(dataTextureB, coord, vec4<f32>(clamp(vorticity * 0.05 + 0.5, 0.0, 1.0),
                                              clamp(shear * 0.04, 0.0, 1.0), boundary, strainCaustic));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + substance * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
