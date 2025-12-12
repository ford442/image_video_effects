// 2D Wave Equation (Ripple Tank) Simulation
// Discrete Laplacian with 5x5 kernel for stable wave propagation

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // current height + velocity
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // previous height + temp
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous state
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=WaveSpeed, y=Damping, z=SourceStrength, w=BoundaryReflect
  ripples: array<vec4<f32>, 50>,
};

// Sum of absolute positive weights in 5x5 Laplacian kernel: 1+2+4+2+1+4+4+4+2+4+2+1+2+4+2+1 = 24
// Used to normalize the Laplacian computation to prevent numerical instability
const LAPLACIAN_5X5_NORM: f32 = 24.0;

// 5x5 Laplacian kernel for better stability
fn laplacian5x5(uv: vec2<f32>, texelSize: vec2<f32>) -> f32 {
  // 5x5 Laplacian kernel weights (center weight = -24 balances positive neighbors)
  let kernel = array<f32, 25>(
    0.0, 0.0, 1.0, 0.0, 0.0,
    0.0, 2.0, 4.0, 2.0, 0.0,
    1.0, 4.0, -24.0, 4.0, 1.0,
    0.0, 2.0, 4.0, 2.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0
  );
  
  var sum = 0.0;
  var idx = 0;
  for (var dy = -2; dy <= 2; dy = dy + 1) {
    for (var dx = -2; dx <= 2; dx = dx + 1) {
      let sampleUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
      let h = textureSampleLevel(dataTextureC, non_filtering_sampler, sampleUV, 0.0).r;
      sum = sum + h * kernel[idx];
      idx = idx + 1;
    }
  }
  return sum / LAPLACIAN_5X5_NORM;
}

// 3x3 Laplacian for faster computation
fn laplacian3x3(uv: vec2<f32>, texelSize: vec2<f32>) -> f32 {
  let center = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let left = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-1.0, 0.0) * texelSize, 0.0).r;
  let right = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(1.0, 0.0) * texelSize, 0.0).r;
  let up = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -1.0) * texelSize, 0.0).r;
  let down = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, 1.0) * texelSize, 0.0).r;
  
  return (left + right + up + down - 4.0 * center);
}

// Compute normals from height field for lighting
fn computeNormal(uv: vec2<f32>, texelSize: vec2<f32>) -> vec3<f32> {
  let left = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-1.0, 0.0) * texelSize, 0.0).r;
  let right = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(1.0, 0.0) * texelSize, 0.0).r;
  let up = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -1.0) * texelSize, 0.0).r;
  let down = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, 1.0) * texelSize, 0.0).r;
  
  let dx = (right - left) * 2.0;
  let dy = (down - up) * 2.0;
  
  return normalize(vec3<f32>(-dx, -dy, 0.1));
}

// HSV to RGB for rainbow coloring
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let h = hsv.x * 6.0;
  let s = hsv.y;
  let v = hsv.z;
  
  let c = v * s;
  let x = c * (1.0 - abs(h % 2.0 - 1.0));
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
  
  // Parameters
  let waveSpeed = mix(0.1, 0.5, u.zoom_params.x);
  let damping = mix(0.98, 0.999, u.zoom_params.y);
  let sourceStrength = mix(0.1, 1.0, u.zoom_params.z);
  let boundaryReflect = mix(0.0, 0.95, u.zoom_params.w);
  
  // Read current state: r=height, g=velocity, b=previous height, a=source intensity
  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var height = state.r;
  var velocity = state.g;
  var prevHeight = state.b;
  
  // Compute Laplacian (wave propagation)
  let laplacian = laplacian3x3(uv, texelSize);
  
  // Wave equation: acceleration = c² * laplacian
  let c2 = waveSpeed * waveSpeed;
  let acceleration = c2 * laplacian;
  
  // Verlet-like integration
  velocity = velocity + acceleration;
  velocity = velocity * damping;  // Apply damping
  
  prevHeight = height;
  height = height + velocity;
  
  // Inject waves from mouse position
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDistSq = dot(uv - mouse, uv - mouse);
  let mouseRadius = 0.02;
  if (mouseDistSq < mouseRadius * mouseRadius) {
    let wave = sin(time * 10.0) * sourceStrength * 0.5;
    height = height + wave * (1.0 - sqrt(mouseDistSq) / mouseRadius);
  }
  
  // Inject waves from ripples (clicks)
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 0.5) {
        let distSq = dot(uv - ripple.xy, uv - ripple.xy);
        let radius = 0.015;
        if (distSq < radius * radius) {
          let strength = (1.0 - rippleAge / 0.5) * sourceStrength;
          height = height + strength * (1.0 - sqrt(distSq) / radius);
        }
      }
    }
  }
  
  // Boundary conditions
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeFade = smoothstep(0.0, 0.05, edgeDist);
  
  // Absorbing/reflecting boundary
  height = height * mix(1.0, edgeFade, 1.0 - boundaryReflect);
  velocity = velocity * mix(1.0, edgeFade, 1.0 - boundaryReflect);
  
  // Clamp to prevent instability
  height = clamp(height, -2.0, 2.0);
  velocity = clamp(velocity, -1.0, 1.0);
  
  // Store wave state
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(height, velocity, prevHeight, 1.0));
  
  // Compute visualization
  let normal = computeNormal(uv, texelSize);
  
  // Refraction-based displacement
  let refractOffset = normal.xy * 0.03;
  let refractedUV = uv + refractOffset;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0);
  
  // Depth-based coloring
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Phase-based rainbow coloring
  let phase = atan2(velocity, height);
  let hue = (phase / 6.283185 + 0.5);
  let amplitude = sqrt(height * height + velocity * velocity);
  let waveColor = hsv2rgb(vec3<f32>(hue, 0.7, amplitude * 2.0 + 0.2));
  
  // Lighting
  let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
  let diffuse = max(dot(normal, lightDir), 0.0);
  let specular = pow(max(dot(reflect(-lightDir, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 32.0);
  
  // Blend source with wave effects
  var finalColor = sourceColor.rgb;
  finalColor = finalColor + waveColor * amplitude * 0.5;
  finalColor = finalColor * (0.5 + diffuse * 0.5);
  finalColor = finalColor + vec3<f32>(specular * 0.3);
  
  // Caustic-like bright spots
  let caustic = pow(abs(laplacian) * 5.0, 2.0);
  finalColor = finalColor + vec3<f32>(caustic * 0.2);
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
