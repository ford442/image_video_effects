// ═══════════════════════════════════════════════════════════════════
//  digital-moss-rgba — Batch 60
//  RD-driven digital moss: spring cursor, held plant/clean modes, capped
//  spore ripples, exact C Laplacian, psychedelic moss palette.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn mossPalette(a: f32, b: f32, c: f32, d: f32, t: f32) -> vec3<f32> {
  let base = vec3<f32>(0.08, 0.55, 0.22) * a
    + vec3<f32>(0.9, 0.25, 0.1) * b
    + vec3<f32>(0.15, 0.95, 0.45) * c
    + vec3<f32>(0.75, 0.65, 0.15) * d;
  let irid = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (t + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.67))
  );
  return base * (0.65 + irid * 0.35);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let aspect = f32(dims.x) / f32(dims.y);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let feedParam = u.zoom_params.x;
  let killParam = u.zoom_params.y;
  let sourceMix = u.zoom_params.z;
  let growSpeed = u.zoom_params.w * (1.0 + bass * 0.25);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

  let state = textureLoad(dataTextureC, coord, 0);
  var A = state.r;
  var B = state.g;
  var C = state.b;
  var D = state.a;

  if (time < 0.1) {
    A = 1.0; B = 0.0; C = 1.0; D = 0.0;
    let centerDist = length(uv - vec2<f32>(0.5));
    if (centerDist < 0.05) { B = 0.5; D = 0.3; }
    let seed2Dist = length(uv - vec2<f32>(0.3, 0.7));
    if (seed2Dist < 0.03) { B = 0.4; }
  }

  let left = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let right = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let down = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let up = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1)), 0);

  let lapA = left.r + right.r + down.r + up.r - 4.0 * A;
  let lapB = left.g + right.g + down.g + up.g - 4.0 * B;
  let lapC = left.b + right.b + down.b + up.b - 4.0 * C;
  let lapD = left.a + right.a + down.a + up.a - 4.0 * D;

  let feed = mix(0.02, 0.06, feedParam);
  let kill = mix(0.04, 0.07, killParam);
  let diffA = 0.8; let diffB = 0.3; let diffC = 0.7; let diffD = 0.25;
  let crossInhibit = sourceMix * 0.3;
  let dt = 0.8;

  let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
  let dB = diffB * lapB + A * B * B - (feed + kill) * B;
  let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B;
  let dD = diffD * lapD + C * D * D - (feed + kill) * D;

  A = clamp(A + dA * dt, 0.0, 1.0);
  B = clamp(B + dB * dt, 0.0, 1.0);
  C = clamp(C + dC * dt, 0.0, 1.0);
  D = clamp(D + dD * dt, 0.0, 1.0);

  let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let m_aspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let mDist = length(p_aspect - m_aspect);
  let mouseInfluence = smoothstep(0.12, 0.0, mDist);

  if (held) {
    B += mouseInfluence * 0.4;
    D += mouseInfluence * 0.25;
  } else if (u.zoom_config.w > 0.0) {
    B = max(0.0, B - mouseInfluence * 0.5);
    D = max(0.0, D - mouseInfluence * 0.3);
  }
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 1.5 && rDist < 0.08) {
      let strength = smoothstep(0.08, 0.0, rDist) * max(0.0, 1.0 - age * 0.7);
      B += strength * 0.5;
      D += strength * 0.3;
    }
  }
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

  let prevMoss = textureLoad(dataTextureC, coord, 0).r;
  let seed = hash12(uv + vec2<f32>(time * 0.1, time * 0.05));
  var grown = prevMoss;

  if (luma < 0.15 && seed > 0.992 - treble * 0.01) {
    grown = 1.0;
  }

  if (grown < 0.9) {
    let angle = hash12(uv * 10.0 + time) * 6.28;
    let offset = vec2<i32>(i32(cos(angle) * 2.0), i32(sin(angle) * 2.0));
    let neighborState = textureLoad(dataTextureC, clamp(coord + offset, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    if (neighborState > 0.5 && luma < 0.42) {
      grown = min(1.0, grown + 0.06 * growSpeed);
    }
  }

  if (luma > 0.6) {
    grown *= 0.88;
  }

  if (mDist < 0.06 && !held && u.zoom_config.w > 0.0) {
    grown = 0.0;
  }
  if (mDist < 0.08 && held) {
    grown = min(1.0, grown + 0.15 * mouseInfluence);
  }

  let mossColor = mossPalette(A, B, C, D, time * 0.04 + mids * 0.2);
  let scan = 0.82 + 0.18 * sin(uv.y * 480.0 + time * 2.0);
  let scannedMossColor = mossColor * scan;
  var finalColor = mix(imgColor, scannedMossColor, grown * 0.88);
  finalColor = acesToneMap(finalColor * (0.95 + bass * 0.08));
  let alpha = clamp(mix(1.0, 0.82, grown) + B * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
