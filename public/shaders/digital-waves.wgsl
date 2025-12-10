@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // zoomTime, mouseX, mouseY, unused
  zoom_params: vec4<f32>,         // param1, param2, param3, param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Hash function for pseudo-random numbers
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Generate digital wave pattern
fn digitalWavePattern(uv: vec2<f32>, time: f32, depth: f32) -> f32 {
  let waveSpeed = 2.0;
  let waveFreq = 15.0 + depth * 10.0;
  
  // Multiple wave layers
  var pattern = 0.0;
  pattern += sin(uv.x * waveFreq + time * waveSpeed) * 0.5;
  pattern += sin(uv.y * waveFreq * 0.8 - time * waveSpeed * 0.7) * 0.3;
  pattern += sin((uv.x + uv.y) * waveFreq * 0.6 + time * waveSpeed * 1.2) * 0.2;
  
  return pattern;
}

// Create scanline effect
fn scanlines(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  let scanlineFreq = 300.0;
  let scanlineSpeed = 50.0;
  let line = sin((uv.y * scanlineFreq + time * scanlineSpeed) * 3.14159);
  return 1.0 - (pow(abs(line), 0.5) * intensity);
}

// Pixelation effect
fn pixelate(uv: vec2<f32>, pixelSize: f32) -> vec2<f32> {
  return floor(uv / pixelSize) * pixelSize;
}

// RGB split based on wave pattern
fn rgbSplit(uv: vec2<f32>, splitAmount: f32, angle: f32) -> vec3<f32> {
  let offset = vec2<f32>(cos(angle), sin(angle)) * splitAmount;
  
  let r = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0).b;
  
  return vec3<f32>(r, g, b);
}

// Data corruption/glitch effect
fn glitchBlocks(uv: vec2<f32>, time: f32) -> vec2<f32> {
  let blockSize = 0.05;
  let blockPos = floor(uv / blockSize);
  let random = hash21(blockPos + floor(time * 5.0));
  
  if (random > 0.95) {
    let glitchOffset = vec2<f32>(
      (hash21(blockPos * 2.0 + time) - 0.5) * 0.1,
      (hash21(blockPos * 3.0 + time) - 0.5) * 0.05
    );
    return uv + glitchOffset;
  }
  
  return uv;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  
  // Sample depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Apply digital wave displacement
  let wavePattern = digitalWavePattern(uv, currentTime, depth);
  let waveDisplacement = vec2<f32>(
    sin(wavePattern * 3.14159) * 0.02,
    cos(wavePattern * 3.14159) * 0.02
  ) * (1.0 - depth * 0.5);
  
  var displacedUV = uv + waveDisplacement;
  
  // Apply glitch blocks occasionally
  displacedUV = glitchBlocks(displacedUV, currentTime);
  
  // Optional pixelation based on depth
  let pixelSize = 0.001 + (1.0 - depth) * 0.003;
  let pixelatedUV = pixelate(displacedUV, pixelSize);
  let usePixelated = step(0.5, fract(currentTime * 0.5));
  displacedUV = mix(displacedUV, pixelatedUV, usePixelated * 0.3);
  
  // RGB split effect based on wave
  let splitAmount = abs(sin(currentTime * 0.5)) * 0.005 * (1.0 + depth * 2.0);
  let splitAngle = wavePattern + currentTime * 0.3;
  var color = rgbSplit(displacedUV, splitAmount, splitAngle);
  
  // Apply scanlines
  let scanlineIntensity = 0.15;
  let scanlineMask = scanlines(uv, currentTime, scanlineIntensity);
  color *= scanlineMask;
  
  // Add digital noise
  let noiseAmount = 0.05;
  let noise = hash21(uv * resolution + currentTime * 10.0) * noiseAmount;
  color += vec3<f32>(noise);
  
  // Color quantization for digital look
  let quantizeLevels = 16.0;
  color = floor(color * quantizeLevels) / quantizeLevels;
  
  // Add cyan/magenta digital color shift based on depth
  let colorShift = vec3<f32>(
    0.1 * depth,
    0.0,
    0.1 * (1.0 - depth)
  );
  color += colorShift * abs(sin(currentTime * 2.0));
  
  // Handle mouse ripples as digital pulses
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 1.5) {
      let ripplePos = rippleData.xy;
      let dist = length(uv - ripplePos);
      
      // Digital pulse wave
      let pulseFreq = 20.0;
      let pulse = step(0.9, fract(dist * pulseFreq - timeSinceClick * 5.0));
      let attenuation = 1.0 - smoothstep(0.0, 1.5, timeSinceClick);
      
      color += vec3<f32>(0.0, 1.0, 1.0) * pulse * attenuation * 0.5;
    }
  }
  
  // Clamp color to valid range
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
  
  // Write output
  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
  
  // Store wave data in persistence texture for potential future use
  textureStore(dataTextureA, global_id.xy, vec4<f32>(wavePattern, depth, 0.0, 1.0));
  
  // Update depth texture
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
