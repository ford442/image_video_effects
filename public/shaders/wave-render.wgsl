// ═══════════════════════════════════════════════════════════════════
//  Wave Tank — render
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: rising-crest foam from latched previous height
//  A packing: raw wave copied back. ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadH(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0).r;
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let h = fract(hsv.x) * 6.0;
  let s = hsv.y;
  let v = hsv.z;
  let c = v * s;
  let x = c * (1.0 - abs((h % 2.0) - 1.0));
  let m = v - c;
  let sector = floor(h);
  var rgb = vec3<f32>(0.0);
  rgb = select(rgb, vec3<f32>(c, x, 0.0), sector < 1.0);
  rgb = select(rgb, vec3<f32>(x, c, 0.0), sector >= 1.0 && sector < 2.0);
  rgb = select(rgb, vec3<f32>(0.0, c, x), sector >= 2.0 && sector < 3.0);
  rgb = select(rgb, vec3<f32>(0.0, x, c), sector >= 3.0 && sector < 4.0);
  rgb = select(rgb, vec3<f32>(x, 0.0, c), sector >= 4.0 && sector < 5.0);
  rgb = select(rgb, vec3<f32>(c, 0.0, x), sector >= 5.0);
  return rgb + vec3<f32>(m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let pixel = vec2<i32>(coord);
  let hi = vec2<i32>(size) - vec2<i32>(1);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));

  let state = textureLoad(dataTextureC, pixel, 0);
  let height = state.r;
  let velocity = state.g;
  let prevHeight = state.b;

  let dx = (loadH(pixel + vec2<i32>(1, 0), hi) - loadH(pixel + vec2<i32>(-1, 0), hi)) * 2.0;
  let dy = (loadH(pixel + vec2<i32>(0, 1), hi) - loadH(pixel + vec2<i32>(0, -1), hi)) * 2.0;
  let normal = normalize(vec3<f32>(-dx, -dy, 0.1));
  let refractOffset = clamp(normal.xy * 0.03, vec2<f32>(-0.08), vec2<f32>(0.08));
  let sourceColor = textureSampleLevel(readTexture, u_sampler, clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let phase = atan2(velocity, height);
  let hue = phase / 6.283185 + 0.5;
  let amplitude = sqrt(height * height + velocity * velocity);
  let waveColor = hsv2rgb(vec3<f32>(hue, 0.7, amplitude * 2.0 + 0.2));

  let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
  let diffuse = max(dot(normal, lightDir), 0.0);
  let specular = pow(max(dot(reflect(-lightDir, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 32.0);

  var finalColor = sourceColor.rgb;
  finalColor = finalColor + waveColor * amplitude * 0.5;
  finalColor = finalColor * (0.5 + diffuse * 0.5);
  finalColor = finalColor + vec3<f32>(specular * 0.3);

  let laplacian = loadH(pixel + vec2<i32>(1, 0), hi) + loadH(pixel + vec2<i32>(-1, 0), hi)
                + loadH(pixel + vec2<i32>(0, 1), hi) + loadH(pixel + vec2<i32>(0, -1), hi)
                - 4.0 * height;
  let caustic = pow(abs(laplacian) * 5.0, 2.0);
  finalColor = finalColor + vec3<f32>(caustic * 0.2);

  // ── Idea 2: foam on a crest that is still rising ──────────────────
  let rising = max(height - prevHeight, 0.0);
  let crest = smoothstep(0.12, 0.48, height) * smoothstep(0.002, 0.06, rising);
  finalColor = finalColor + vec3<f32>(0.82, 0.90, 1.0) * crest * (0.4 + amplitude * 0.8);

  let alpha = clamp(sourceColor.a * 0.35 + amplitude * 0.45 + crest * 0.4, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(max(finalColor, vec3<f32>(0.0))), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(mix(depth, 0.5 - height * 0.2, 0.65), 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, state);
}
