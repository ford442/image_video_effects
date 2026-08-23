// ═══════════════════════════════════════════════════════════════════
//  Liquid Metal — Rosensweig ferro-surface with anisotropic metal reflection
//  Raw A ownership: R height, G vertical velocity, B foam, A wetness.
//  C is the exact previous A copy; output is a projection of current state.
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

fn restHeight(p0: vec2<f32>, time: f32) -> f32 {
  var p = p0;
  var sum = 0.0;
  var amp = 0.5;
  for (var octave = 0; octave < 4; octave += 1) {
    sum += amp * noise2(p + vec2<f32>(time * 0.035, -time * 0.027));
    p = mat2x2<f32>(0.82, -0.57, 0.57, 0.82) * p * 2.03 + vec2<f32>(8.1, 3.7);
    amp *= 0.5;
  }
  return sum;
}

fn schlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3<f32>(1.0) - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampPixel(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Saved-preset contract: viscosity, reflectivity, chromatic_spread, flow_speed.
  let viscosity = u.zoom_params.x;
  let reflectivity = u.zoom_params.y;
  let chromaSpread = u.zoom_params.z;
  let flowSpeed = u.zoom_params.w;

  let stateC = textureLoad(dataTextureC, pixel, 0);
  let stateL = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let stateR = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let stateD = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let stateU = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let stateLD = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, -1), dims), 0);
  let stateRU = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 1), dims), 0);

  let rest = restHeight(uv * vec2<f32>(4.2 * aspect, 4.2), time * (0.2 + flowSpeed * 0.8));
  // A hexagonal Rosensweig mode approximates the fastest-growing ferrofluid
  // surface instability. Bass lifts the field; mids precess the spike lattice.
  let latticeP = (uv - 0.5) * aspectVec * (12.0 + flowSpeed * 7.0);
  let latticeAngle = time * (0.012 + mids * 0.018);
  let latticeRot = mat2x2<f32>(cos(latticeAngle), -sin(latticeAngle), sin(latticeAngle), cos(latticeAngle)) * latticeP;
  let hexMode = (cos(latticeRot.x) + 2.0 * cos(latticeRot.x * 0.5) * cos(latticeRot.y * 0.8660254)) / 3.0;
  let spikeMode = pow(clamp(hexMode * 0.5 + 0.5, 0.0, 1.0), 5.0);
  let magneticDrive = (0.035 + reflectivity * 0.11) * (0.75 + bass * 0.45);
  let equilibrium = 0.16 + rest * 0.12 + spikeMode * magneticDrive;
  let initialized = dot(abs(stateC), vec4<f32>(1.0)) > 0.000001;
  var height = select(equilibrium, max(stateC.r, 0.0), initialized);
  var velocity = select(0.0, clamp(stateC.g, -1.5, 1.5), initialized);
  let hL = select(equilibrium, stateL.r, initialized);
  let hR = select(equilibrium, stateR.r, initialized);
  let hD = select(equilibrium, stateD.r, initialized);
  let hU = select(equilibrium, stateU.r, initialized);
  let hLD = select(equilibrium, stateLD.r, initialized);
  let hRU = select(equilibrium, stateRU.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;
  let diagonalShear = (hRU - hLD) * 0.5;

  // A zeroed buffer initializes immediately as a low mercury sheet; later
  // frames are governed by surface tension, damping, depth flow, and impulses.
  let tension = mix(0.22, 0.07, viscosity);
  let damping = mix(0.93, 0.985, viscosity);
  var acceleration = laplacian * tension + (equilibrium - height) * 0.012;
  acceleration += diagonalShear * flowSpeed * 0.025;

  // Existing scene depth acts as a gravity basin.
  let depthC = textureLoad(readDepthTexture, pixel, 0).r;
  let depthL = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0).r;
  let depthR = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(1, 0), dims), 0).r;
  let depthD = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(0, -1), dims), 0).r;
  let depthU = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(0, 1), dims), 0).r;
  let depthGradient = vec2<f32>(depthR - depthL, depthU - depthD);
  acceleration += dot(depthGradient, vec2<f32>(hR - hL, hU - hD))
    * flowSpeed * 0.08;

  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec;
  let mouseRadius = length(mouseDelta);
  let heldPour = exp(-mouseRadius * mouseRadius * 95.0) * select(0.18, 1.0, u.zoom_config.w > 0.5);
  // The held cursor behaves like a local magnetic pole: a raised core and a
  // shallow moat sharpen into a mobile ferrofluid spike.
  let poleMoat = exp(-mouseRadius * mouseRadius * 95.0) - 0.42 * exp(-mouseRadius * mouseRadius * 24.0);
  acceleration += heldPour * (0.025 + flowSpeed * 0.045) + poleMoat * select(0.015, 0.09, u.zoom_config.w > 0.5);

  var impulse = 0.0;
  var foamImpulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri += 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.3) {
      let radius = length((uv - ripple.xy) * aspectVec);
      let front = smoothstep(0.028, 0.0, abs(radius - age * (0.22 + flowSpeed * 0.24))) * exp(-age * 1.0);
      impulse += front * cos(age * 7.0) * 0.13;
      foamImpulse += front;
    }
  }
  acceleration += impulse + (bass - 0.18) * 0.006 * sin(time * 2.6 + rest * TAU);

  velocity = clamp(velocity * damping + acceleration, -1.25, 1.25);
  height = clamp(height + velocity * mix(0.11, 0.045, viscosity), 0.0, 1.6);
  let curvature = abs(laplacian) * 4.0 + abs(velocity) * 0.9;
  let foam = clamp(max(stateC.b * mix(0.88, 0.97, viscosity),
    smoothstep(0.16, 0.72, curvature) + foamImpulse * 0.55 + treble * curvature * 0.08), 0.0, 1.0);
  let wetness = clamp(max(stateC.a * 0.992, smoothstep(0.05, 0.38, height) + heldPour * 0.3), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, foam, wetness));

  // Project the newly evolved raw state into a mercury surface.
  let gradient = vec2<f32>(hL - hR, hD - hU) * (2.0 + height * 4.0);
  let normal = normalize(vec3<f32>(gradient, 0.12 + viscosity * 0.12));
  let viewDir = normalize(vec3<f32>((uv - 0.5) * aspectVec * 0.48, 1.0));
  let refraction = normal.xy * (0.018 + height * 0.065) / aspectVec;
  let spread = chromaSpread * (0.015 + treble * 0.006);
  let rUV = clamp(uv + refraction * (1.0 - spread), vec2<f32>(0.001), vec2<f32>(0.999));
  let gUV = clamp(uv + refraction, vec2<f32>(0.001), vec2<f32>(0.999));
  let bUV = clamp(uv + refraction * (1.0 + spread), vec2<f32>(0.001), vec2<f32>(0.999));
  let source = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  let f0 = mix(vec3<f32>(0.46, 0.50, 0.56), vec3<f32>(0.91, 0.94, 0.98), reflectivity);
  let fresnel = schlick(max(dot(normal, viewDir), 0.0), f0);
  let key = normalize(vec3<f32>(-0.38, 0.58, 0.72));
  let rim = normalize(vec3<f32>(0.65, -0.22, 0.73));
  let specKey = pow(max(dot(normal, normalize(viewDir + key)), 0.0), mix(26.0, 170.0, reflectivity));
  let specRim = pow(max(dot(normal, normalize(viewDir + rim)), 0.0), mix(18.0, 90.0, reflectivity));
  // Ward-style anisotropic lobe aligned to the ferro-domain shear. It makes
  // each Rosensweig ridge stretch highlights along the local field direction.
  let shearAngle = atan2(gradient.y, gradient.x) + diagonalShear * 2.5;
  let tangent = normalize(vec3<f32>(cos(shearAngle), sin(shearAngle), -dot(normal.xy, vec2<f32>(cos(shearAngle), sin(shearAngle))) / max(normal.z, 0.08)));
  let bitangent = normalize(cross(normal, tangent));
  let halfKey = normalize(viewDir + key);
  let ndh = max(dot(normal, halfKey), 0.04);
  let tangentRoughness = mix(0.32, 0.075, reflectivity);
  let bitangentRoughness = mix(0.11, 0.035, reflectivity);
  let wardExponent = -(pow(dot(halfKey, tangent) / tangentRoughness, 2.0)
    + pow(dot(halfKey, bitangent) / bitangentRoughness, 2.0)) / max(ndh * ndh, 0.002);
  let anisotropicSpec = exp(wardExponent) / max(4.0 * tangentRoughness * bitangentRoughness * ndh, 0.08);
  let iridescence = 0.55 + 0.45 * cos(TAU * (vec3<f32>(0.86, 1.0, 1.16)
    * (height * 0.62 + curvature * 0.08 + time * 0.018) + vec3<f32>(0.0, 0.18, 0.35)));
  let environment = mix(vec3<f32>(0.16, 0.2, 0.28), iridescence, 0.22 + chromaSpread * 0.45);
  var color = source * (vec3<f32>(1.0) - fresnel * 0.72)
    + environment * fresnel * (0.8 + reflectivity * 0.55)
    + vec3<f32>(1.08, 1.02, 0.92) * specKey * (1.2 + bass * 0.5)
    + vec3<f32>(0.42, 0.68, 1.0) * specRim * 0.48
    + vec3<f32>(0.92, 0.97, 1.08) * anisotropicSpec * (0.07 + treble * 0.035) * (0.35 + spikeMode);
  color = mix(color, color + vec3<f32>(0.72, 0.84, 1.0) * foam * (0.38 + mids * 0.35), foam * 0.52);
  let alpha = clamp(wetness * (0.62 + reflectivity * 0.28) + fresnel.g * 0.14 + foam * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));

  let generatedDepth = clamp(height * 0.48 + foam * 0.08, 0.0, 0.92);
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(depthC * 0.82, generatedDepth), 0.0, 0.0, 0.0));
}
