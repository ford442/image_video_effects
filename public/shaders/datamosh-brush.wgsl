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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let brushSize = mix(0.02, 0.2, u.zoom_params.x);
  let blockSize = mix(0.0, 0.1, u.zoom_params.y); // Bitrate crush
  let decay = mix(0.0, 0.1, u.zoom_params.z);
  let threshold = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Read previous frame (feedback)
  // We want to read from dataTextureC to see what was there before
  var prevColor = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);

  // If alpha is 0 (uninitialized), use current frame
  if (prevColor.a < 0.1) {
      prevColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  }

  // New input frame
  var inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // "Blockify" logic for the brush effect
  // We determine if this pixel is inside the "frozen" or "dragged" region.

  // Actually, standard Datamosh is: P-frames not updating.
  // We want to freeze the image where we paint.
  // So, if we paint, we COPY the current input to the buffer.
  // If we DON'T paint, the buffer just stays as is (infinite persistence)?
  // Or: if we don't paint, the buffer updates normally?

  // "Datamosh Brush": The brush drags pixels.
  // Implementation: The buffer stores uv offsets? Or colors?
  // Storing colors is easier for "freezing".

  // Logic:
  // 1. Decay: Gradually blend buffer towards current input.
  var blended = mix(prevColor, inputColor, decay);

  // 2. Brush interaction:
  // If mouse is down, we "smear".
  // Smearing means taking the color from (mouse position + relative offset) and putting it here?
  // Or simpler: If mouse is close, we DO NOT update the buffer (we freeze it).
  // Or: If mouse is close, we copy the color from the CENTER of the brush to the whole brush area? (Stamp)

  // Let's do "Pixel Drag".
  // We need motion vectors. We don't have them.

  // Alternate: "Macroblock Freeze".
  // Quantize UV to blocks.
  let blockUV = floor(uv / max(0.001, blockSize)) * max(0.001, blockSize);
  // Actually, we want the grid to be fixed.
  let blockID = floor(uv * (1.0/max(0.001, blockSize)));

  // Check if mouse is in this block/area.
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  if (mouseDown > 0.5 && dist < brushSize) {
      // Paint!
      // Option A: Freeze the current input forever.
      // Option B: Drag pixels.

      // Let's go with "MPEG Artifact Smear".
      // We copy the color from the current input, BUT we add some random offset (glitch)
      let noiseVal = hash12(blockID + vec2<f32>(u.config.x));
      if (noiseVal > threshold) {
          // Glitchy offset read
          blended = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(noiseVal * 0.05), 0.0);
      } else {
         // Freeze the PREVIOUS color (don't update to new frame)
         blended = prevColor;

         // OR: Drag from mouse center
         // blended = textureSampleLevel(readTexture, u_sampler, mouse + (uv - mouse)*0.5, 0.0);
      }

      // Force alpha 1
      blended.a = 1.0;
  } else {
      // If not painting, we normally show the video?
      // Or does the paint persist?
      // If we want persistence, we must output 'blended' (which is mix(prev, input)).
      // If decay is 0.0, prev persists forever.
  }

  // Write to storage (for next frame)
  textureStore(dataTextureA, vec2<i32>(global_id.xy), blended);

  // Output to screen (apply blockiness here if desired)
  if (blockSize > 0.01) {
      let pixUV = floor(uv * (1.0/blockSize)) * blockSize;
      // We read from the buffer we just computed, but at block coords
      // But we can't read from dataTextureA in the same pass easily (write-only).
      // We read from 'blended' but sampled? No, 'blended' is a vec4 for this pixel.
      // We can't do spatial reduction here easily.
      // We'll just output 'blended'. The "crush" effect comes from the randomness above.
      textureStore(writeTexture, vec2<i32>(global_id.xy), blended);
  } else {
      textureStore(writeTexture, vec2<i32>(global_id.xy), blended);
  }
}
