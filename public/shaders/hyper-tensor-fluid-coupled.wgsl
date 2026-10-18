// ═══════════════════════════════════════════════════════════════════
//  Hyper Tensor Fluid + Mouse Coupling
//  Category: simulation
//  Features: advanced-hybrid, tensor-field, navier-stokes, mouse-driven, fluid-coupling, interactive
//  Complexity: Very High
//  Chunks From: hyper-tensor-fluid, mouse-fluid-coupling
//  Created: 2026-04-18
//  By: Agent CB-4 - Mouse Physics Injector
//  Upgraded: 2026-10-18
//  Ideas: Weissenberg pile-up on tensor edges; die swell downstream of an edge
//  A packing: raw (velocity.xy, vorticity, density). Pixel (0,0) stashes the pointer. Display ACES is writeTexture only.
// ═══════════════════════════════════════════════════════════════════
//  Tensor-field fluid with viscous mouse stirring. Mouse acts as a
//  stirring rod injecting velocity and vorticity. Click ripples spawn
//  radial fluid bursts. Alpha stores fluid density/thickness.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn loadState(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn stateBilinear(uv: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
  let q = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * res - 0.5;
  let p = vec2<i32>(floor(q));
  let f = fract(q);
  let dims = vec2<i32>(res);
  let a = mix(loadState(p, dims), loadState(p + vec2<i32>(1, 0), dims), f.x);
  let b = mix(loadState(p + vec2<i32>(0, 1), dims), loadState(p + vec2<i32>(1, 1), dims), f.x);
  return mix(a, b, f.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixel = 1.0 / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let aspect = resolution.x / resolution.y;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioReactivity = 1.0 + bass * 0.3;

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
  let edgeStrength = clamp((tensor[0][0] + tensor[1][1]) * 48.0, 0.0, 1.0);

  // Read previous velocity and density from exact dataTextureC loads.
  let prevState = stateBilinear(uv, resolution);
  let prevVel = prevState.xy;

  // Advect velocity (semi-Lagrangian)
  let backUV = clamp(uv - prevVel * pixel * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let backState = stateBilinear(backUV, resolution);
  var velocity = backState.xy * viscosity;
  var dens = backState.w * viscosity;

  // Apply tensor field influence
  velocity = velocity + flowDirection * tensorStrength * 0.01;

  // Idea: Weissenberg pile-up — density climbs the image contour.
  dens = dens + edgeStrength * tensorStrength * 0.12 * (0.65 + mids * 0.35);

  // Idea: die swell — the jet widens along the minor axis once it leaves the edge.
  let aheadUV = clamp(uv + flowDirection * pixel * 6.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let tensorAhead = calculateStructureTensor(aheadUV, pixel);
  let edgeAhead = clamp((tensorAhead[0][0] + tensorAhead[1][1]) * 48.0, 0.0, 1.0);
  let swell = max(edgeStrength - edgeAhead, 0.0);
  velocity = velocity + eigen.zw * swell * tensorStrength * 0.05;

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
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0 * (0.7 + treble * 0.6);
  color = color + vec3<f32>(0.9, 0.95, 1.0) * specular;

  color = acesToneMap(max(color, vec3<f32>(0.0)));

  // Alpha = fluid density
  let alpha = mix(0.7, 1.0, flowIntensity + dens * 0.3);

  textureStore(writeTexture, id, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - flowIntensity * 0.2), 0.0, 0.0, 0.0));
}
