// Fabric of Reality — wireframe textile render + commit positions to dataA

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

const THREAD_DENSITY: f32 = 3.0;
const FABRIC_BASE_ALPHA: f32 = 0.78;
const STRAINED_ALPHA: f32 = 0.55;
const TORN_ALPHA: f32 = 0.25;

fn fabricSSS(strain: f32, baseColor: vec3<f32>) -> vec3<f32> {
  let threadScatter = strain * 0.3;
  let gapTint = vec3<f32>(0.9, 0.9, 0.95);
  return mix(baseColor, baseColor * gapTint, threadScatter);
}

fn calculateFabricAlpha(strain: f32, isTorn: bool, threadDensity: f32) -> f32 {
  var alpha = FABRIC_BASE_ALPHA;
  if (isTorn) {
    alpha = TORN_ALPHA;
  } else if (strain > 0.5) {
    let stretchFactor = smoothstep(0.5, 1.0, strain);
    alpha = mix(FABRIC_BASE_ALPHA, STRAINED_ALPHA, stretchFactor);
  }
  let densityAlpha = exp(-threadDensity * 0.3);
  alpha = mix(alpha, alpha * 0.85, densityAlpha * 0.3);
  return clamp(alpha, 0.2, 0.88);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));

  let posState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let pos = posState.xy;
  let meta = textureLoad(dataTextureB, vec2<i32>(coord), 0);

  let totalStrain = meta.r;
  let isTorn = meta.g > 0.5;
  let weavePhase = meta.b;

  let sourceColor = textureSampleLevel(readTexture, u_sampler, pos, 0.0);
  let fabricColor = fabricSSS(totalStrain, sourceColor.rgb);

  let strainColor = mix(
    vec3<f32>(0.2, 0.4, 0.8),
    vec3<f32>(1.0, 0.3, 0.1),
    totalStrain
  );
  let weaveTint = vec3<f32>(
    0.5 + 0.5 * sin(weavePhase * 6.28),
    0.5 + 0.5 * sin(weavePhase * 6.28 + 2.09),
    0.5 + 0.5 * sin(weavePhase * 6.28 + 4.18)
  );
  var finalColor = mix(fabricColor, strainColor, totalStrain * 0.3);
  finalColor = mix(finalColor, finalColor * weaveTint, 0.15);
  if (isTorn) {
    finalColor = finalColor + vec3<f32>(1.0, 0.4, 0.1) * meta.g * 0.4;
  }

  let threadDensity = select(THREAD_DENSITY, 0.15, isTorn);
  let fabricAlpha = calculateFabricAlpha(totalStrain, isTorn, threadDensity);

  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, fabricAlpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pos, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(coord), posState);
}
