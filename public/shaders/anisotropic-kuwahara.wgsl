// Anisotropic Kuwahara Filter - Van Gogh Style Flow Painting
// Structure tensor based directional smoothing for painterly effects

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // structure tensor
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // temp
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=WindowSize, y=Anisotropy, z=Sharpness, w=FlowStrength
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Compute luminance
fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Gaussian weight
fn gaussian(x: f32, sigma: f32) -> f32 {
  return exp(-x * x / (2.0 * sigma * sigma)) / (2.506628 * sigma);
}

// Structure tensor computation
fn computeStructureTensor(uv: vec2<f32>, texelSize: vec2<f32>) -> mat2x2<f32> {
  // Sobel gradients
  var gx = 0.0;
  var gy = 0.0;
  
  // 3x3 Sobel
  let sobelX = array<f32, 9>(-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0);
  let sobelY = array<f32, 9>(-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0);
  
  var idx = 0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let sampleUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
      let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
      let lum = luminance(sample.rgb);
      gx = gx + lum * sobelX[idx];
      gy = gy + lum * sobelY[idx];
      idx = idx + 1;
    }
  }
  
  // Structure tensor: [gx*gx, gx*gy; gx*gy, gy*gy]
  return mat2x2<f32>(gx * gx, gx * gy, gx * gy, gy * gy);
}

// Get eigenvector (flow direction) from structure tensor
fn getFlowDirection(tensor: mat2x2<f32>) -> vec2<f32> {
  let a = tensor[0][0];
  let b = tensor[0][1];
  let c = tensor[1][0];
  let d = tensor[1][1];
  
  // Eigenvalue decomposition
  let trace = a + d;
  let det = a * d - b * c;
  let disc = sqrt(max(trace * trace * 0.25 - det, 0.0));
  
  let lambda1 = trace * 0.5 + disc;
  let lambda2 = trace * 0.5 - disc;
  
  // Eigenvector for smaller eigenvalue (perpendicular to gradient = flow direction)
  var flow: vec2<f32>;
  if (abs(b) > 0.0001) {
    flow = normalize(vec2<f32>(lambda2 - d, b));
  } else if (abs(c) > 0.0001) {
    flow = normalize(vec2<f32>(c, lambda2 - a));
  } else {
    flow = vec2<f32>(1.0, 0.0);
  }
  
  // Return anisotropy as length hint
  let anisotropy = (lambda1 - lambda2) / (lambda1 + lambda2 + 0.001);
  
  return flow * (0.5 + anisotropy * 0.5);
}

// Anisotropic Kuwahara filter
fn anisotropicKuwahara(uv: vec2<f32>, texelSize: vec2<f32>, flow: vec2<f32>, windowSize: f32, anisotropy: f32) -> vec3<f32> {
  let numSectors = 8;
  let sectorAngle = PI * 2.0 / f32(numSectors);
  
  // Get flow angle
  let flowAngle = atan2(flow.y, flow.x);
  
  var bestColor = vec3<f32>(0.0);
  var minVariance = 1e10;
  
  // Sample in each sector
  for (var sector = 0; sector < numSectors; sector = sector + 1) {
    let sectorStartAngle = flowAngle + f32(sector) * sectorAngle;
    
    var colorSum = vec3<f32>(0.0);
    var colorSqSum = vec3<f32>(0.0);
    var weightSum = 0.0;
    
    // Sample within sector
    let samples = i32(windowSize * 4.0);
    for (var i = 0; i < samples; i = i + 1) {
      let t = f32(i) / f32(samples);
      
      // Elliptical sampling based on anisotropy
      let r = (t * 0.8 + 0.2) * windowSize;
      let angle = sectorStartAngle + (t - 0.5) * sectorAngle * 0.8;
      
      // Elongate in flow direction
      let stretch = 1.0 + anisotropy;
      let sampleOffset = vec2<f32>(
        cos(angle) * r,
        sin(angle) * r * (1.0 / stretch)
      );
      
      let sampleUV = uv + sampleOffset * texelSize * 3.0;
      let sample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
      
      let weight = gaussian(t, 0.4);
      colorSum = colorSum + sample.rgb * weight;
      colorSqSum = colorSqSum + sample.rgb * sample.rgb * weight;
      weightSum = weightSum + weight;
    }
    
    if (weightSum > 0.0) {
      let mean = colorSum / weightSum;
      let meanSq = colorSqSum / weightSum;
      let variance = dot(meanSq - mean * mean, vec3<f32>(0.333));
      
      if (variance < minVariance) {
        minVariance = variance;
        bestColor = mean;
      }
    }
  }
  
  return bestColor;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters
  let windowSize = mix(2.0, 8.0, u.zoom_params.x);
  let anisotropy = mix(0.0, 2.0, u.zoom_params.y);
  let sharpness = mix(0.0, 2.0, u.zoom_params.z);
  let flowStrength = mix(0.0, 1.0, u.zoom_params.w);
  
  // Compute structure tensor
  let tensor = computeStructureTensor(uv, texelSize);
  
  // Get flow direction
  var flow = getFlowDirection(tensor);
  
  // Mouse interaction - create vortex in flow field
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = uv - mouse;
  let mouseDist = length(toMouse);
  let mouseInfluence = 0.15;
  
  if (mouseDist < mouseInfluence && mouseDist > 0.001) {
    let vortexStrength = (1.0 - mouseDist / mouseInfluence) * flowStrength;
    let perpendicular = vec2<f32>(-toMouse.y, toMouse.x) / mouseDist;
    flow = mix(flow, perpendicular, vortexStrength);
  }
  
  // Ripple disturbance in flow
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let toRipple = uv - ripple.xy;
        let dist = length(toRipple);
        if (dist < 0.1 && dist > 0.001) {
          let rotStrength = (1.0 - rippleAge / 2.0) * (1.0 - dist / 0.1);
          let rotated = vec2<f32>(-toRipple.y, toRipple.x) / dist;
          flow = mix(flow, rotated, rotStrength * 0.5);
        }
      }
    }
  }
  
  // Store flow field for visualization
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(flow, length(flow), 0.0));
  
  // Apply anisotropic Kuwahara filter
  let paintedColor = anisotropicKuwahara(uv, texelSize, flow, windowSize, anisotropy);
  
  // Get original for edge enhancement
  let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Edge enhancement (unsharp mask style)
  let edgeEnhance = (originalColor - paintedColor) * sharpness;
  
  // Final color
  var finalColor = paintedColor + edgeEnhance * 0.3;
  
  // Add subtle brush stroke texture based on flow
  let strokeFreq = 30.0;
  let strokeNoise = sin(dot(uv * strokeFreq, flow * 10.0 + vec2<f32>(time * 0.5)));
  let strokeTexture = strokeNoise * 0.02;
  finalColor = finalColor + vec3<f32>(strokeTexture);
  
  // Saturation boost for painterly look
  let gray = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  finalColor = mix(vec3<f32>(gray), finalColor, 1.2);
  
  // Clamp
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
