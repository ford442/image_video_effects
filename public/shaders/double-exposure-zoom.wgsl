// ═══════════════════════════════════════════════════════════════════
//  Double Exposure Zoom
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
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

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouse = u.zoom_config.yz;

  let prevState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let bassRaw = plasmaBuffer[0].x;
  let k = select(0.15, 0.8, bassRaw > prevState.r);
  let bassSmooth = mix(prevState.r, bassRaw, k);
  let smoothMouse = mix(prevState.gb, mouse, vec2<f32>(0.08));

  let rot = (u.zoom_params.x - 0.5) * 6.28318;
  let zoomRaw = u.zoom_params.y;
  let edgeFade = u.zoom_params.z;
  let audioReact = u.zoom_params.w;

  let mouseDist = length(mouse - 0.5);
  let zoomMod = zoomRaw + mouseDist * 0.3;
  let zoom = clamp(pow(2.0, (zoomMod - 0.5) * 4.0 + bassSmooth * audioReact * 2.0 + mids * 0.1), 0.01, 100.0);

  let col1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  var uv2 = uv - smoothMouse;
  uv2.x = uv2.x * aspect;
  let c = cos(rot);
  let s = sin(rot);
  uv2 = vec2<f32>(uv2.x * c - uv2.y * s, uv2.x * s + uv2.y * c);
  uv2.x = uv2.x / aspect;
  uv2 = uv2 / zoom;
  uv2 = uv2 + smoothMouse;

  let col2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let edgeDist = min(min(uv2.x, 1.0 - uv2.x), min(uv2.y, 1.0 - uv2.y));
  let edgeMask = smoothstep(0.0, 0.05 + edgeFade * 0.45, edgeDist);
  let col2Faded = vec4<f32>(col2.rgb, col2.a * edgeMask);

  let blendedRGB = 1.0 - (1.0 - col1.rgb) * (1.0 - col2Faded.rgb);
  let blendAlpha = 1.0 - (1.0 - col1.a) * (1.0 - col2Faded.a);

  let prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let trailAmt = 0.15 + bassSmooth * audioReact * 0.25 + treble * 0.05;
  let finalRGB = mix(blendedRGB, prevFrame.rgb, trailAmt);
  let finalAlpha = mix(blendAlpha, prevFrame.a * 0.96, trailAmt);
  let luminance = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(finalAlpha, luminance * 0.5 + 0.3, edgeMask * 0.3), 0.0, 1.0);
  let finalColor = vec4<f32>(finalRGB, alpha);

  let isOrigin = select(0.0, 1.0, global_id.x == 0u && global_id.y == 0u);
  let statePixel = vec4<f32>(bassSmooth, smoothMouse.x, smoothMouse.y, 0.0);
  let dataAVal = mix(finalColor, statePixel, isOrigin);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, vec2<i32>(global_id.xy), dataAVal);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
