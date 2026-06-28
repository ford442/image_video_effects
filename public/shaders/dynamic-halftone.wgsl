// ═══════════════════════════════════════════════════════════════════
//  Dynamic Halftone
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Phase A Upgrade Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=InfluenceRadius, z=Contrast, w=EdgeSharpness
  ripples: array<vec4<f32>, 50>,
};

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.49, 0.47) +
         vec3<f32>(0.48, 0.43, 0.38) *
         cos(6.28318 * (vec3<f32>(1.0, 0.76, 0.48) * t + vec3<f32>(0.03, 0.28, 0.56)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coords = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  var mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let density = max(20.0 + u.zoom_params.x * 100.0, 0.001);
  let influenceRadius = u.zoom_params.y * (1.0 + bass * 0.2);
  let contrast = max(0.5 + u.zoom_params.z * 2.0, 0.001);

  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let scale = vec2<f32>(density, density);

  let gridUV = aspectUV * scale;
  let cellIndex = floor(gridUV);
  let cellLocalUV = fract(gridUV);
  let cellCenter = vec2<f32>(0.5, 0.5);

  let cellCenterUV = (cellIndex + cellCenter) / scale;
  let sampleUV = vec2<f32>(cellCenterUV.x / aspect, cellCenterUV.y);

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let distToMouse = length((sampleUV - mouse) * vec2<f32>(aspect, 1.0));
  let influence = smoothstep(influenceRadius, 0.0, distToMouse);

  var radius = luma * 0.5;
  radius = clamp(radius * (1.0 + influence * 0.8), 0.0, 0.6);

  let edgeSharpnessFactor = mix(2.0, 0.1, clamp(u.zoom_params.w, 0.0, 1.0));
  let edgeWidth = 0.05 * (1.0 + influence) * max(edgeSharpnessFactor, 0.001);

  let centeredCell = cellLocalUV - cellCenter;
  let plateAngle = sin(time * 0.17 + cellIndex.x * 0.07) * 0.22 + influence * 0.45;
  let rot = mat2x2<f32>(cos(plateAngle), -sin(plateAngle), sin(plateAngle), cos(plateAngle));
  let ovalCell = rot * centeredCell * vec2<f32>(1.0 + influence * 0.55, 1.0 - influence * 0.22);
  let distToDotCenter = length(ovalCell);
  let dot_alpha = 1.0 - smoothstep(radius - edgeWidth, radius + edgeWidth, distToDotCenter);
  let inkRim = smoothstep(radius + edgeWidth * 2.2, radius - edgeWidth * 0.25, abs(distToDotCenter - radius));
  let paper = 0.88 + (ign(vec2<f32>(global_id.xy) * 0.37 + time) - 0.5) * 0.08;

  var hdr = mix(vec3<f32>(0.022, 0.020, 0.018) * paper, color.rgb * paper, dot_alpha);
  hdr = pow(max(hdr, vec3<f32>(0.0)), vec3<f32>(contrast));
  let spectralInk = palette(luma + time * 0.03 + mids * 0.18 + ign(cellIndex));
  hdr = hdr + spectralInk * inkRim * (0.30 + treble * 0.75) * (0.35 + luma);
  hdr = hdr + vec3<f32>(1.0, 0.82, 0.45) * pow(influence, 2.6) * dot_alpha * (0.22 + bass * 0.45);

  let radial = length(uv - vec2<f32>(0.5)) * 1.414;
  hdr = hdr * mix(1.08, 0.68, smoothstep(0.45, 1.0, radial));
  let dither = (ign(vec2<f32>(global_id.xy) + time * 11.0) - 0.5) / 255.0;
  let finalColor = clamp(aces(hdr * 1.22) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

  // Alpha encodes dot coverage: filled dots = high weight, empty cells = transparent
  let hdrLuma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  let alpha = clamp(0.12 + dot_alpha * (0.42 + luma * 0.32) + pow(max(0.0, hdrLuma - 0.55), 2.0) * 2.4, 0.0, 1.0);

  textureStore(writeTexture, coords, vec4<f32>(finalColor * alpha, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(finalColor * alpha, alpha));
}
