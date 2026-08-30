// ═══════════════════════════════════════════════════════════════════
//  Optical Illusion Spin
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA
//  Motion: counter-rotating ring packets + Fraser-spiral whip
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

const TAU: f32 = 6.28318530718;

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(dot(fract(p * vec2<f32>(0.1031, 0.1030)), vec2<f32>(19.19, 17.13)) * 43758.5453);
}

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn snakePattern(coord: vec2<f32>, rings: f32, t: f32, dir: f32) -> f32 {
  let radius = length(coord);
  let angle = atan2(coord.y, coord.x);
  let ringIndex = floor(radius * rings);
  let ringPhase = fract(radius * rings);
  let alt = select(-1.0, 1.0, fract(ringIndex * 0.5) >= 0.5);
  let snakeAngle = angle + dir * t * 1.6 + ringIndex * 0.35 * alt;
  let wedge = fract(snakeAngle * 3.0 / TAU);
  let edge = 1.0 - smoothstep(0.38, 0.50, abs(wedge - 0.5));
  let ringEdge = 1.0 - smoothstep(0.42, 0.50, abs(ringPhase - 0.5));
  return edge * ringEdge;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[2].y;
  let binB = plasmaBuffer[7].x;

  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 8.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.0), vec2<f32>(2.0));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  let ringCount = 4.0 + u.zoom_params.x * 44.0;
  let speed = 0.15 + u.zoom_params.y * 5.0;
  let twistForce = u.zoom_params.z * 4.5;
  let alternating = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let scale = 1.0 - depth * 0.3;
  let centered = (uv - spring) * vec2<f32>(aspect, 1.0) / max(scale, 0.15);
  let radius = length(centered);
  let angle = atan2(centered.y, centered.x);
  let bassSpeed = speed * (1.0 + bass * 1.15);
  let ringI = floor(radius * ringCount);
  let dirA = mix(1.0, select(-1.0, 1.0, fract(ringI * 0.5) >= 0.5), alternating);
  let dirB = -dirA * 0.7;

  let packet = sin(radius * ringCount * 1.15 - time * (3.6 + bassSpeed)) * 0.5 + 0.5;
  let packetPulse = pow(packet, 3.0) * (0.22 + bass * 0.18);
  let fraser = angle + log(max(radius, 0.004)) * (2.8 + twistForce * 0.35);
  let whip = sin(fraser * 6.0 - time * (4.8 + mids * 2.2)) * exp(-radius * 1.4) * (0.16 + treble * 0.1);

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.5;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    click = click + select(0.0, exp(-abs(rd - age * 0.5) * 14.0) * exp(-age * 1.2), alive);
  }

  let twist = (1.0 - smoothstep(0.0, 1.1, radius)) * twistForce + whip + click * 0.4;
  let holdSpin = select(0.0, 0.35, held);
  let spun = rotate(centered, twist + packetPulse + holdSpin);
  let sampleUV = clamp(spun / vec2<f32>(aspect, 1.0) + spring, vec2<f32>(0.0), vec2<f32>(1.0));

  let patA = snakePattern(centered, ringCount, time * bassSpeed, dirA);
  let patB = snakePattern(centered * 1.03 + vec2<f32>(0.01, 0.0), ringCount, time * bassSpeed * 0.94, dirB);
  let moire = abs(patA - patB) * 2.0;

  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let afterimage = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.007, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    baseColor.g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.007, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let opA = mix(vec3<f32>(0.05, 0.82, 0.95), vec3<f32>(0.95, 0.92, 0.05), 0.5 + 0.5 * sin(angle * 4.0 + time * bassSpeed + binA));
  let opB = mix(vec3<f32>(0.95, 0.25, 0.05), vec3<f32>(0.15, 0.95, 0.42), 0.5 + 0.5 * cos(angle * 3.0 - time * bassSpeed * 0.8 + binB));
  let opArt = mix(opA, opB, moire) * (patA + patB + moire * 0.5 + packetPulse);

  var hdr = mix(baseColor.rgb, opArt, clamp((patA + patB) * 0.35, 0.0, 0.68));
  hdr = mix(hdr, afterimage, 0.12 * (patA + patB));
  hdr = mix(hdr, hist.rgb, 0.12);
  hdr = hdr + vec3<f32>(0.92, 0.78, 0.55) * ((patA + patB) * (0.08 + 0.16 * treble) + click * 0.25);
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * 1.22;
  let rgb = acesFilm(hdr * 1.1);

  let illusion = clamp((patA + patB + moire + packetPulse) * 0.42, 0.0, 1.0);
  let alpha = clamp(illusion * (0.25 + depth) + abs(whip) * 0.4, 0.12, 0.96);
  let outCol = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.28 + illusion * 0.5, 0.2), 0.0, 1.0), 0.0, 0.0, 0.0));
}
