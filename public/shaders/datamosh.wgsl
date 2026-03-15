// ═══════════════════════════════════════════════════════════════
//  True Datamoshing - I/P-Frame Simulation with Motion Vectors
//  Category: retro-glitch
//  
//  Simulates video compression artifacts by:
//  - Computing optical flow between frames (motion estimation)
//  - Storing motion vectors in dataTextureA
//  - P-frame simulation: displacing pixels by accumulated motion
//  - I-frame refreshes: periodic full frame reset
//  - Creating authentic smearing and trailing artifacts
//  
//  ALPHA-AWARE: Motion trails fade with partial alpha, MPEG blocks
//  have corrupted alpha, datamoshing creates ghost frames
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Motion vectors (xy) + age (z) + strength (w)
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Accumulated smear buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=MotionStrength, y=IFrameInterval, z=BlendAmount, w=FeedbackDecay
  ripples: array<vec4<f32>, 50>,
};

// Hash function for noise
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, p3.zxy + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Convert RGB to luminance for optical flow
fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Block-based motion estimation (simplified optical flow)
// Returns estimated motion vector for this block
fn estimate_motion(coord: vec2<i32>, block_size: i32) -> vec2<f32> {
  let dim = vec2<i32>(textureDimensions(readTexture));
  
  // Get current frame block center color
  var cur_sum = vec3<f32>(0.0);
  var prev_sum = vec3<f32>(0.0);
  var count = 0;
  
  // Sample block
  for (var dy: i32 = -block_size; dy <= block_size; dy = dy + 2) {
    for (var dx: i32 = -block_size; dx <= block_size; dx = dx + 2) {
      let sample_coord = coord + vec2<i32>(dx, dy);
      if (sample_coord.x >= 0 && sample_coord.x < dim.x && 
          sample_coord.y >= 0 && sample_coord.y < dim.y) {
        cur_sum = cur_sum + textureLoad(readTexture, sample_coord, 0).rgb;
        prev_sum = prev_sum + textureLoad(dataTextureC, sample_coord, 0).rgb;
        count = count + 1;
      }
    }
  }
  
  if (count == 0) {
    return vec2<f32>(0.0);
  }
  
  let cur_avg = cur_sum / f32(count);
  let prev_avg = prev_sum / f32(count);
  
  // Simple gradient-based motion estimation
  // Look for best match in small neighborhood
  var best_motion = vec2<f32>(0.0);
  var best_diff = luminance(abs(cur_avg - prev_avg));
  
  let search_range = 3; // pixels to search
  
  for (var dy: i32 = -search_range; dy <= search_range; dy = dy + 1) {
    for (var dx: i32 = -search_range; dx <= search_range; dx = dx + 1) {
      let search_coord = coord + vec2<i32>(dx * 2, dy * 2);
      if (search_coord.x >= 0 && search_coord.x < dim.x && 
          search_coord.y >= 0 && search_coord.y < dim.y) {
        let search_color = textureLoad(dataTextureC, search_coord, 0).rgb;
        let diff = luminance(abs(cur_avg - search_color));
        if (diff < best_diff) {
          best_diff = diff;
          best_motion = vec2<f32>(f32(dx * 2), f32(dy * 2));
        }
      }
    }
  }
  
  return best_motion;
}

// Quantize coordinate to macroblock grid (like MPEG blocks)
fn quantize_to_block(coord: vec2<i32>, block_size: i32) -> vec2<i32> {
  return vec2<i32>(
    (coord.x / block_size) * block_size,
    (coord.y / block_size) * block_size
  );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let coord = vec2<i32>(global_id.xy);
  let dim = vec2<i32>(textureDimensions(readTexture));
  
  // Bounds check
  if (coord.x >= dim.x || coord.y >= dim.y) {
    return;
  }
  
  let resolution = vec2<f32>(dim);
  let uv = vec2<f32>(coord) / resolution;
  let time = u.config.x;
  let frame_count = u.config.y;
  
  // Parameters
  let motion_strength = u.zoom_params.x * 20.0;      // Scale motion vectors
  let iframe_interval = u.zoom_params.y * 120.0 + 5.0; // Frames between I-frames (5-125)
  let blend_amount = u.zoom_params.z * 0.95 + 0.05;    // How much to blend (0.05-1.0)
  let feedback_decay = u.zoom_params.w * 0.1;          // Decay rate for old smears
  
  // Macroblock size (like MPEG compression blocks)
  let block_size = 8; // 8x8 pixel blocks
  
  // Determine if this is an I-frame (key frame) or P-frame (predicted)
  let is_iframe = (frame_count % iframe_interval) < 1.0;
  
  // Calculate block coordinates for macroblock effects
  let block_coord = quantize_to_block(coord, block_size);
  let block_uv = vec2<f32>(block_coord) / resolution;
  
  // Get previous motion vector for this block
  let prev_motion_data = textureLoad(dataTextureC, block_coord, 0);
  var motion_vector = prev_motion_data.rg * 2.0 - 1.0; // Decode from 0-1 to -1 to 1 range
  var motion_age = prev_motion_data.b * 255.0; // Frame age of this motion vector
  var motion_strength_hist = prev_motion_data.a;
  
  // Get source alpha from current frame
  let current_sample = textureLoad(readTexture, coord, 0);
  let source_alpha = current_sample.a;
  
  // I-frame: Full refresh - reset motion vectors and use clean frame
  // P-frame: Use predicted motion and create smearing
  var output_color: vec3<f32>;
  var output_alpha: f32;
  var new_motion_data: vec4<f32>;
  
  if (is_iframe) {
    // I-FRAME: Complete image refresh (key frame)
    // Reset motion vectors and use current input directly
    output_color = current_sample.rgb;
    output_alpha = source_alpha;
    
    // Estimate new motion for next P-frames
    let new_motion = estimate_motion(block_coord, block_size / 2);
    let motion_normalized = new_motion / 20.0; // Normalize to 0-1 range
    
    // Store new motion vector (0-1 encoded)
    new_motion_data = vec4<f32>(
      motion_normalized.x * 0.5 + 0.5,
      motion_normalized.y * 0.5 + 0.5,
      0.0 / 255.0, // Reset age
      motion_strength / 20.0
    );
    
  } else {
    // P-FRAME: Predicted frame - use motion vectors to displace pixels
    
    // Occasionally update motion estimation (not every frame for stability)
    let update_motion = hash12(block_uv + time * 0.1) > 0.7;
    
    if (update_motion || motion_age < 1.0) {
      // Estimate new motion
      let new_motion = estimate_motion(block_coord, block_size / 2);
      let motion_normalized = clamp(new_motion / 20.0, vec2<f32>(-1.0), vec2<f32>(1.0));
      
      // Blend with previous motion for smoothness
      motion_vector = mix(motion_vector, motion_normalized, 0.3);
      motion_age = 0.0;
      motion_strength_hist = mix(motion_strength_hist, motion_strength / 20.0, 0.3);
    } else {
      // Age the motion vector
      motion_age = motion_age + 1.0;
    }
    
    // Apply motion vector displacement for datamoshing effect
    // This is the key: pixels are displaced by accumulated motion, creating trails
    let displacement = motion_vector * motion_strength;
    
    // Add some randomness for authentic compression artifacts
    let noise = hash12(block_uv + vec2<f32>(time * 0.01, frame_count * 0.001));
    let jitter = (noise - 0.5) * motion_strength * 0.1;
    
    // Calculate displaced coordinate
    let displaced_coord_f = vec2<f32>(coord) - displacement * block_size + jitter;
    let displaced_coord = vec2<i32>(displaced_coord_f);
    
    // Wrap around for continuous smearing
    let wrapped_x = ((displaced_coord.x % dim.x) + dim.x) % dim.x;
    let wrapped_y = ((displaced_coord.y % dim.y) + dim.y) % dim.y;
    let wrapped_coord = vec2<i32>(wrapped_x, wrapped_y);
    
    // Sample from previous frame at displaced position (P-frame prediction)
    let predicted_sample = textureLoad(dataTextureC, wrapped_coord, 0);
    let predicted_color = predicted_sample.rgb;
    let predicted_alpha = predicted_sample.a;
    
    // Get current frame input
    let current_color = current_sample.rgb;
    
    // Datamoshing blend: mix predicted (displaced) with current based on blend amount
    // High blend = more smearing/trails
    // Use block-level decision for macroblock artifacts
    let block_decision = hash13(vec3<f32>(block_uv, floor(frame_count / 3.0))) > 0.3;
    
    if (block_decision) {
      // Smear mode: blend displaced pixel with current
      output_color = mix(current_color, predicted_color, blend_amount);
      // Alpha blending: motion trails fade with partial alpha
      output_alpha = mix(source_alpha, predicted_alpha * (1.0 - motion_age * 0.01), blend_amount);
    } else {
      // Block artifact mode: use predicted pixel directly (creates visible blocks)
      output_color = mix(predicted_color, current_color, 0.2);
      // Block glitches corrupt alpha too
      output_alpha = mix(predicted_alpha * 0.9, source_alpha, 0.2);
    }
    
    // Apply feedback decay for trailing effect
    let prev_smear_sample = textureLoad(dataTextureC, coord, 0);
    let prev_smear = prev_smear_sample.rgb;
    let prev_alpha = prev_smear_sample.a;
    
    output_color = mix(output_color, prev_smear, feedback_decay);
    // Trail fade: motion trails have fade alpha
    output_alpha = mix(output_alpha, prev_alpha * 0.95, feedback_decay);
    
    // Encode motion data for next frame
    let motion_encoded = motion_vector * 0.5 + 0.5;
    new_motion_data = vec4<f32>(
      motion_encoded.x,
      motion_encoded.y,
      motion_age / 255.0,
      motion_strength_hist
    );
  }
  
  // Add occasional macroblock corruption (authentic datamoshing artifact)
  let corruption_chance = hash12(block_uv + vec2<f32>(floor(frame_count / 10.0))) > 0.95;
  if (corruption_chance && !is_iframe) {
    // Randomly corrupt some blocks - copy from wrong location
    let wrong_offset = vec2<i32>(
      i32(hash12(block_uv + 1.0) * 100.0) - 50,
      i32(hash12(block_uv + 2.0) * 100.0) - 50
    );
    let wrong_coord = coord + wrong_offset;
    let wrapped_wrong_x = ((wrong_coord.x % dim.x) + dim.x) % dim.x;
    let wrapped_wrong_y = ((wrong_coord.y % dim.y) + dim.y) % dim.y;
    let corrupted_sample = textureLoad(dataTextureC, vec2<i32>(wrapped_wrong_x, wrapped_wrong_y), 0);
    let corrupted_color = corrupted_sample.rgb;
    let corrupted_alpha = corrupted_sample.a;
    
    output_color = mix(output_color, corrupted_color, 0.7);
    // Digital corruption affects alpha channel too - create ghost frames
    output_alpha = mix(output_alpha, corrupted_alpha * 0.7 + 0.1, 0.7);
  }
  
  // Clamp alpha to valid range
  output_alpha = clamp(output_alpha, 0.0, 1.0);
  
  // Store motion vector data for next frame (in dataTextureA)
  textureStore(dataTextureA, coord, new_motion_data);
  
  // Store accumulated smear (in dataTextureB) with alpha
  textureStore(dataTextureB, coord, vec4<f32>(output_color, output_alpha));
  
  // Final output with glitched/preserved alpha
  textureStore(writeTexture, coord, vec4<f32>(output_color, output_alpha));
  
  // Pass through depth
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
