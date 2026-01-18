// ────────────────────────────────────────────────────────────────────────────────
//  Rotoscope Ink – Interactive Cartoon/Ink Style
//  - Transforms the video into a stylized "rotoscope" animation.
//  - Uses edge detection for ink lines and color quantization for the cartoon look.
//  - Mouse interaction: Varies line thickness and edge sensitivity locally.
// ────────────────────────────────────────────────────────────────────────────────

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
  config: vec4<f32>,       // x=Time, y=MouseClick, z=ViewW, w=ViewH
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=LineThickness, y=Quantization, z=EdgeThreshold, w=Blend
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = u.config.zw;
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / dims;
  let texel = 1.0 / dims;

  // Parameters
  // x: Line Thickness (base)
  // y: Quantization Levels (2.0 to 16.0)
  // z: Edge Threshold
  // w: Ink Darkness / Blend

  let baseThickness = mix(0.5, 3.0, u.zoom_params.x);
  let quantLevels = mix(2.0, 16.0, u.zoom_params.y);
  let threshold = mix(0.01, 0.2, u.zoom_params.z);
  let inkStrength = u.zoom_params.w;

  // Mouse Interaction
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  // Mouse boosts line thickness and lowers threshold (more detail near mouse)
  let influence = 1.0 - smoothstep(0.0, 0.4, dist);
  let localThickness = baseThickness + influence * 2.0;
  let localThreshold = max(0.001, threshold - influence * 0.1);

  // Sobel Edge Detection
  let t = localThickness * texel;

  let c  = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let cN = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -t.y), 0.0).rgb;
  let cS = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, t.y), 0.0).rgb;
  let cE = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(t.x, 0.0), 0.0).rgb;
  let cW = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-t.x, 0.0), 0.0).rgb;

  let edgeH = getLuma(cE) - getLuma(cW);
  let edgeV = getLuma(cS) - getLuma(cN);
  let edgeMag = sqrt(edgeH*edgeH + edgeV*edgeV);

  let isEdge = step(localThreshold, edgeMag);

  // Color Quantization
  var quantColor = floor(c * quantLevels) / quantLevels;

  // Ink Application
  // If edge, darken.
  let inkColor = vec3<f32>(0.05, 0.05, 0.1); // Slightly blue-black ink
  var finalColor = mix(quantColor, inkColor, isEdge * inkStrength);

  // Extra "paper" texture or noise could be added, but keeping it clean for now.
  // Let's add a slight paper tint to highlights
  if (getLuma(finalColor) > 0.9) {
      finalColor = finalColor * vec3<f32>(1.0, 0.98, 0.95);
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
