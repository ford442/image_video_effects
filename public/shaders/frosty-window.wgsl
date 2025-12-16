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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let freezeSpeed = 0.005 + u.zoom_params.x * 0.05;
  let meltRadius = 0.05 + u.zoom_params.y * 0.2;
  let blurStrength = u.zoom_params.z * 5.0;
  let frostOpacity = 0.5 + u.zoom_params.w * 0.5;

  // Mouse
  let mouse = u.zoom_config.yz;
  let dist = distance(uv, mouse);

  // Persistence (Frost Level)
  // Read previous state from dataTextureC (r channel)
  var frostLevel = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

  // Grow frost
  frostLevel = min(1.0, frostLevel + freezeSpeed);

  // Melt frost with mouse
  if (dist < meltRadius) {
    let melt = smoothstep(meltRadius, meltRadius * 0.5, dist);
    frostLevel = frostLevel * (1.0 - melt);
  }

  // Write frost state to dataTextureA
  textureStore(dataTextureA, global_id.xy, vec4<f32>(frostLevel, 0.0, 0.0, 1.0));

  // Effect
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  if (frostLevel > 0.0) {
     let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
     let angle = noise * 6.28;
     let radius = frostLevel * blurStrength * 0.01;
     let offset = vec2<f32>(cos(angle), sin(angle)) * radius;

     let blurredColor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
     let frostColor = blurredColor + vec4<f32>(0.1, 0.1, 0.2, 0.0) * frostLevel;
     color = mix(color, frostColor, frostLevel * frostOpacity);
  }

  textureStore(writeTexture, global_id.xy, color);
}
