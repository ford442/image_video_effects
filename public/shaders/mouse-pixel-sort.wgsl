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

fn get_luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Mouse Input
  let mouse = u.zoom_config.yz; // 0..1
  let isMouseDown = u.zoom_config.w;

  // Parameters
  let sortThreshold = u.zoom_params.x; // Threshold
  let sortLength = u.zoom_params.y * 0.2; // Max sort distance
  let direction = u.zoom_params.z; // <0.5 vertical, >0.5 horizontal
  let mode = u.zoom_params.w; // 0 = standard, 1 = inverse

  // Mouse interaction:
  // If mouse is down, it acts as a "magnet" or "perturbation"
  var localThreshold = sortThreshold;

  let aspect = resolution.x / resolution.y;
  let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

  // If mouse is near, lower the threshold to trigger sorting
  if (mouse.x >= 0.0) {
      let influence = smoothstep(0.3, 0.0, dist);
      localThreshold = mix(localThreshold, 0.0, influence * isMouseDown);
  }

  // Sample original pixel
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = get_luma(c.rgb);

  // Sorting Logic:
  // We don't actually sort (which is hard in parallel), we "slide" pixels based on luma.
  // Brighter pixels slide further.

  var offset = 0.0;
  if (luma > localThreshold) {
      offset = (luma - localThreshold) * sortLength;
  }

  if (mode > 0.5) {
      // Invert logic: darker pixels slide
      if (luma < (1.0 - localThreshold)) {
           offset = ((1.0 - localThreshold) - luma) * sortLength;
      }
  }

  var sourceUV = uv;
  if (direction > 0.5) {
      // Horizontal Slide
      sourceUV.x -= offset;
  } else {
      // Vertical Slide
      sourceUV.y -= offset;
  }

  let finalColor = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);

  textureStore(writeTexture, global_id.xy, finalColor);

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
