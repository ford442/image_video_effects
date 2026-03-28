// ═══════════════════════════════════════════════════════════════
//  Datamosh Brush - Interactive Datamoshing with Alpha Ghosting
//  Category: retro-glitch
//
//  Interactive datamoshing brush that creates persistent smears:
//  - Paint to freeze or drag pixels
//  - Block-based MPEG artifact simulation
//  - Decay control for trail persistence
//  - Alpha ghosting creates semi-transparent motion trails
// ═══════════════════════════════════════════════════════════════

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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let aspect = resolution.x / resolution.y;
  var uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let brushSize = mix(0.02, 0.2, u.zoom_params.x);
  let blockSize = mix(0.0, 0.1, u.zoom_params.y); // Bitrate crush
  let decay = mix(0.0, 0.1, u.zoom_params.z);
  let alphaGhost = mix(0.3, 1.0, u.zoom_params.w); // Alpha ghosting intensity

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Read previous frame (feedback)
  var prevSample = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  var prevColor = prevSample.rgb;
  var prevAlpha = prevSample.a;

  // If alpha is 0 (uninitialized), use current frame
  if (prevAlpha < 0.01) {
      let currSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
      prevColor = currSample.rgb;
      prevAlpha = currSample.a;
  }

  // New input frame
  var inputSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var inputColor = inputSample.rgb;
  var inputAlpha = inputSample.a;

  // Datamosh brush logic:
  // 1. Decay: Gradually blend buffer towards current input with alpha fade
  var blendedColor = mix(prevColor, inputColor, decay);
  var blendedAlpha = mix(prevAlpha, inputAlpha, decay);
  
  // Ghost trail effect: reduce alpha based on decay for motion trails
  blendedAlpha = blendedAlpha * (1.0 - decay * 0.5);

  // 2. Brush interaction:
  // Quantize UV to blocks for macroblock effects
  let blockUV = floor(uv / max(0.001, blockSize)) * max(0.001, blockSize);
  let blockID = floor(uv * (1.0/max(0.001, blockSize)));

  // Check if mouse is in this block/area
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  if (mouseDown > 0.5 && dist < brushSize) {
      // Paint with MPEG Artifact Smear
      let noiseVal = hash12(blockID + vec2<f32>(u.config.x));
      if (noiseVal > 0.3) {
          // Glitchy offset read - corrupts both color and alpha
          let offsetUV = uv + vec2<f32>(noiseVal * 0.05);
          let glitchSample = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);
          blendedColor = glitchSample.rgb;
          // Digital corruption affects alpha - creates ghost blocks
          blendedAlpha = glitchSample.a * 0.8 + 0.1;
      } else {
         // Freeze the PREVIOUS color (don't update to new frame) - creates trails
         blendedColor = prevColor;
         // Partial alpha for ghost trails
         blendedAlpha = prevAlpha * alphaGhost;
      }

      // Ensure minimum alpha for visibility
      blendedAlpha = max(blendedAlpha, 0.1);
  }

  // Apply blockiness if enabled - quantize to macroblocks
  if (blockSize > 0.01) {
      let pixUV = floor(uv * (1.0/blockSize)) * blockSize;
      // Macroblock corruption affects alpha too
      let blockCorrupt = hash12(floor(uv / blockSize) + vec2<f32>(u.config.x * 0.1));
      if (blockCorrupt > 0.8) {
          // Corrupted block has random alpha
          blendedAlpha = mix(blendedAlpha, blockCorrupt, 0.3);
      }
  }

  // Final alpha clamp
  blendedAlpha = clamp(blendedAlpha, 0.0, 1.0);

  // Write to storage (for next frame) with RGBA
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(blendedColor, blendedAlpha));

  // Output to screen with full RGBA
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(blendedColor, blendedAlpha));
  
  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
