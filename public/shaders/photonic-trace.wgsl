// Photonic Caustics — photon trace batch (graph node 2, repeat N)
// Reads emitter scratch from dataTextureC, accumulates into dataTextureA

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

const PI: f32 = 3.14159265359;
const PHOTONS_PER_PASS: i32 = 16;

fn hash31(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn fresnelSchlick(cosTheta: f32, ior: f32) -> f32 {
  let r0 = (1.0 - ior) / (1.0 + ior);
  let r0sq = r0 * r0;
  return r0sq + (1.0 - r0sq) * pow(1.0 - cosTheta, 5.0);
}

fn refractRay(incident: vec3<f32>, normal: vec3<f32>, eta: f32) -> vec3<f32> {
  let cosi = -dot(normal, incident);
  let sin2t = eta * eta * (1.0 - cosi * cosi);
  if (sin2t > 1.0) {
    return reflect(incident, normal);
  }
  let cost = sqrt(1.0 - sin2t);
  return incident * eta + normal * (eta * cosi - cost);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u.config.y;

  let baseIOR = mix(1.1, 1.8, u.zoom_params.x);
  let lightSize = mix(0.05, 0.3, u.zoom_params.y);
  let dispersion = mix(0.0, 0.1, u.zoom_params.z);
  let intensity = mix(0.5, 3.0, u.zoom_params.w);

  let lightPos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let emitter = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let hitNormal = emitter.rgb;
  let lightHeight = emitter.a;

  var causticAccum = vec3<f32>(0.0);
  let batchOffset = i32(fract(frame * 0.1) * f32(PHOTONS_PER_PASS));

  for (var p = 0; p < PHOTONS_PER_PASS; p = p + 1) {
    let pid = p + batchOffset;
    let seed = vec3<f32>(uv, f32(pid) + time * 0.01);
    let randomAngle = hash31(seed) * 2.0 * PI;
    let randomRadius = sqrt(hash31(seed + vec3<f32>(1.0, 0.0, 0.0))) * lightSize;
    let photonOrigin = lightPos + vec2<f32>(cos(randomAngle), sin(randomAngle)) * randomRadius;

    let toPixel = uv - photonOrigin;
    let dist2D = length(toPixel);
    let dir2D = toPixel / max(dist2D, 0.001);
    let lightDir = normalize(vec3<f32>(dir2D, -lightHeight));

    let cosTheta = abs(dot(lightDir, hitNormal));
    let iorR = baseIOR - dispersion;
    let iorG = baseIOR;
    let iorB = baseIOR + dispersion;

    let refractR = refractRay(lightDir, hitNormal, 1.0 / iorR);
    let refractG = refractRay(lightDir, hitNormal, 1.0 / iorG);
    let refractB = refractRay(lightDir, hitNormal, 1.0 / iorB);

    let convergenceR = abs(dot(refractR, vec3<f32>(0.0, 0.0, -1.0)));
    let convergenceG = abs(dot(refractG, vec3<f32>(0.0, 0.0, -1.0)));
    let convergenceB = abs(dot(refractB, vec3<f32>(0.0, 0.0, -1.0)));
    let fresnel = 1.0 - fresnelSchlick(cosTheta, baseIOR);
    let attenuation = 1.0 / (1.0 + dist2D * 5.0);

    causticAccum = causticAccum + vec3<f32>(
      pow(convergenceR, 4.0) * fresnel * attenuation,
      pow(convergenceG, 4.0) * fresnel * attenuation,
      pow(convergenceB, 4.0) * fresnel * attenuation
    );
  }

  causticAccum = causticAccum / f32(PHOTONS_PER_PASS) * intensity;
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(causticAccum, 1.0));
}
