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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Threshold, y=SortStrength, z=Direction, w=Glitchiness
  ripples: array<vec4<f32>, 50>,
};

// Pseudo random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mousePos = u.zoom_config.yz;

  let threshold = u.zoom_params.x;
  let strength = u.zoom_params.y * 0.5; // Max displacement length
  let dirMix = u.zoom_params.z;
  let glitch = u.zoom_params.w;

  // Calculate luminance
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Mouse interaction: Modify threshold based on Y position of mouse
  // and maybe local influence
  let mouseInfluence = 0.0;
  if (abs(uv.y - mousePos.y) < 0.2) {
      mouseInfluence = 1.0 - abs(uv.y - mousePos.y) / 0.2;
  }

  // Dynamic threshold
  let localThreshold = threshold - (mouseInfluence * 0.2);

  var offset = vec2<f32>(0.0, 0.0);

  if (luma > localThreshold) {
      // "Sort" / Displace
      // The brighter the pixel, the further we look back/forward?
      // Or we shift this pixel to a new location?
      // Simple glitch sort: displace UV based on luma if above threshold

      let shift = (luma - localThreshold) * strength;

      // Add noise/glitch
      let noise = rand(vec2<f32>(uv.y, time)) * glitch;

      if (dirMix < 0.5) {
          // Vertical sort/smear
          offset.y = shift + noise * 0.1;
      } else {
          // Horizontal sort/smear
          offset.x = shift + noise * 0.1;
      }
  }

  // Sample at offset
  let srcUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let finalColor = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);

  textureStore(writeTexture, global_id.xy, finalColor);
}
