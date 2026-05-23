// ═══════════════════════════════════════════════════════════════════
//  Hexagon Mosaic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=TileSize, y=Radius, z=EdgeHardness, w=SaturationBoost
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;

  // Parameters with randomization guards
  let gridScale = mix(10.0, 150.0, max(u.zoom_params.x, 0.001));   // Param 1: Tile Size (Frequency)
  let focusRadius = clamp(u.zoom_params.y * 0.8, 0.0, 1.0);         // Param 2: Radius
  let edgeHardness = clamp(u.zoom_params.z, 0.0, 1.0);              // Param 3: Edge Hardness
  let satBoost = clamp(u.zoom_params.w * (1.0 + bass * 0.3), 0.0, 3.0); // Param 4: Saturation Boost (audio-reactive)

  // Aspect ratio correction for hexagonal grid
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);

  // Hex Grid Math
  let r = vec2<f32>(1.0, 1.7320508); // 1, sqrt(3)
  let h = r * 0.5;

  let uvScaled = uv * aspectVec * gridScale;

  let uvA = uvScaled / r;
  let idA = floor(uvA + 0.5);
  let uvB = (uvScaled - h) / r;
  let idB = floor(uvB + 0.5);

  let centerA = idA * r;
  let centerB = idB * r + h;

  let distA = distance(uvScaled, centerA);
  let distB = distance(uvScaled, centerB);

  // Find closest center
  var center = select(centerB, centerA, distA < distB);

  // Map back to UV space (0-1)
  let centerUV = center / gridScale / aspectVec;

  // Sample texture at hex center
  var hexColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
  let origColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Saturation Boost (Simple)
  let gray = dot(hexColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  hexColor = mix(vec4<f32>(gray, gray, gray, hexColor.a), hexColor, 1.0 + satBoost);

  // Mouse Interaction
  var mousePos = u.zoom_config.yz;
  let d = distance(uv * aspectVec, mousePos * aspectVec);

  // Calculate mask: 0 = Clear (near mouse), 1 = Hex (far)
  let edgeWidth = max((1.0 - edgeHardness) * 0.2, 0.001);
  let mask = smoothstep(focusRadius, focusRadius + edgeWidth, d);
  let clampedMask = clamp(mask, 0.0, 1.0);

  var finalColor = mix(origColor, hexColor, clampedMask);

  // Meaningful alpha: luminance-based blended by effect intensity
  let origLum = dot(origColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let hexLum = dot(hexColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let finalAlpha = mix(clamp(origLum, 0.3, 1.0), clamp(hexLum, 0.5, 1.0), clampedMask);
  finalColor.a = clamp(finalAlpha, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Passthrough depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
