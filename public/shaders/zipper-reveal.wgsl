// ═══════════════════════════════════════════════════════════════════
//  Zipper Reveal v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: zipper-reveal
//  Created: 2026-05-30
//  Upgraded: 2026-05-30
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
  let s = sin(a);
  let c = cos(a);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fabric_weave(uv: vec2<f32>, scale: f32) -> f32 {
  let weave = sin(uv.x * scale) * sin(uv.y * scale * 1.3);
  return 0.5 + weave * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / resolution;

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let spread = u.zoom_params.x * 0.5;
  let toothSize = 0.003 + u.zoom_params.y * 0.06;
  let angle = u.zoom_params.z * 3.14159;
  let toothAmp = u.zoom_params.w * 0.06;

  let aspect = resolution.x / max(resolution.y, 1.0);
  let local = rotate((uv - mouse) * vec2<f32>(aspect, 1.0), -angle);

  // Bass-driven zipper speed
  let zipSpeed = 1.0 + bass * 2.0;
  let openAmount = max(0.0, spread * (0.55 - local.y)) * zipSpeed;
  let halfGap = openAmount * 0.5;

  // Parallax from depth: fabric layers shift with depth
  let parallax = (depth - 0.5) * 0.04;
  let pushDir = select(-1.0, 1.0, local.x >= 0.0);
  let displacedLocal = vec2<f32>(local.x + pushDir * (halfGap + parallax), local.y);
  let sampleUV = clamp(rotate(displacedLocal, angle) / vec2<f32>(aspect, 1.0) + mouse, vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic aberration on fast-moving teeth
  let chroma = toothAmp * 0.5 * bass;
  let rSample = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(chroma, 0.0), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(chroma, 0.0), 0.0).b;
  var sampleColor = vec3<f32>(rSample, gSample, bSample);

  // Fabric texture
  let weave = fabric_weave(displacedLocal * 80.0, 200.0);
  sampleColor *= 0.9 + weave * 0.2;

  // Tooth geometry
  let toothPitch = max(toothSize * 2.8, 0.002);
  let toothWave = abs(fract(local.y / toothPitch) - 0.5) * 2.0;
  let openMask = select(0.0, 1.0, halfGap > 0.001);

  // Interlocking tooth profile
  let toothProfile = sin(local.y * 60.0 + time * 4.0 * zipSpeed) * 0.5 + 0.5;
  let toothOffset = toothAmp * toothProfile * openMask;
  let seamDist = abs(local.x) - toothOffset;

  let toothLine = 1.0 - smoothstep(0.0, toothSize * 0.5, abs(seamDist - halfGap));
  let toothRow = 1.0 - smoothstep(0.22, 0.50, toothWave);
  let toothMask = openMask * toothLine * toothRow;

  // Specular highlights on metal teeth
  let lightDir = normalize(vec2<f32>(0.3, 0.7));
  let toothNormal = normalize(vec2<f32>(cos(local.y * 80.0), 0.5));
  let spec = pow(max(dot(toothNormal, lightDir), 0.0), 16.0);
  let metalBase = vec3<f32>(0.45, 0.40, 0.35);
  let metalHighlight = vec3<f32>(1.0, 0.85, 0.55) * (0.4 + spec * 0.6 + bass * 0.2);
  let metalColor = mix(metalBase, metalHighlight, 0.5);

  // Under-fabric
  let underPattern = 0.5 + 0.5 * sin(local.y * 100.0 + time * 5.0);
  let underColor = mix(vec3<f32>(0.03, 0.02, 0.05), vec3<f32>(0.2, 0.04, 0.25), underPattern);

  // Fabric edge confidence
  let edgeConf = smoothstep(0.0, toothSize * 2.0, abs(abs(local.x) - halfGap));

  var finalColor = sampleColor;
  finalColor = mix(finalColor, underColor, openMask * (1.0 - toothMask) * edgeConf * 0.8);
  finalColor = mix(finalColor, metalColor, toothMask);

  // ACES tone mapping
  finalColor = aces_tone_map(finalColor);

  // Alpha: Tooth visibility * fabric_edge_confidence * depth
  let alpha = clamp(toothMask * 0.9 + edgeConf * 0.4 * openMask + depth * 0.3, 0.1, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth + toothMask * 0.1, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
