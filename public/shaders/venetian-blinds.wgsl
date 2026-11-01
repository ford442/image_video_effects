// ═══════════════════════════════════════════════════════════════════
//  Venetian Blinds
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-01
//  Ideas: tilt view; ladder tape; slat bounce
//  A packing: ACES display RGBA (C is not read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);

  let slatCount = mix(10.0, 100.0, u.zoom_params.x);
  let baseOpenness = u.zoom_params.y;
  let slatColorMix = u.zoom_params.z;
  let phaseShift = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouseInfluence = mouse.y - 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let openness = clamp(baseOpenness + mouseInfluence + bass * 0.35, 0.0, 1.0);

  let y = uv.y * slatCount + phaseShift;
  let slatUV = fract(y);
  let minThickness = 0.05;
  let visibleSlatSize = mix(1.0, minThickness, openness);
  let halfSlat = max(visibleSlatSize * 0.5, 0.001);
  let centeredSlatUV = abs(slatUV - 0.5);
  let slatHit = 1.0 - smoothstep(halfSlat - 0.008, halfSlat + 0.008, centeredSlatUV);

  let normY = clamp((slatUV - 0.5) / halfSlat, -1.0, 1.0);
  let light = 0.5 + 0.5 * sqrt(max(0.0, 1.0 - normY * normY));
  let baseSlat = mix(vec3<f32>(0.1, 0.1, 0.1), vec3<f32>(0.9, 0.9, 0.9), slatColorMix);
  let glint = pow(max(0.0, 1.0 - abs(normY)), 8.0)
    * (0.5 + 0.5 * sin(uv.x * 12.0 - u.config.x * 2.0)) * mids;
  let slatRGB = baseSlat * light + vec3<f32>(0.7, 0.85, 1.0) * glint * 0.5;

  // ── Idea 1: tilt view — an open slat shows a shifted slice of the photo ──
  let tilt = (openness - 0.5) * 2.0;
  let pitch = 1.0 / max(slatCount, 1.0);
  let seeUV = clamp(uv + vec2<f32>(0.0, tilt * pitch * 1.6), vec2<f32>(0.0), vec2<f32>(1.0));
  let baseImage = textureSampleLevel(readTexture, u_sampler, seeUV, 0.0);

  let below = smoothstep(0.5, 0.502, slatUV);
  let distFromSlatEdge = slatUV - (0.5 + halfSlat);
  let shadowT = smoothstep(0.0, 0.2, distFromSlatEdge);
  let shadow = mix(1.0, mix(0.5, 1.0, shadowT), below * (1.0 - slatHit));

  // ── Idea 3: slat bounce — the gap just under a slat takes its colour ──
  let bounce = exp(-max(distFromSlatEdge, 0.0) * 18.0) * below * (1.0 - slatHit) * (0.35 + slatColorMix * 0.4);
  let gapRGB = baseImage.rgb * shadow + baseSlat * bounce * 0.22;

  var rgb = mix(gapRGB, slatRGB, slatHit);

  // ── Idea 2: ladder tape — two vertical cords, stitched at each slat ──
  let tapeL = 1.0 - smoothstep(0.006, 0.014, abs(uv.x - 0.14));
  let tapeR = 1.0 - smoothstep(0.006, 0.014, abs(uv.x - 0.86));
  let tape = max(tapeL, tapeR);
  let tapeCol = mix(baseSlat, vec3<f32>(0.55, 0.48, 0.38), 0.55);
  let tapeLight = mix(0.72, light, slatHit);
  rgb = mix(rgb, tapeCol * tapeLight, tape * 0.72);
  let stitch = tape * slatHit * (1.0 - smoothstep(0.0, 0.08, centeredSlatUV));
  rgb = rgb * (1.0 - stitch * 0.35);

  let display = aces(max(rgb, vec3<f32>(0.0)));
  var alpha = mix(baseImage.a * shadow, 0.88 + light * 0.1, slatHit);
  alpha = mix(alpha, min(alpha + 0.06, 1.0), tape * 0.5);
  let outCol = vec4<f32>(display, clamp(alpha, 0.0, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(depth, 0.22 + (1.0 - openness) * 0.15, slatHit * 0.65 + tape * 0.2), 0.0, 1.0);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
