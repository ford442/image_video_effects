@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // zoomTime, mouseX, mouseY, unused
  zoom_params: vec4<f32>,         // param1, param2, param3, param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Helper function to rotate UV coordinates
fn rotate2D(uv: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(
    uv.x * c - uv.y * s,
    uv.x * s + uv.y * c
  );
}

// Create a fractal kaleidoscope pattern
fn kaleidoscopeFractal(uv: vec2<f32>, time: f32, segments: f32) -> vec2<f32> {
  var coord = uv - 0.5;
  let radius = length(coord);
  var angle = atan2(coord.y, coord.x);
  
  // Create kaleidoscope effect by mirroring around segments
  let segmentAngle = 6.28318530718 / segments;
  angle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
  
  // Reconstruct coordinates
  coord = vec2<f32>(cos(angle), sin(angle)) * radius;
  
  return coord + 0.5;
}

// Multi-level fractal zoom with depth awareness
fn fractalZoom(uv: vec2<f32>, time: f32, depth: f32, iterations: i32) -> vec2<f32> {
  var coord = uv;
  let zoomSpeed = 0.3 + depth * 0.2;
  
  for (var i: i32 = 0; i < iterations; i = i + 1) {
    let level = f32(i);
    let scale = 1.0 + sin(time * zoomSpeed + level * 1.5) * 0.3;
    let rotation = time * 0.1 * (1.0 + level * 0.5);
    
    coord = coord - 0.5;
    coord = rotate2D(coord, rotation);
    coord = coord * scale;
    coord = coord + 0.5;
    
    // Add depth-based distortion
    coord += vec2<f32>(
      sin(time * 0.5 + level + depth * 2.0) * 0.02,
      cos(time * 0.5 + level + depth * 2.0) * 0.02
    );
  }
  
  return fract(coord);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  
  // Sample depth for this pixel
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Number of kaleidoscope segments (animated)
  let segments = 6.0 + sin(currentTime * 0.2) * 2.0;
  
  // Apply kaleidoscope effect
  var kaleidoUV = kaleidoscopeFractal(uv, currentTime, segments);
  
  // Apply multi-level fractal zoom based on depth
  let iterations = 3 + i32(depth * 2.0);
  let finalUV = fractalZoom(kaleidoUV, currentTime, depth, iterations);
  
  // Sample the texture multiple times for chromatic effect
  let chromaticOffset = 0.003 * (1.0 - depth);
  let colorR = textureSampleLevel(readTexture, u_sampler, finalUV + vec2<f32>(chromaticOffset, 0.0), 0.0).r;
  let colorG = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let colorB = textureSampleLevel(readTexture, u_sampler, finalUV - vec2<f32>(chromaticOffset, 0.0), 0.0).b;
  
  var finalColor = vec3<f32>(colorR, colorG, colorB);
  
  // Add depth-based color modulation
  let depthModulation = 0.8 + depth * 0.4;
  finalColor *= depthModulation;
  
  // Add subtle glow effect based on symmetry
  let symmetryGlow = pow(1.0 - abs(fract(atan2(uv.y - 0.5, uv.x - 0.5) / 6.28318530718 * segments) - 0.5) * 2.0, 3.0);
  finalColor += vec3<f32>(symmetryGlow * 0.15);
  
  // Handle ripple interactions
  let rippleCount = u32(u.config.y);
  var rippleInfluence = 0.0;
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
      let ripplePos = rippleData.xy;
      let dist = length(uv - ripplePos);
      let wave = sin(dist * 30.0 - timeSinceClick * 5.0);
      let attenuation = 1.0 - smoothstep(0.0, 2.0, timeSinceClick);
      rippleInfluence += wave * attenuation * 0.3 / (dist * 10.0 + 1.0);
    }
  }
  
  finalColor += vec3<f32>(rippleInfluence * 0.2);
  
  // Write output
  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
  
  // Update depth texture
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
