// Chromatographic Separation - RGB Channel Fluid Viscosity Simulation
// Separate velocity fields for R, G, B with interacting drag forces

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // velocity R (xy) + velocity G (zw)
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // velocity B (xy) + temp (zw)
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous state
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=WindX, y=MouseX, z=MouseY, w=WindY
  zoom_params: vec4<f32>,  // x=ViscosityR, y=ViscosityG, z=ViscosityB, w=Temperature
  ripples: array<vec4<f32>, 50>,
};

const DIFFUSION: f32 = 0.1;
const DT: f32 = 0.016;

// Noise function
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// Semi-Lagrangian advection
fn advect(uv: vec2<f32>, velocity: vec2<f32>, texelSize: vec2<f32>) -> vec2<f32> {
  let prevUV = uv - velocity * DT * 0.5;
  return clamp(prevUV, vec2<f32>(0.0), vec2<f32>(1.0));
}

// Laplacian for diffusion
fn laplacian2D(uv: vec2<f32>, texelSize: vec2<f32>, channel: i32) -> vec2<f32> {
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
  
  return (l + r + u_val + d - 4.0 * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters - viscosities control how "thick" each color layer is
  let viscosityR = mix(0.01, 0.5, u.zoom_params.x);
  let viscosityG = mix(0.01, 0.5, u.zoom_params.y);
  let viscosityB = mix(0.01, 0.5, u.zoom_params.z);
  let temperature = mix(0.0, 1.0, u.zoom_params.w);
  
  // Wind direction from zoom_config
  let wind = vec2<f32>(
    sin(time * 0.5) * 0.1 + u.zoom_config.x * 0.2,
    cos(time * 0.7) * 0.05 + u.zoom_config.w * 0.2
  );
  
  // Read previous velocity states from dataTextureC
  let stateA = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var velR = stateA.xy;
  var velG = stateA.zw;
  
  // For velocity B, we'll pack it differently - using the luminance gradient
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Initialize velocities if zero
  if (length(velR) < 0.0001 && length(velG) < 0.0001) {
    // Initialize based on color gradients
    let colorL = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0);
    let colorR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0);
    let colorU = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0);
    let colorD = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0);
    
    velR = vec2<f32>(colorR.r - colorL.r, colorD.r - colorU.r) * 0.1;
    velG = vec2<f32>(colorR.g - colorL.g, colorD.g - colorU.g) * 0.1;
  }
  
  var velB = vec2<f32>(
    sin(uv.y * 10.0 + time) * 0.02,
    cos(uv.x * 10.0 + time) * 0.02
  );
  
  // Apply wind force
  velR = velR + wind * (1.0 - viscosityR);
  velG = velG + wind * (1.0 - viscosityG);
  velB = velB + wind * (1.0 - viscosityB);
  
  // Mouse interaction - inject velocity
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = mouse - uv;
  let mouseDist = length(toMouse);
  let mouseRadius = 0.1;
  
  if (mouseDist < mouseRadius && mouseDist > 0.001) {
    let force = (1.0 - mouseDist / mouseRadius) * 0.1;
    let dir = normalize(toMouse);
    velR = velR + dir * force / viscosityR;
    velG = velG + dir * force / viscosityG;
    velB = velB + dir * force / viscosityB;
  }
  
  // Apply ripple forces
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let toRipple = uv - ripple.xy;
        let dist = length(toRipple);
        if (dist < 0.15 && dist > 0.001) {
          let force = (1.0 - rippleAge / 2.0) * (1.0 - dist / 0.15) * 0.05;
          let dir = normalize(toRipple);
          // Different channels respond differently
          velR = velR + dir * force * (1.0 + sin(time * 5.0));
          velG = velG + dir * force * (1.0 + sin(time * 5.0 + 2.094));
          velB = velB + dir * force * (1.0 + sin(time * 5.0 + 4.188));
        }
      }
    }
  }
  
  // Diffusion (viscosity-dependent)
  let lapR = laplacian2D(uv, texelSize, 0);
  let lapG = laplacian2D(uv, texelSize, 1);
  
  velR = velR + lapR * DIFFUSION * (1.0 - viscosityR);
  velG = velG + lapG * DIFFUSION * (1.0 - viscosityG);
  
  // Inter-layer drag/cohesion - layers influence each other
  let dragRG = (velG - velR) * 0.02;
  let dragGB = (velB - velG) * 0.02;
  let dragBR = (velR - velB) * 0.02;
  
  velR = velR + dragRG - dragBR;
  velG = velG + dragGB - dragRG;
  velB = velB + dragBR - dragGB;
  
  // Temperature-based evaporation/condensation
  let evaporationR = temperature * (1.0 - viscosityR) * 0.01;
  let evaporationG = temperature * (1.0 - viscosityG) * 0.01;
  let evaporationB = temperature * (1.0 - viscosityB) * 0.01;
  
  // Depth influence - foreground moves faster
  let depthFactor = 0.5 + depth * 0.5;
  velR = velR * depthFactor;
  velG = velG * depthFactor;
  velB = velB * depthFactor;
  
  // Damping
  let dampingR = mix(0.99, 0.95, viscosityR);
  let dampingG = mix(0.99, 0.95, viscosityG);
  let dampingB = mix(0.99, 0.95, viscosityB);
  
  velR = velR * dampingR;
  velG = velG * dampingG;
  velB = velB * dampingB;
  
  // Clamp velocities
  velR = clamp(velR, vec2<f32>(-0.5), vec2<f32>(0.5));
  velG = clamp(velG, vec2<f32>(-0.5), vec2<f32>(0.5));
  velB = clamp(velB, vec2<f32>(-0.5), vec2<f32>(0.5));
  
  // Store velocity state
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(velR, velG));
  textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(velB, 0.0, 0.0));
  
  // Advect each color channel separately
  let advectedR_uv = advect(uv, velR, texelSize);
  let advectedG_uv = advect(uv, velG, texelSize);
  let advectedB_uv = advect(uv, velB, texelSize);
  
  // Sample source at advected positions
  let colorR = textureSampleLevel(readTexture, u_sampler, advectedR_uv, 0.0).r;
  let colorG = textureSampleLevel(readTexture, u_sampler, advectedG_uv, 0.0).g;
  let colorB = textureSampleLevel(readTexture, u_sampler, advectedB_uv, 0.0).b;
  
  // Combine with subtle evaporation effect
  var finalR = colorR * (1.0 - evaporationR);
  var finalG = colorG * (1.0 - evaporationG);
  var finalB = colorB * (1.0 - evaporationB);
  
  // Add subtle iridescence based on velocity differences
  let velDiff = length(velR - velG) + length(velG - velB) + length(velB - velR);
  let iridescence = velDiff * 2.0;
  finalR = finalR + sin(iridescence * 6.283 + 0.0) * 0.05;
  finalG = finalG + sin(iridescence * 6.283 + 2.094) * 0.05;
  finalB = finalB + sin(iridescence * 6.283 + 4.188) * 0.05;
  
  // Output
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalR, finalG, finalB, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
