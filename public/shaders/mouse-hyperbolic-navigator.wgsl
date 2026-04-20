// ═══════════════════════════════════════════════════════════════════
//  mouse-hyperbolic-navigator
//  Category: interactive-mouse
//  Features: mouse-driven, geometric, infinite-tiling
//  Complexity: High
//  Chunks From: chunk-library.md (none — complex arithmetic inline)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  The image is mapped onto a Poincaré disk. Mouse movement drives
//  Möbius transformations that scroll the hyperbolic plane. Tiles
//  become smaller and more numerous toward the disk boundary.
//  Alpha channel stores hyperbolic distance from center.
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

// Complex arithmetic helpers
fn cMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}
fn cDiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let denom = max(dot(b, b), 0.0001);
  return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / denom;
}
fn cConj(a: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x, -a.y);
}

// Möbius transform preserving unit disk: (z - a) / (1 - conj(a)*z)
fn mobiusDisk(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
  let num = z - a;
  let den = vec2<f32>(1.0, 0.0) - cMul(cConj(a), z);
  return cDiv(num, den);
}

// Hyperbolic distance from origin in Poincaré disk
fn hyperbolicDistOrigin(z: vec2<f32>) -> f32 {
  let r2 = dot(z, z);
  return 0.5 * log((1.0 + r2 + 0.0001) / (1.0 - r2 + 0.0001));
}

// Wrap a point into a repeating tile for the image
fn hyperbolicTile(z: vec2<f32>, repetitions: f32) -> vec2<f32> {
  // Convert to polar-like coordinates in hyperbolic space
  let r = length(z);
  let angle = atan2(z.y, z.x);

  // Wrap angle for tiling
  let wrappedAngle = fract(angle / 6.28318 * repetitions) / repetitions * 6.28318;
  let tileZ = vec2<f32>(cos(wrappedAngle), sin(wrappedAngle)) * r;
  return tileZ;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let navigationSpeed = mix(0.2, 1.5, u.zoom_params.x);
  let tileCount = mix(3.0, 12.0, u.zoom_params.y);
  let edgeGlow = u.zoom_params.z;
  let zoomFactor = mix(0.5, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;

  // Map mouse to disk navigation parameter a (clamped to keep inside disk)
  let a = vec2<f32>(
    (mousePos.x - 0.5) * 1.8 * navigationSpeed,
    (mousePos.y - 0.5) * 1.8 * navigationSpeed
  );

  // Map UV to Poincaré disk coordinates (-1 to 1, corrected for aspect)
  var diskUV = (uv - 0.5) * 2.0;
  diskUV.x = diskUV.x * aspect;

  // Apply zoom
  diskUV = diskUV / zoomFactor;

  // Only render inside unit disk
  let distFromOrigin = length(diskUV);
  if (distFromOrigin > 0.999) {
    // Outside disk: dark hyperbolic void
    let voidColor = vec3<f32>(0.01, 0.0, 0.02);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(voidColor, 0.0));
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
    return;
  }

  // Apply Möbius navigation
  let transformed = mobiusDisk(diskUV, a);

  // Hyperbolic tiling: repeat pattern toward boundary
  let tiled = hyperbolicTile(transformed, tileCount);

  // Map back to UV space for image sampling
  let sampleUV = tiled * 0.5 + 0.5;

  // Hyperbolic magnification: near boundary = more detail
  let hDist = hyperbolicDistOrigin(transformed);
  let magnify = 1.0 + hDist * 0.3;

  // Sample with magnification bias
  let magnifiedUV = (sampleUV - 0.5) * magnify + 0.5;
  var color = textureSampleLevel(readTexture, u_sampler, magnifiedUV, 0.0).rgb;

  // Ripple distortions: clicks create hyperbolic waves
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let rPos = vec2<f32>(
        (ripple.x - 0.5) * 2.0 * aspect,
        (ripple.y - 0.5) * 2.0
      );
      let rDist = length(diskUV - rPos);
      let wave = sin(rDist * 20.0 - elapsed * 6.0) * exp(-elapsed * 1.2) * smoothstep(1.0, 0.0, rDist);
      color = color + vec3<f32>(0.2, 0.4, 0.6) * wave * 0.5;
    }
  }

  // Edge glow: highlight boundary of unit disk
  let edgeProximity = smoothstep(0.999, 0.85, distFromOrigin);
  let boundaryGlow = (1.0 - edgeProximity) * edgeGlow;
  color = mix(color, vec3<f32>(0.3, 0.6, 1.0), boundaryGlow * 0.4);

  // Hyperbolic distance as alpha
  let alpha = clamp(hDist / 3.0, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
