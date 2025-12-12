// Flow Sort - Streamline Pixel Sorting
// Sorts pixels along vector field lines derived from luminance gradient

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // flow field
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // sorted buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=FlowStrength, y=SortPasses, z=StrandPersist, w=Threshold
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Luminance
fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Compute flow direction from luminance gradient
fn computeFlowField(uv: vec2<f32>, texelSize: vec2<f32>) -> vec2<f32> {
  // Sobel gradient
  let left = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).rgb);
  let right = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb);
  let up = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).rgb);
  let down = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb);
  
  let gx = right - left;
  let gy = down - up;
  
  // Flow is perpendicular to gradient
  return normalize(vec2<f32>(-gy, gx) + vec2<f32>(0.001));
}

// Hash function for randomness
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
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
  let flowStrength = mix(0.1, 2.0, u.zoom_params.x);
  let sortPasses = i32(mix(1.0, 8.0, u.zoom_params.y));
  let strandPersist = mix(0.0, 0.95, u.zoom_params.z);
  let threshold = mix(0.0, 1.0, u.zoom_params.w);
  
  // Compute flow field
  var flow = computeFlowField(uv, texelSize);
  
  // Add time-based rotation
  let timeRot = sin(time * 0.5) * 0.2;
  let c = cos(timeRot);
  let s = sin(timeRot);
  flow = vec2<f32>(flow.x * c - flow.y * s, flow.x * s + flow.y * c);
  
  // Mouse interaction - create vortex
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = uv - mouse;
  let mouseDist = length(toMouse);
  let mouseRadius = 0.2;
  
  if (mouseDist < mouseRadius && mouseDist > 0.001) {
    let vortex = vec2<f32>(-toMouse.y, toMouse.x) / mouseDist;
    let influence = 1.0 - mouseDist / mouseRadius;
    flow = mix(flow, vortex, influence * flowStrength);
  }
  
  // Ripple vortices
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let toRipple = uv - ripple.xy;
        let dist = length(toRipple);
        if (dist < 0.15 && dist > 0.001) {
          let vortex = vec2<f32>(-toRipple.y, toRipple.x) / dist;
          let influence = (1.0 - rippleAge / 2.0) * (1.0 - dist / 0.15);
          flow = mix(flow, vortex, influence * 0.5);
        }
      }
    }
  }
  
  // Store flow field
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(flow, 0.0, 0.0));
  
  // Get current pixel
  let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let currentLum = luminance(currentColor.rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Sorting threshold - only sort pixels above threshold
  let shouldSort = currentLum > threshold || currentLum < (1.0 - threshold);
  
  if (!shouldSort) {
    textureStore(writeTexture, vec2<i32>(coord), currentColor);
    textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }
  
  // Sample along flow line and sort
  var sortedColor = currentColor.rgb;
  var sortedLum = currentLum;
  
  // Look upstream and downstream in flow
  for (var passIndex = 0; passIndex < sortPasses; passIndex = passIndex + 1) {
    let passOffset = f32(passIndex + 1) * texelSize * flowStrength;
    
    // Sample upstream
    let upstreamUV = uv - flow * passOffset;
    let upstreamColor = textureSampleLevel(readTexture, u_sampler, upstreamUV, 0.0);
    let upstreamLum = luminance(upstreamColor.rgb);
    
    // Sample downstream
    let downstreamUV = uv + flow * passOffset;
    let downstreamColor = textureSampleLevel(readTexture, u_sampler, downstreamUV, 0.0);
    let downstreamLum = luminance(downstreamColor.rgb);
    
    // Sort by luminance - darker flows "down", brighter flows "up"
    if (upstreamLum > sortedLum) {
      // Swap - this pixel should be darker
      let blend = 0.5 / f32(passIndex + 1);
      sortedColor = mix(sortedColor, upstreamColor.rgb, blend);
      sortedLum = luminance(sortedColor);
    }
    
    if (downstreamLum < sortedLum) {
      // Swap - this pixel should be brighter
      let blend = 0.5 / f32(passIndex + 1);
      sortedColor = mix(sortedColor, downstreamColor.rgb, blend);
      sortedLum = luminance(sortedColor);
    }
  }
  
  // Persistence - blend with previous frame for strand trails
  let prevColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
  sortedColor = mix(sortedColor, prevColor, strandPersist);
  
  // Store for persistence
  textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(sortedColor, 1.0));
  
  // Add subtle glow to sorted areas
  let sortDelta = abs(sortedLum - currentLum);
  let glowIntensity = sortDelta * 0.5;
  
  // Depth influence - foreground sorts less
  let depthInfluence = 1.0 - depth * 0.5;
  sortedColor = mix(currentColor.rgb, sortedColor, depthInfluence);
  
  // Final blend with flow visualization
  let flowVis = abs(flow.x - flow.y) * 0.1;
  sortedColor = sortedColor + vec3<f32>(flowVis * 0.0); // Subtle flow vis
  
  // Clamp
  sortedColor = clamp(sortedColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(sortedColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
