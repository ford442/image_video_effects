// ═══════════════════════════════════════════════════════════════════
//  Vortex Drag
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA
//  Motion: sprung vortex core + helical streak ribbons
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn palette(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (vec3<f32>(1.0, 0.75, 0.5) * t + vec3<f32>(0.0, 0.22, 0.45)));
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
  let binA = plasmaBuffer[3].x;
  let binB = plasmaBuffer[6].y;

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
      let omega = 10.5;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-3.2), vec2<f32>(3.2));
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

  let twistStrength = (u.zoom_params.x - 0.5) * 20.0 * (1.0 + bass * 0.5);
  let radius = mix(0.1, 0.8, u.zoom_params.y) * (1.0 + mids * 0.3);
  let pinchStrength = (u.zoom_params.z - 0.5) * 2.0 * (1.0 + treble * 0.4);
  let hardness = mix(0.0, 0.95, u.zoom_params.w);

  var dVec = (uv - spring) * vec2<f32>(aspect, 1.0);
  let dist = length(dVec);
  let effectT = 1.0 - smoothstep(radius * (1.0 - hardness), radius, dist);
  let hold = select(1.0, 1.4, held);

  let helix = sin(atan2(dVec.y, dVec.x) * 5.0 - dist * 22.0 + time * (5.5 + bass * 2.5))
    * effectT * (0.07 + mids * 0.04);
  let ribbon = pow(max(0.0, sin(atan2(dVec.y, dVec.x) * 3.0 + time * 3.8) * 0.5 + 0.5), 8.0) * effectT;

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.0;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    click = click + select(0.0, exp(-abs(rd - age * 0.65) * 16.0) * exp(-age * 1.5), alive);
  }

  let angle = twistStrength * effectT * effectT * hold + helix * 6.0 + click * 1.2;
  let s = sin(angle);
  let c = cos(angle);
  var rotated = vec2<f32>(dVec.x * c - dVec.y * s, dVec.x * s + dVec.y * c);
  let pinchFactor = 1.0 - (pinchStrength * effectT);
  rotated = rotated * pinchFactor;
  let finalUV = clamp(spring + vec2<f32>(rotated.x / aspect, rotated.y), vec2<f32>(0.0), vec2<f32>(1.0));

  let warped = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let twistMag = abs(twistStrength) * effectT * effectT;
  let pinchMag = abs(pinchStrength) * effectT;
  var hdr = warped.rgb * vec3<f32>(1.05, 1.0, 0.95) * (1.0 + pinchMag * 0.08);
  hdr = hdr * vec3<f32>(1.0 + twistMag * 0.04, 1.0, 1.0 - twistMag * 0.04);
  hdr = mix(hdr, hist.rgb, 0.16 * effectT);
  hdr = hdr + palette(time * 0.08 + dist * 1.6 + binA * 0.1) * ribbon * (0.35 + treble * 0.2 + binB * 0.1);
  hdr = hdr + vec3<f32>(0.75, 0.9, 1.0) * click * 0.35;
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * 1.2;
  let rgb = acesToneMap(hdr * 1.08);

  let alpha = clamp(warped.a * (0.7 + effectT * 0.3) * (1.0 - pinchMag * 0.15) + ribbon * 0.25 + click * 0.2, 0.12, 0.98);
  let outCol = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * (1.0 + pinchMag * 0.08), 0.0, 1.0), 0.0, 0.0, 0.0));
}
