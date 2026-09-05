// Hybrid Voronoi Glass — stable cellular optics with Cauchy dispersion and TIR.
// A/C stores ACES display RGBA. B is unused.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let x = fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
  let y = fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 43758.5453);
  return 0.18 + vec2<f32>(x, y) * 0.64;
}

fn fresnelSchlick(cosine: f32, ior: f32) -> f32 {
  let f0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
  return f0 + (1.0 - f0) * pow(1.0 - cosine, 5.0);
}

fn cauchyIOR(baseIOR: f32, dispersion: f32, wavelengthMicrons: f32) -> f32 {
  return baseIOR + dispersion * 0.012 / max(wavelengthMicrons * wavelengthMicrons, 0.12);
}

fn refractedOffset(normal: vec3<f32>, ior: f32, thickness: f32) -> vec2<f32> {
  let incident = normalize(vec3<f32>(0.0, 0.0, -1.0));
  let eta = 1.0 / ior;
  let cosine = clamp(-dot(incident, normal), 0.0, 1.0);
  let sinSquared = eta * eta * (1.0 - cosine * cosine);
  let transmittedCosine = sqrt(max(1.0 - sinSquared, 0.0));
  let refracted = eta * incident + (eta * cosine - transmittedCosine) * normal;
  return refracted.xy * thickness / max(abs(refracted.z), 0.15);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
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
  let cellDensity = 3.0 + u.zoom_params.x * 17.0;
  let baseIOR = 1.08 + u.zoom_params.y * 0.82;
  let dispersion = u.zoom_params.z;
  let thickness = 0.04 + u.zoom_params.w * 0.48;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let scaled = vec2<f32>(uv.x * aspect, uv.y) * cellDensity;
  let baseCell = floor(scaled);
  let local = fract(scaled);
  var nearestDistance = 100.0;
  var secondDistance = 100.0;
  var nearestVector = vec2<f32>(0.0);
  var nearestCell = vec2<f32>(0.0);
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let feature = neighbor + hash22(baseCell + neighbor);
      let delta = feature - local;
      let distanceToFeature = length(delta);
      if (distanceToFeature < nearestDistance) {
        secondDistance = nearestDistance;
        nearestDistance = distanceToFeature;
        nearestVector = delta;
        nearestCell = baseCell + neighbor;
      } else if (distanceToFeature < secondDistance) {
        secondDistance = distanceToFeature;
      }
    }
  }

  let stableBoundaryDistance = max((secondDistance - nearestDistance) * 0.5, 0.0);
  let boundary = 1.0 - smoothstep(0.015, 0.075, stableBoundaryDistance);
  let cellRandom = hash22(nearestCell);
  let cellNormal2 = normalize(nearestVector + vec2<f32>(0.0001));
  let facetTilt = 0.3 + cellRandom.x * 0.48;
  var normal = normalize(vec3<f32>(cellNormal2 * facetTilt, 1.0));

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDistance = length(pointerDelta);
  let lensPressure = exp(-pointerDistance * pointerDistance * 14.0) * select(0.32, 1.15, held);
  normal = normalize(normal + vec3<f32>(pointerDelta / max(pointerDistance, 0.0001) * lensPressure * 0.52, -lensPressure * 0.18));

  var fracture = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let delta = (uv - ripple.xy) * aspectVec;
      let rd = length(delta);
      let front = age * (0.24 + audio.x * 0.04);
      let ring = exp(-abs(rd - front) * 58.0) * exp(-age * 1.0);
      fracture += ring * (0.35 + boundary * 0.9) * (0.6 + hash22(nearestCell + f32(i)).x * 0.4);
      normal = normalize(normal + vec3<f32>(delta / max(rd, 0.0001) * ring * 0.38, 0.0));
    }
  }

  let iorR = cauchyIOR(baseIOR, dispersion, 0.700);
  let iorG = cauchyIOR(baseIOR, dispersion, 0.546);
  let iorB = cauchyIOR(baseIOR, dispersion, 0.436);
  let opticalThickness = thickness * (0.65 + cellRandom.y * 0.8 + boundary * 0.35);
  let pressureOffset = pointerDelta / aspectVec * lensPressure * 0.012;
  let rUV = clamp(uv + refractedOffset(normal, iorR, opticalThickness) / aspectVec + pressureOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + refractedOffset(normal, iorG, opticalThickness) / aspectVec + pressureOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + refractedOffset(normal, iorB, opticalThickness) / aspectVec + pressureOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let red = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let green = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let blue = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  let viewCosine = clamp(normal.z, 0.0, 1.0);
  let fresnel = fresnelSchlick(viewCosine, baseIOR);
  let exitEta = baseIOR;
  let totalInternalReflection = step(1.0, exitEta * exitEta * (1.0 - viewCosine * viewCosine));
  let absorptionColor = mix(vec3<f32>(0.24, 0.08, 0.025), vec3<f32>(0.04, 0.16, 0.22), cellRandom.x);
  let transmission = exp(-absorptionColor * opticalThickness * (2.0 + audio.y * 0.3));
  let reflectedColor = vec3<f32>(0.22, 0.55, 1.2) * (fresnel + totalInternalReflection * 0.65);
  let history = historyAt(uv - normal.xy / aspectVec * 0.002, resolution);
  var hdr = vec3<f32>(red, green, blue) * transmission * (1.0 - fresnel * 0.55);
  hdr += reflectedColor * (0.35 + boundary * 0.65 + audio.z * 0.2);
  hdr += vec3<f32>(1.15, 0.62, 0.28) * fracture * (0.25 + audio.z * 0.35);
  hdr += history.rgb * clamp(0.018 + fracture * 0.028 + boundary * 0.012, 0.0, 0.07);
  let alpha = clamp(0.18 + opticalThickness * 0.52 + fresnel * 0.45 + boundary * 0.28 + fracture * 0.2, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, gUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - fresnel * 0.3), 0.0, 0.0, 0.0));
}
