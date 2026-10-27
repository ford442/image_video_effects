// ═══════════════════════════════════════════════════════════════════
//  Digital Compression
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: AC quantization (§12.2B); mosquito noise on the block edge
//  A packing: diagnostic (influence, artifact, blocks, alpha); C unread; ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rgb2yuv(rgb: vec3<f32>) -> vec3<f32> {
  let y = 0.29900 * rgb.r + 0.58700 * rgb.g + 0.11400 * rgb.b;
  let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.43600 * rgb.b;
  let v = 0.61500 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
  return vec3<f32>(y, u, v);
}

fn yuv2rgb(yuv: vec3<f32>) -> vec3<f32> {
  let r = yuv.x + 1.13983 * yuv.z;
  let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
  let b = yuv.x + 2.03211 * yuv.y;
  return vec3<f32>(r, g, b);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blockEdge(blockUV: vec2<f32>, blocks: f32, aspect: f32) -> f32 {
  let cell = fract(vec2<f32>(blockUV.x * blocks * aspect, blockUV.y * blocks));
  let edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
  return 1.0 - smoothstep(0.0, 0.1, edge);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 0.001);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let blockSizeParam = u.zoom_params.x;
  let colorDepthParam = u.zoom_params.y;
  let artifactParam = u.zoom_params.z;
  let focusRadius = u.zoom_params.w * select(1.0, 1.25, held);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) { smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]); }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) { springPos = mouse; springVel = vec2<f32>(0.0); }
    else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(smoothMouse.x * aspect, smoothMouse.y));
  var influence = smoothstep(focusRadius * 0.45, focusRadius, dist);

  var rippleClear = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      rippleClear += smoothstep(0.12, 0.0, rDist) * (1.0 - age);
    }
  }
  influence = clamp(influence - rippleClear * 0.7, 0.0, 1.0);

  let bassBlockBoost = 1.0 + bass * 0.5;
  let blocks = mix(256.0, 16.0, blockSizeParam * influence) / bassBlockBoost;
  let blockUV = vec2<f32>(
    floor(uv.x * blocks * aspect) / max(blocks * aspect, 0.001),
    floor(uv.y * blocks) / max(blocks, 0.001)
  );

  let noise = hash12(blockUV * 10.0 + time);
  let artifactThresh = artifactParam * 0.1 * influence * (1.0 + treble * 0.5);
  let displaceActive = step(0.001, artifactParam) * step(noise, artifactThresh);
  let displaceX = (noise - 0.5) * 0.1 * displaceActive;
  let sampleUV = clamp(vec2<f32>(blockUV.x + displaceX, blockUV.y), vec2<f32>(0.0), vec2<f32>(1.0));

  let sampled = textureSampleLevel(readTexture, non_filtering_sampler, sampleUV, 0.0);
  var color = sampled.rgb;

  // ── Idea 1: AC quantization (§12.2B) ────────────────────────────
  // The block corner stays the DC. The pixel-minus-DC residual is rounded
  // to a step from Bit Crush and added back. Bit Crush at zero keeps the
  // flat block sample.
  let localRgb = textureSampleLevel(readTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let quantStep = max(mix(0.02, 0.18, colorDepthParam * influence), 0.001);
  let acQuant = round((localRgb - sampled.rgb) / quantStep) * quantStep;
  color += acQuant * step(0.001, colorDepthParam);

  let colorActive = step(0.001, colorDepthParam);
  let levels = mix(255.0, 2.0, colorDepthParam * influence);
  color = mix(color, floor(color * levels) / max(levels, 0.001), colorActive);

  let chromaActive = step(0.001, artifactParam);
  let yuv = rgb2yuv(color);
  let uvLevels = mix(255.0, 4.0, artifactParam * influence);
  let chromaColor = yuv2rgb(vec3<f32>(yuv.x, floor(yuv.y * uvLevels) / max(uvLevels, 0.001), floor(yuv.z * uvLevels) / max(uvLevels, 0.001)));
  color = mix(color, chromaColor, chromaActive);

  let edge = blockEdge(blockUV, blocks, aspect);
  color = mix(color, color * vec3<f32>(1.15, 0.9, 1.1), edge * mids * 0.35 * influence);

  // ── Idea 2: mosquito noise ──────────────────────────────────────
  // MPEG mosquito grain sits on the block edge this file already measures.
  // Artifacts still scales it. The phase steps with time, like a codec.
  let mozPhase = floor(time * 9.0);
  let mosquito = (hash12(blockUV * 13.0 + vec2<f32>(mozPhase, 2.7)) - 0.5) * edge * artifactParam * influence;
  color += vec3<f32>(mosquito * 0.4);

  color = acesToneMap(clamp(color, vec3<f32>(0.0), vec3<f32>(4.0)) * (0.96 + bass * 0.06));
  let artifactStrength = clamp(artifactParam * influence + displaceActive * 0.3, 0.0, 1.0);
  let alpha = clamp(artifactStrength * 0.5 + influence * 0.3 + bass * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(influence, artifactStrength, blocks * 0.01, alpha));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
