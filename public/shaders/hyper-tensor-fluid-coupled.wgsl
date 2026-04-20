// ═══════════════════════════════════════════════════════════════════
//  Hyper Tensor Fluid + Mouse Coupling
//  Category: simulation
//  Features: advanced-hybrid, tensor-field, navier-stokes, mouse-driven, fluid-coupling, interactive
//  Complexity: Very High
//  Chunks From: hyper-tensor-fluid, mouse-fluid-coupling
//  Created: 2026-04-18
//  By: Agent CB-4 - Mouse Physics Injector
// ═══════════════════════════════════════════════════════════════════
//  Tensor-field fluid with viscous mouse stirring. Mouse acts as a
//  stirring rod injecting velocity and vorticity. Click ripples spawn
//  radial fluid bursts. Alpha stores fluid density/thickness.
// ═══════════════════════════════════════════════════════════════════

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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: fbm2 (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

// ═══ TENSOR FIELD CALCULATION ═══
fn calculateStructureTensor(uv: vec2<f32>, pixel: vec2<f32>) -> mat2x2<f32> {
  let l = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let lum = dot(l, vec3<f32>(0.299, 0.587, 0.114));

  let right = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let left = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let up = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let down = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

  let dx = (right - left) * 0.5;
  let dy = (up - down) * 0.5;

  return mat2x2<f32>(
    dx * dx, dx * dy,
    dy * dx, dy * dy
  );
}

fn calculateTensorEigen(tensor: mat2x2<f32>) -> vec4<f32> {
  let a = tensor[0][0];
  let b = tensor[0][1];
  let d = tensor[1][1];

  let trace = a + d;
  let det = a * d - b * b;
  let discriminant = sqrt(max(trace * trace - 4.0 * det, 0.0));

  let lambda1 = (trace + discriminant) * 0.5;
  let lambda2 = (trace - discriminant) * 0.5;

  let vec1 = normalize(vec2<f32>(lambda1 - d, b + 0.0001));
  let vec2 = normalize(vec2<f32>(-vec1.y, vec1.x));

  return vec4<f32>(vec1, vec2);
}

fn sampleVelocity(tex: texture_2d<f32>, uv: vec2<f32>) -> vec2<f32> {
  return textureSampleLevel(tex, u_sampler, uv, 0.0).xy;
}

fn sampleDensity(tex: texture_2d<f32>, uv: vec2<f32>) -> f32 {
  return textureSampleLevel(tex, u_sampler, uv, 0.0).a;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixel = 1.0 / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let aspect = resolution.x / resolution.y;

  let audioOverall = u.zoom_config.x;
  let audioReactivity = 1.0 + audioOverall * 0.3;

  // Parameters
  let tensorStrength = mix(0.0, 2.0, u.zoom_params.x);
  let viscosity = mix(0.1, 0.99, u.zoom_params.y);
  let turbulence = mix(0.0, 0.5, u.zoom_params.z);
  let advectionSpeed = mix(0.5, 3.0, u.zoom_params.w);

  let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
  let colorShift = u.zoom_params.z;
  let vortexStrength = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Calculate structure tensor from image
  let tensor = calculateStructureTensor(uv, pixel);
  let eigen = calculateTensorEigen(tensor);

  let flowDirection = eigen.xy;
  let edgeStrength = length(eigen.xy);

  // Read previous velocity and density from dataTextureC
  let prevVel = sampleVelocity(dataTextureC, uv);
  let prevDens = sampleDensity(dataTextureC, uv);

  // Advect velocity (semi-Lagrangian)
  let backUV = uv - prevVel * pixel * 2.0;
  var velocity = sampleVelocity(dataTextureC, backUV) * viscosity;
  var dens = sampleDensity(dataTextureC, backUV) * viscosity;

  // Apply tensor field influence
  velocity = velocity + flowDirection * tensorStrength * 0.01;

  // Add FBM turbulence
  let turb = fbm2(uv * 8.0 + time * 0.1 * audioReactivity, 4);
  velocity = velocity + vec2<f32>(
    fbm2(uv * 4.0 + vec2<f32>(time * 0.1 * audioReactivity, 0.0), 3) - 0.5,
    fbm2(uv * 4.0 + vec2<f32>(0.0, time * 0.1 * audioReactivity), 3) - 0.5
  ) * turbulence;

  // Mouse force: stirring rod
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let influence = smoothstep(mouseRadius, 0.0, dist);

  // Add mouse velocity as body force
  velocity = velocity + mouseVel * influence * 0.5;

  // Vortex force: perpendicular to mouse motion
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  velocity = velocity + vortexDir * influence * vortexStrength * mouseSpeed;

  // Click ripples = fluid injection points
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      velocity = velocity + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  // Damping at edges
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  velocity = velocity * edgeDamp;

  // Clamp to prevent explosion
  velocity = clamp(velocity, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  // Store velocity (RG) and density (A) for next frame
  // B stores vorticity approximation
  let vorticity = velocity.x - velocity.y;
  if (global_id.x != 0u || global_id.y != 0u) {
    textureStore(dataTextureA, id, vec4<f32>(velocity, vorticity, dens));
  }

  // Advect color along flow field
  let dt = 0.016 * advectionSpeed;
  let advectedUV = uv + velocity * dt;

  var color = textureSampleLevel(readTexture, u_sampler, clamp(advectedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  // Depth-aware distortion
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = 1.0 - depth * 0.5;

  // Apply flow-based color modulation
  let flowIntensity = length(velocity) * 5.0;
  color = mix(color, color * (1.0 + flowIntensity), edgeStrength * 2.0);

  // Add iridescent highlights along flow
  let hueShift = flowIntensity * 0.1 + time * 0.05 * audioReactivity;
  let highlight = vec3<f32>(
    0.5 + 0.5 * cos(hueShift * 6.28),
    0.5 + 0.5 * cos(hueShift * 6.28 + 2.09),
    0.5 + 0.5 * cos(hueShift * 6.28 + 4.18)
  );
  color = color + highlight * flowIntensity * 0.3 * depthFactor;

  // Color absorption: thicker fluid = warmer tint
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * colorShift);
  color = color * fluidTint;

  // Specular highlight on fluid surface near mouse
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  color = color + vec3<f32>(0.9, 0.95, 1.0) * specular;

  // Alpha = fluid density
  let alpha = mix(0.7, 1.0, flowIntensity + dens * 0.3);

  textureStore(writeTexture, id, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - flowIntensity * 0.2), 0.0, 0.0, 0.0));
}
