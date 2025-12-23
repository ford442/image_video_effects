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

// Helper function to convert RGB to YUV
fn rgb2yuv(rgb: vec3<f32>) -> vec3<f32> {
    let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
    let v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
    return vec3<f32>(y, u, v);
}

// Helper function to convert YUV to RGB
fn yuv2rgb(yuv: vec3<f32>) -> vec3<f32> {
    let r = yuv.x + 1.13983 * yuv.z;
    let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
    let b = yuv.x + 2.03211 * yuv.y;
    return vec3<f32>(r, g, b);
}

// Hash function for noise
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  // x: Block Size (Compression level)
  // y: Color Depth (Bit crushing)
  // z: Artifacts/Noise amount
  // w: Mouse Focus Radius (Area to keep clear)

  let blockSizeParam = u.zoom_params.x;
  let colorDepthParam = u.zoom_params.y;
  let artifactParam = u.zoom_params.z;
  let focusRadius = u.zoom_params.w;

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  // Calculate influence: 1.0 = fully distorted, 0.0 = clear
  let influence = smoothstep(focusRadius * 0.5, focusRadius, dist);

  // Apply block quantization to UVs
  // Scale blocks from 32 pixels to 2 pixels (inverted logic: param 1.0 -> big blocks)
  let blocks = mix(256.0, 16.0, blockSizeParam * influence);

  // Aspect corrected block grid
  let blockUV = vec2<f32>(
      floor(uv.x * blocks * aspect) / (blocks * aspect),
      floor(uv.y * blocks) / blocks
  );

  // Add some jitter to blockUV based on artifacts
  let noise = hash12(blockUV * 10.0 + u.config.x);
  var sampleUV = blockUV;

  if (artifactParam > 0.0 && noise < artifactParam * 0.1 * influence) {
      // Random block displacement
      sampleUV.x += (noise - 0.5) * 0.1;
  }

  // Sample color
  var color = textureSampleLevel(readTexture, non_filtering_sampler, sampleUV, 0.0).rgb;

  // Color quantization (Bit Crushing)
  // Reduce color palette
  if (colorDepthParam > 0.0) {
      // Levels: 255 down to 2
      let levels = mix(255.0, 2.0, colorDepthParam * influence);
      color = floor(color * levels) / levels;
  }

  // Chroma subsampling simulation (YUV conversion)
  if (artifactParam > 0.0) {
     let yuv = rgb2yuv(color);
     // Quantize UV channels more aggressively
     let uvLevels = mix(255.0, 4.0, artifactParam * influence);
     let qU = floor(yuv.y * uvLevels) / uvLevels;
     let qV = floor(yuv.z * uvLevels) / uvLevels;
     color = yuv2rgb(vec3<f32>(yuv.x, qU, qV));
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
