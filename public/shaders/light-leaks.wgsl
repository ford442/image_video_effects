// ═══════════════════════════════════════════════════════════════════
//  Light Leaks
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-31
//  Ideas: rebate streak; dye-layer fringe; halation (§12.2A)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Mouse blob, two drifting blobs, and the rebate streak. Same weights as the
// original leak field so halation can re-evaluate it at a neighbor.
fn leakField(uv: vec2<f32>, mouse: vec2<f32>, time: f32, size: f32, speed: f32, intensity: f32) -> f32 {
  let safeSize = max(size, 0.001);
  let blob1 = smoothstep(safeSize, 0.0, distance(uv, mouse));
  let move2 = vec2<f32>(sin(time * speed * 0.5), cos(time * speed * 0.3)) * 0.5 + 0.5;
  let blob2 = smoothstep(safeSize * 1.5, 0.0, distance(uv, move2));
  let move3 = vec2<f32>(cos(time * speed * 0.7), sin(time * speed * 0.4)) * 0.5 + 0.5;
  let blob3 = smoothstep(safeSize * 1.2, 0.0, distance(uv, move3));
  // ── Idea 1: rebate streak ─────────────────────────────────────────
  // Light enters from the frame edge facing the pointer. Width is leak size.
  let edgeX = mix(uv.x, 1.0 - uv.x, step(0.5, mouse.x));
  let edgeY = mix(uv.y, 1.0 - uv.y, step(0.5, mouse.y));
  let edge = mix(edgeX, edgeY, step(abs(mouse.x - 0.5), abs(mouse.y - 0.5)));
  let gate = smoothstep(safeSize * 0.9, 0.0, edge);
  let drift = 0.5 + 0.5 * sin(uv.y * 6.2831853 + time * speed * 1.7 + uv.x * 2.0);
  let streak = gate * drift;
  return (blob1 + blob2 * 0.7 + blob3 * 0.5 + streak * 0.85) * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let intensity = u.zoom_params.x * (1.0 + bass * 0.28);
  let warmth = u.zoom_params.y;
  let size = u.zoom_params.z;
  let speed = u.zoom_params.w;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let totalLeak = leakField(uv, mouse, time, size, speed, intensity);

  let warmColor = vec3<f32>(1.0, 0.5, 0.2);
  let coldColor = vec3<f32>(0.2, 0.5, 1.0);
  let leakColor = mix(coldColor, warmColor, warmth);
  // ── Idea 2: dye-layer fringe ──────────────────────────────────────
  // Mid leak is magenta. The white-hot core is unchanged.
  let fringe = smoothstep(0.08, 0.35, totalLeak) * (1.0 - smoothstep(0.55, 0.9, totalLeak));
  let dyed = mix(leakColor, vec3<f32>(0.82, 0.22, 0.48), fringe * (0.45 + warmth * 0.4));
  let core = smoothstep(0.75, 1.0, totalLeak);
  let finalLeakColor = mix(dyed, vec3<f32>(1.0), core);

  let leakAdd = clamp(finalLeakColor * totalLeak, vec3<f32>(0.0), vec3<f32>(1.0));
  var color = vec3<f32>(1.0) - (vec3<f32>(1.0) - src.rgb) * (vec3<f32>(1.0) - leakAdd);

  // ── Idea 3: halation (§12.2A) ─────────────────────────────────────
  // Red fog around the leak, and a bleached core. Four neighbor evaluations.
  let hr = 0.01 + size * 0.025;
  var hal = 0.0;
  for (var k = 0; k < 4; k = k + 1) {
    let o = vec2<f32>(f32(k & 1) * 2.0 - 1.0, f32((k >> 1) & 1) * 2.0 - 1.0) * hr;
    let tapUV = clamp(uv + o, vec2<f32>(0.0), vec2<f32>(1.0));
    hal += max(leakField(tapUV, mouse, time, size, speed, intensity) - 0.35, 0.0);
  }
  hal *= 0.25;
  color += vec3<f32>(1.0, 0.35, 0.10) * hal * 0.65;
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(color, vec3<f32>(luma), clamp(hal * 0.35, 0.0, 0.45));

  let leakAmt = clamp(totalLeak, 0.0, 1.0);
  let alpha = clamp(src.a * 0.55 + leakAmt * 0.4 + hal * 0.2, 0.0, 1.0);
  let display = vec4<f32>(aces(max(color, vec3<f32>(0.0))), alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, display);
  textureStore(dataTextureA, coord, display);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
