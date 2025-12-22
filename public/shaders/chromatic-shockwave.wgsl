// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Params
  let speed = u.zoom_params.x * 10.0;
  let freq = 10.0 + u.zoom_params.y * 50.0;
  let aberr = u.zoom_params.z * 0.1; // Max 0.1 UV distance

  let diff = uv - mouse;
  // Use a small epsilon to avoid divide by zero in normalize
  let distSq = dot(diff, diff);

  var dir = vec2<f32>(1.0, 0.0);
  if (distSq > 0.000001) {
    dir = normalize(diff);
  }

  let dist = sqrt(dot(diff * vec2<f32>(aspect, 1.0), diff * vec2<f32>(aspect, 1.0)));

  // Wave function
  let wave = sin(dist * freq - time * speed);

  // Chromatic Aberration Offsets
  // Red moves one way, Blue the other
  let offsetR = dir * wave * aberr;
  let offsetB = -dir * wave * aberr;
  // Green stays closer to center (or move less)
  let offsetG = dir * wave * aberr * 0.3;

  let r = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

  textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
