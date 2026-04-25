// ═══════════════════════════════════════════════════════════════════
//  mouse-kaleidoscope-tunnel
//  Category: interactive-mouse
//  Features: mouse-driven, kaleidoscope, tunnel
//  Complexity: High
//  Chunks From: chunk-library.md (kaleidoscope, rot2)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  The mouse is the center of an infinite kaleidoscope tunnel.
//  Moving the mouse spirals the tunnel. Distance from mouse
//  controls mirror count and z-depth perspective.
//  Alpha channel stores tunnel depth layer.
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

// ═══ CHUNK: rot2 (from kaleidoscope.wgsl) ═══
fn rot2(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// ═══ CHUNK: kaleidoscope (from kaleidoscope.wgsl) ═══
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
  let angle = atan2(uv.y, uv.x);
  let radius = length(uv);
  let segmentAngle = 6.28318 / segments;
  let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
  return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let tunnelSpeed = mix(0.2, 2.0, u.zoom_params.x);
  let segmentBase = mix(3.0, 16.0, u.zoom_params.y);
  let spiralTwist = mix(0.0, 3.0, u.zoom_params.z);
  let zoomDepth = mix(0.3, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Center coordinates on mouse
  var centered = (uv - mousePos) * vec2<f32>(aspect, 1.0);

  // Convert to polar
  var polar = vec2<f32>(length(centered), atan2(centered.y, centered.x));

  // Tunnel depth: distance from center maps to z
  let tunnelZ = polar.x * zoomDepth;
  let depthLayer = fract(tunnelZ - time * tunnelSpeed * 0.2);

  // Spiral twist based on depth
  polar.y = polar.y + depthLayer * spiralTwist * 6.28318;

  // Kaleidoscope fold count increases with distance (more mirrors further out)
  let segments = segmentBase + floor(polar.x * 10.0);
  let kUV = kaleidoscope(vec2<f32>(cos(polar.y), sin(polar.y)) * polar.x, segments);

  // Perspective projection for tunnel feel
  let perspective = 1.0 / (depthLayer + 0.1);
  var sampleUV = kUV * perspective * 0.5 + 0.5;

  // Ripple effects: clicks create expanding kaleidoscope bursts
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let ring = smoothstep(0.05, 0.0, abs(rDist - elapsed * 0.15)) * exp(-elapsed * 0.5);
      sampleUV = sampleUV + vec2<f32>(sin(elapsed * 5.0 + f32(i)), cos(elapsed * 5.0 + f32(i))) * ring * 0.1;
    }
  }

  // Sample with rotation for extra motion
  let rotAngle = time * tunnelSpeed * 0.1 + mouseDown * 2.0;
  sampleUV = rot2(rotAngle) * (sampleUV - 0.5) + 0.5;

  // Multiple depth layers for parallax
  var color = vec3<f32>(0.0);
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let layerOffset = f32(layer) * 0.33;
    let layerUV = fract(sampleUV + vec2<f32>(layerOffset * 0.1, layerOffset * 0.15));
    let layerColor = textureSampleLevel(readTexture, u_sampler, layerUV, 0.0).rgb;
    let layerWeight = 1.0 / (1.0 + f32(layer));
    color = color + layerColor * layerWeight;
  }
  color = color / (1.0 + 0.5 + 0.33);

  // Depth fog: darker further in tunnel
  let fog = 1.0 - smoothstep(0.0, 0.8, depthLayer);
  color = color * (0.5 + 0.5 * fog);

  // Glow at tunnel rings
  let ringGlow = smoothstep(0.02, 0.0, abs(depthLayer - 0.5)) * 0.3;
  color = color + vec3<f32>(0.6, 0.8, 1.0) * ringGlow;

  // Alpha = tunnel depth layer
  let alpha = clamp(depthLayer, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
