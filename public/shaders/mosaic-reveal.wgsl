// ═══════════════════════════════════════════════════════════════════
//  mosaic-reveal — Batch D Upgrade
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, mosaic, interactive-reveal,
//            mouse-driven, hex-grid, flood-fill-reveal, audio-reactive
//  Upgraded: 2026-05-10
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

fn hash12(p: vec2<f32>) -> f32 {
  let a = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(a) * 43758.5453);
}

fn hexCoord(uv: vec2<f32>, size: f32) -> vec2<f32> {
  let s = vec2<f32>(1.0, 1.7320508);
  let h = s * 0.5;
  let a = mod(uv, s) - h;
  let b = mod(uv - h, s) - h;
  let g = select(a, b, dot(a, a) > dot(b, b));
  return (uv - g) / size;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let aspectVec = vec2<f32>(res.x / res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;

  // Parameters
  let cellSize = mix(15.0, 150.0, u.zoom_params.x);
  let revealSpeed = u.zoom_params.y * 2.0 + 0.2;
  let edgeGlow = u.zoom_params.z;
  let gridType = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouseDist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

  // Hex or square grid selection
  let isHex = gridType > 0.5;
  var tileUV: vec2<f32>;
  var uvPix: vec2<f32>;
  var uvCenter: vec2<f32>;
  var fracTile: vec2<f32>;

  if (isHex) {
    let hex = hexCoord(uv * cellSize, 1.0);
    tileUV = hex;
    uvPix = floor(hex) / cellSize;
    uvCenter = uvPix + (0.5 / cellSize);
    fracTile = fract(hex);
  } else {
    tileUV = uv * cellSize;
    uvPix = floor(tileUV) / cellSize;
    uvCenter = uvPix + (0.5 / cellSize);
    fracTile = fract(tileUV);
  }

  let colMosaic = textureSampleLevel(readTexture, non_filtering_sampler, uvCenter, 0.0).rgb;
  let colFull = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Flood-fill reveal from mouse position with time + audio pulse
  let bassPulse = 1.0 + bass * 0.3;
  let revealRadius = fract(time * revealSpeed * bassPulse) * 0.8;
  let revealMask = 1.0 - smoothstep(revealRadius - 0.05, revealRadius + 0.05, mouseDist);

  // Edge glow around reveal boundary
  let edgeMask = smoothstep(revealRadius - 0.08, revealRadius - 0.02, mouseDist)
               * smoothstep(revealRadius + 0.08, revealRadius + 0.02, mouseDist);

  var color = mix(colMosaic, colFull, revealMask);

  // Golden transition rim glow
  color = color + vec3<f32>(1.0, 0.78, 0.25) * edgeMask * edgeGlow * 2.0;

  // Atmospheric depth haze
  let haze = depth * 0.3;
  color = mix(color, color * vec3<f32>(0.6, 0.75, 1.0) + vec3<f32>(0.1, 0.14, 0.2), haze);

  // Subtle vignette
  let vig = 1.0 - dot((uv - 0.5) * 1.3, (uv - 0.5) * 1.3);
  color = color * mix(0.85, 1.0, clamp(vig, 0.0, 1.0));

  // Alpha: reveal-mask based
  let alpha = mix(0.7, 1.0, revealMask);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
