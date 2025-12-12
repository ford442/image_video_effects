// Multiscale Turing Patterns - Multiple reaction-diffusion systems combined
// Based on Jonathan McCabe's multiscale patterns with DoG bands

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // scale 1 & 2
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // scale 3 & 4
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous state
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=Feed1, y=Kill1, z=Feed2, w=Kill2
  ripples: array<vec4<f32>, 50>,
};

// Scales for multi-resolution patterns
const SCALE1: f32 = 1.0;
const SCALE2: f32 = 2.0;
const SCALE3: f32 = 4.0;
const SCALE4: f32 = 8.0;

// Reaction-diffusion parameters
const DA: f32 = 1.0;
const DB: f32 = 0.5;
const DT: f32 = 1.0;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

// Gaussian blur for DoG (Difference of Gaussians)
fn gaussianBlur(uv: vec2<f32>, texelSize: vec2<f32>, radius: f32) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  var totalWeight = 0.0;
  
  let samples = 5;
  for (var y = -samples; y <= samples; y = y + 1) {
    for (var x = -samples; x <= samples; x = x + 1) {
      let offset = vec2<f32>(f32(x), f32(y)) * texelSize * radius;
      let dist = length(vec2<f32>(f32(x), f32(y)));
      let weight = exp(-dist * dist / (2.0 * radius * radius));
      sum = sum + textureSampleLevel(dataTextureC, non_filtering_sampler, uv + offset, 0.0) * weight;
      totalWeight = totalWeight + weight;
    }
  }
  
  return sum / totalWeight;
}

// Difference of Gaussians for pattern detection
fn differenceOfGaussians(uv: vec2<f32>, texelSize: vec2<f32>, scale: f32) -> f32 {
  let blur1 = gaussianBlur(uv, texelSize, scale).r;
  let blur2 = gaussianBlur(uv, texelSize, scale * 2.0).r;
  return blur1 - blur2;
}

// Laplacian for reaction-diffusion
fn laplacian(uv: vec2<f32>, texelSize: vec2<f32>, channel: i32) -> vec2<f32> {
  let center = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let left = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0);
  let right = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0);
  let up = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0);
  let down = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0);
  
  var c: vec2<f32>;
  var l: vec2<f32>;
  var r: vec2<f32>;
  var u_val: vec2<f32>;
  var d: vec2<f32>;
  
  if (channel == 0) {
    c = center.xy;
    l = left.xy;
    r = right.xy;
    u_val = up.xy;
    d = down.xy;
  } else {
    c = center.zw;
    l = left.zw;
    r = right.zw;
    u_val = up.zw;
    d = down.zw;
  }
  
  return l + r + u_val + d - 4.0 * c;
}

// Gray-Scott reaction-diffusion step
fn grayScottStep(ab: vec2<f32>, lap: vec2<f32>, feed: f32, kill: f32) -> vec2<f32> {
  let a = ab.x;
  let b = ab.y;
  
  let reaction = a * b * b;
  
  let da = DA * lap.x - reaction + feed * (1.0 - a);
  let db = DB * lap.y + reaction - (kill + feed) * b;
  
  return vec2<f32>(
    clamp(a + da * DT, 0.0, 1.0),
    clamp(b + db * DT, 0.0, 1.0)
  );
}

// HSV to RGB helper
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let x = c * (1.0 - abs((h % 2.0) - 1.0));
  let m = v - c;
  var rgb: vec3<f32>;
  if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters for different scales
  let feed1 = mix(0.01, 0.08, u.zoom_params.x);
  let kill1 = mix(0.04, 0.07, u.zoom_params.y);
  let feed2 = mix(0.02, 0.06, u.zoom_params.z);
  let kill2 = mix(0.05, 0.065, u.zoom_params.w);
  
  // Read current state
  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  
  // Initialize patterns from source image if state is empty
  var scale1 = state.xy;
  var scale2 = state.zw;
  
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  
  if (length(scale1) < 0.001 && length(scale2) < 0.001) {
    // Initialize with source luminance + noise
    let noise1 = hash21(uv * 100.0);
    let noise2 = hash21(uv * 200.0 + vec2<f32>(time, 0.0));
    
    scale1 = vec2<f32>(1.0, sourceLum * 0.5 + noise1 * 0.3);
    scale2 = vec2<f32>(1.0, sourceLum * 0.3 + noise2 * 0.3);
  }
  
  // Compute Laplacians for each scale
  let lap1 = laplacian(uv, texelSize * SCALE1, 0);
  let lap2 = laplacian(uv, texelSize * SCALE2, 1);
  
  // Apply reaction-diffusion at each scale
  scale1 = grayScottStep(scale1, lap1, feed1, kill1);
  scale2 = grayScottStep(scale2, lap2, feed2, kill2);
  
  // Cross-scale coupling - patterns at one scale affect others
  let coupling = 0.1;
  scale1 = scale1 + (scale2 - scale1) * coupling * 0.1;
  scale2 = scale2 + (scale1 - scale2) * coupling * 0.05;
  
  // Mouse interaction - seed new patterns
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(uv - mouse);
  if (mouseDist < 0.05) {
    let strength = 1.0 - mouseDist / 0.05;
    scale1.y = scale1.y + strength * 0.3;
    scale2.y = scale2.y + strength * 0.2;
  }
  
  // Ripple seeding
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 1.0) {
        let dist = length(uv - ripple.xy);
        if (dist < 0.04) {
          let strength = (1.0 - rippleAge) * (1.0 - dist / 0.04);
          scale1.y = scale1.y + strength * 0.5;
          scale2.y = scale2.y + strength * 0.3;
        }
      }
    }
  }
  
  // Store state
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(scale1, scale2));
  
  // Generate color from pattern values
  // Use different hues for different scales
  let patternValue1 = scale1.y;
  let patternValue2 = scale2.y;
  
  // Combine patterns with additive blending
  let combinedPattern = patternValue1 * 0.6 + patternValue2 * 0.4;
  
  // Color mapping - organic, natural colors

  let hue1 = 0.55 + patternValue1 * 0.1; // Cyan-ish
  let hue2 = 0.15 + patternValue2 * 0.1; // Orange-ish
  
  // HSV to RGB conversion
  let c1 = vec3<f32>(hue1 * 6.0, 0.7, patternValue1);
  let c2 = vec3<f32>(hue2 * 6.0, 0.6, patternValue2);
  
  
  let color1 = hsv2rgb(hue1 * 6.0, 0.7, patternValue1);
  let color2 = hsv2rgb(hue2 * 6.0, 0.6, patternValue2);
  
  // Blend with source image
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let patternColor = color1 * 0.6 + color2 * 0.4;
  let finalColor = mix(sourceColor.rgb, patternColor, combinedPattern * 0.7 + 0.1);
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
