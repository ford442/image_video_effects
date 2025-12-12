// Log-Polar Droste Effect - Recursive Spiral Zoom
// Creates infinite recursive zoom effect with spiral distortion

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=ZoomSpeed, y=SpiralFactor, z=RecursionDepth, w=BranchCount
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const E: f32 = 2.71828182846;

// Complex number operations
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let denom = b.x * b.x + b.y * b.y;
  return vec2<f32>((a.x * b.x + a.y * b.y) / denom, (a.y * b.x - a.x * b.y) / denom);
}

fn cexp(z: vec2<f32>) -> vec2<f32> {
  let r = exp(z.x);
  return vec2<f32>(r * cos(z.y), r * sin(z.y));
}

fn clog(z: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(log(length(z)), atan2(z.y, z.x));
}

fn cpow(z: vec2<f32>, n: f32) -> vec2<f32> {
  let r = length(z);
  let theta = atan2(z.y, z.x);
  let newR = pow(r, n);
  let newTheta = theta * n;
  return vec2<f32>(newR * cos(newTheta), newR * sin(newTheta));
}

// Droste transformation
fn drosteTransform(z: vec2<f32>, time: f32, r1: f32, r2: f32, twist: f32) -> vec2<f32> {
  // Log-polar transformation
  var logZ = clog(z);
  
  // Scale and rotation parameters for seamless looping
  let scale = log(r2 / r1);
  let rotation = TAU / 4.0; // 90 degree rotation
  
  // Apply spiral twist
  logZ.y = logZ.y + logZ.x * twist;
  
  // Time-based animation
  logZ.x = logZ.x - time * 0.5;
  
  // Wrap to create infinite recursion
  logZ.x = fract(logZ.x / scale) * scale + log(r1);
  
  // Transform back to Cartesian
  return cexp(logZ);
}

// Smooth step for anti-aliasing
fn smoothBand(x: f32, edge0: f32, edge1: f32) -> f32 {
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters
  let zoomSpeed = mix(0.1, 1.0, u.zoom_params.x);
  let spiralFactor = mix(-1.0, 1.0, u.zoom_params.y);
  let recursionDepth = mix(1.0, 5.0, u.zoom_params.z);
  let branchCount = floor(mix(1.0, 6.0, u.zoom_params.w));
  
  // Center coordinates
  let aspect = u.config.z / u.config.w;
  var z = (uv - vec2<f32>(0.5)) * 2.0;
  z.x = z.x * aspect;
  
  // Mouse as center point
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let center = (mouse - vec2<f32>(0.5)) * 2.0 * vec2<f32>(aspect, 1.0);
  z = z - center;
  
  let r = length(z);
  let theta = atan2(z.y, z.x);
  
  // Define recursion radii
  let r1 = 0.2;
  let r2 = 0.8;
  
  // Log-polar coordinates
  var logR = log(r + 0.001);
  var angle = theta;
  
  // Apply spiral twist (Droste spiral)
  let twistAmount = spiralFactor * TAU / 4.0;
  angle = angle + logR * twistAmount / log(r2 / r1);
  
  // Time-based zoom animation
  logR = logR - time * zoomSpeed;
  
  // Wrap log-radius for infinite recursion
  let logRange = log(r2 / r1);
  logR = ((logR - log(r1)) % logRange + logRange) % logRange + log(r1);
  
  // Apply multi-branch spiral
  if (branchCount > 1.0) {
    let branchAngle = TAU / branchCount;
    angle = angle + floor(angle / branchAngle) * (time * zoomSpeed * 0.5);
  }
  
  // Convert back to Cartesian for texture sampling
  let newR = exp(logR);
  let newZ = vec2<f32>(newR * cos(angle), newR * sin(angle));
  
  // Ripple effects
  var rippleOffset = vec2<f32>(0.0);
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let rippleCenter = (ripple.xy - vec2<f32>(0.5)) * 2.0 * vec2<f32>(aspect, 1.0);
        let toRipple = newZ - rippleCenter;
        let dist = length(toRipple);
        let wave = sin(dist * 15.0 - rippleAge * 5.0) * 0.02;
        let fade = 1.0 - rippleAge / 2.0;
        rippleOffset = rippleOffset + normalize(toRipple + vec2<f32>(0.001)) * wave * fade;
      }
    }
  }
  
  // Map back to UV space
  var texZ = newZ + center + rippleOffset;
  texZ.x = texZ.x / aspect;
  var texUV = texZ * 0.5 + vec2<f32>(0.5);
  
  // Handle out-of-bounds with recursive sampling
  var recursionLevel = 0.0;
  var currentUV = texUV;
  
  for (var level = 0; level < 5; level = level + 1) {
    if (f32(level) >= recursionDepth) { break; }
    
    if (currentUV.x < 0.0 || currentUV.x > 1.0 || currentUV.y < 0.0 || currentUV.y > 1.0) {
      // Wrap with scale for recursion
      currentUV = fract(currentUV);
      recursionLevel = recursionLevel + 1.0;
    } else {
      break;
    }
  }
  
  // Sample source texture
  let sourceColor = textureSampleLevel(readTexture, u_sampler, clamp(currentUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(currentUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  
  // Color modification based on recursion depth
  var finalColor = sourceColor.rgb;
  
  // Tint based on recursion level
  let recursionTint = vec3<f32>(
    1.0 - recursionLevel * 0.1,
    1.0 - recursionLevel * 0.05,
    1.0 + recursionLevel * 0.1
  );
  finalColor = finalColor * recursionTint;
  
  // Spiral band coloring
  let spiralPhase = fract((angle + logR * spiralFactor) / TAU);
  let bandColor = vec3<f32>(
    0.5 + 0.5 * sin(spiralPhase * TAU),
    0.5 + 0.5 * sin(spiralPhase * TAU + TAU / 3.0),
    0.5 + 0.5 * sin(spiralPhase * TAU + TAU * 2.0 / 3.0)
  );
  
  // Subtle blend with spiral bands
  finalColor = mix(finalColor, finalColor * bandColor, 0.2);
  
  // Vignette at recursion boundaries
  let distFromCenter = length(z);
  let vignette = 1.0 - smoothstep(r2 * 0.8, r2, distFromCenter);
  let innerFade = smoothstep(r1 * 0.5, r1, distFromCenter);
  
  finalColor = finalColor * mix(0.7, 1.0, vignette * innerFade);
  
  // Add glow at center
  let centerGlow = exp(-distFromCenter * 3.0) * 0.3;
  finalColor = finalColor + vec3<f32>(0.2, 0.5, 1.0) * centerGlow;
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
