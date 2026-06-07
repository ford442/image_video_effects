// ═══════════════════════════════════════════════════════════════════
//  Hexagon Mosaic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let coords = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / u.config.zw;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let gridScale = mix(10.0, 150.0, max(u.zoom_params.x, 0.001));
  let focusRadius = clamp(u.zoom_params.y * 0.8, 0.0, 1.0);
  let edgeHardness = clamp(u.zoom_params.z, 0.0, 1.0);
  let satBoost = clamp(u.zoom_params.w * (1.0 + bass * 0.3 + mids * 0.15), 0.0, 3.0);

  let aspect = u.config.z / max(u.config.w, 0.001);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let r = vec2<f32>(1.0, 1.7320508);
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

  let center = select(centerB, centerA, distA < distB);
  let centerUV = clamp(center / gridScale / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));

  var hexColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
  let origColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let gray = dot(hexColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  hexColor = mix(vec4<f32>(gray, gray, gray, hexColor.a), hexColor, 1.0 + satBoost);

  let mousePos = u.zoom_config.yz;
  let d = distance(uv * aspectVec, mousePos * aspectVec);

  let edgeWidth = max((1.0 - edgeHardness) * 0.2, 0.001);
  let mask = smoothstep(focusRadius, focusRadius + edgeWidth, d);
  let clampedMask = clamp(mask, 0.0, 1.0);

  var finalColor = mix(origColor, hexColor, clampedMask);

  let origLum = dot(origColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let hexLum = dot(hexColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let finalAlpha = mix(clamp(origLum, 0.3, 1.0), clamp(hexLum, 0.5, 1.0), clampedMask);
  finalColor.a = clamp(finalAlpha, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coords, finalColor);
  textureStore(dataTextureA, coords, finalColor);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
