// ═══════════════════════════════════════════════════════════════════
//  Polka Wave
//  Category: image
//  Features: mouse-driven, audio-reactive, cmyk-halftone, upgraded-rgba
//  Complexity: High
//  Chunks From: polka-wave, bass_env, aa_step, IGN-dither
//  Created: 2026-05-17
//  Upgraded: 2026-05-31
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

fn aa_step(threshold: f32, value: f32, aa: f32) -> f32 {
  return smoothstep(threshold - aa, threshold + aa, value);
}

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a);
  let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let density = mix(20.0, 150.0, u.zoom_params.x);
  let amp = u.zoom_params.y * bass_env(bass, mids);
  let freq = mix(5.0, 50.0, u.zoom_params.z);
  let speed = mix(0.5, 5.0, u.zoom_params.w);

  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let distMouse = distance(uv * vec2<f32>(aspect, 1.0), mouse_aspect);
  let ripple = sin(distMouse * freq - time * speed) * amp;
  let invertRipple = smoothstep(0.0, 0.3, ripple * 0.5 + 0.5);

  let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let brightness = dot(texColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let cmykC = 1.0 - texColor.r;
  let cmykM = 1.0 - texColor.g;
  let cmykY = 1.0 - texColor.b;
  let cmykK = 1.0 - max(max(texColor.r, texColor.g), texColor.b);

  let angles = vec4<f32>(0.2618, 0.7854, 1.3090, 1.5708);
  let channels = vec4<f32>(cmykC, cmykM, cmykY, cmykK);

  var dotAccum = vec3<f32>(0.0);
  var maskAccum = 0.0;

  for (var i: i32 = 0; i < 4; i = i + 1) {
    let angle = angles[i];
    let chVal = channels[i];
    let rotGrid = rot2D(angle) * (uv * vec2<f32>(aspect, 1.0) * density);
    let cellId = floor(rotGrid);
    let cellUv = fract(rotGrid) - 0.5;

    let centerPos = (cellId + 0.5) / density;
    let sampleUv = vec2<f32>(centerPos.x / aspect, centerPos.y);
    let sampleCol = textureSampleLevel(readTexture, u_sampler, sampleUv, 0.0);
    let sampleBright = dot(sampleCol.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let distCell = length(cellUv);
    let dotRadius = sampleBright * 0.45 * bass_env(bass, mids);
    let noiseAmt = (treble * 0.05) * sin(time * 10.0 + cellId.x * 3.0 + cellId.y * 7.0);
    let rFinal = clamp(dotRadius + ripple * 0.15 * amp + noiseAmt, 0.03, 0.5);

    let aa = 0.7 / density;
    let mask = 1.0 - aa_step(rFinal, distCell, aa);
    let invertMask = mix(mask, 1.0 - mask, invertRipple);

    let inkCol = select(vec3<f32>(0.0, 1.0, 1.0), select(vec3<f32>(1.0, 0.0, 1.0), select(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 0.0), i == 2), i == 1), i == 0);
    dotAccum = dotAccum + inkCol * invertMask * chVal;
    maskAccum = maskAccum + invertMask * chVal;
  }

  let paperWhite = vec3<f32>(0.96, 0.96, 0.94);
  let halftoneRGB = paperWhite - dotAccum;
  let halftoneAlpha = clamp(maskAccum + brightness * 0.3 + mids * 0.1, 0.0, 1.0);
  let finalColor = vec4<f32>(clamp(halftoneRGB, vec3<f32>(0.0), vec3<f32>(1.0)), halftoneAlpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
