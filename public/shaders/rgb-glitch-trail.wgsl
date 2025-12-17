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
  let time = u.config.x;

  // Params
  let decayRate = 0.9 + u.zoom_params.x * 0.09;
  let radius = 0.05 + u.zoom_params.y * 0.2;
  let shiftStrength = u.zoom_params.z * 0.05;
  let chaos = u.zoom_params.w;

  // Mouse
  let mouse = u.zoom_config.yz;
  let dist = distance(uv, mouse);

  // Persistence (Glitch Intensity)
  var intensity = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

  // Decay
  intensity = intensity * decayRate;

  // Add from mouse
  if (dist < radius) {
     let val = smoothstep(radius, radius * 0.2, dist);
     intensity = min(1.0, intensity + val);
  }

  // Write state
  textureStore(dataTextureA, global_id.xy, vec4<f32>(intensity, 0.0, 0.0, 1.0));

  // Effect
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  if (intensity > 0.01) {
    let seed = uv.y * 100.0 + time;
    let noise = fract(sin(seed) * 43758.5453);

    let shift = intensity * shiftStrength;
    var r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(shift, 0.0), 0.0).r;
    var b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(shift, 0.0), 0.0).b;

    var g = color.g;
    if (chaos > 0.0 && intensity > 0.5) {
       if (noise > 0.9) {
          let streak = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(noise * 0.1, 0.0), 0.0);
          r = streak.r;
          g = streak.g;
          b = streak.b;
       }
    }

    color = vec4<f32>(r, g, b, color.a);
  }

  textureStore(writeTexture, global_id.xy, color);
}
