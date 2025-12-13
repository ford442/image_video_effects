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

  let mouseX = u.zoom_config.y; // 0..1
  let mouseY = u.zoom_config.z; // 0..1

  let threshold = mouseX; // Threshold controlled by mouse X
  let intensity = mouseY; // Intensity controlled by mouse Y

  let direction = u.zoom_params.x; // 0 = Vertical, 1 = Horizontal
  let reverse = u.zoom_params.y; // 0 = standard, 1 = reverse sort

  // Sample original
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = get_luma(c.rgb);

  var offset_amt = 0.0;

  if (luma > threshold) {
      // "Melt" or "Slide"
      // The brighter the pixel (above threshold), the further it slides.
      offset_amt = (luma - threshold) * intensity * 0.2; // Max 0.2 screen slide
  }

  var sampleUV = uv;
  if (direction < 0.5) {
      // Vertical
      if (reverse > 0.5) {
          sampleUV.y += offset_amt;
      } else {
          sampleUV.y -= offset_amt;
      }
  } else {
      // Horizontal
      if (reverse > 0.5) {
          sampleUV.x += offset_amt;
      } else {
          sampleUV.x -= offset_amt;
      }
  }

  let finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  textureStore(writeTexture, global_id.xy, finalColor);

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
