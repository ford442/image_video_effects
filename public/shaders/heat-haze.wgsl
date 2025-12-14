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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Params
  let heatGain = u.zoom_params.x;
  let decayRate = u.zoom_params.y;
  let diffusion = u.zoom_params.z;
  let refraction = u.zoom_params.w;

  // 1. Read previous heat (from Depth)
  // Diffusion: Sample neighbors
  let c = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let l = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
  let r = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
  let t = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
  let b = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;

  let avg = (l + r + t + b) * 0.25;
  let diffusedHeat = mix(c, avg, diffusion);

  // 2. Add Mouse Heat
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let aspect = resolution.x / resolution.y;
  let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

  let mouseHeat = 0.0;
  // If mouse is down, inject heat
  if (mouseDown > 0.5 && dist < 0.05) {
      mouseHeat = heatGain * (1.0 - dist / 0.05);
  }

  let newHeat = (diffusedHeat + mouseHeat) * decayRate;

  // Clamp
  let finalHeat = clamp(newHeat, 0.0, 1.0);

  // Write Heat to Depth (for next frame)
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(finalHeat, 0.0, 0.0, 0.0));

  // 3. Render
  // Distort UV based on Heat Gradient (refraction)
  // We use the spatial gradient of the heat map
  let heatGradX = r - l;
  let heatGradY = b - t;
  let warp = vec2<f32>(heatGradX, heatGradY) * refraction;

  let finalUV = uv - warp;

  // Sample Image with distorted UV
  let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  // Add some thermal glow overlay?
  // Heat map: Blue (cold) -> Red (hot) -> Yellow (very hot)
  // But let's keep it subtle: just a reddish tint
  let thermalTint = vec4<f32>(1.0, 0.3, 0.1, 1.0) * finalHeat * 0.5;

  textureStore(writeTexture, global_id.xy, color + thermalTint);
}
