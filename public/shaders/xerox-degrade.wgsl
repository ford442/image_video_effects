// Xerox Degrade — Composer batch cyber/digital/glitch
// Photocopy halftone + ordered dither: spring cursor, held smear burst,
// capped ripples, exact C generation memory, three-band audio, ACES + semantic alpha.

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

fn hash3_packed(p: vec2<f32>) -> vec3<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum += amp * valueNoise(p * freq);
    freq *= 2.0;
    amp *= 0.5;
  }
  return sum;
}

fn bayer4x4(p: vec2<i32>) -> f32 {
  let x = u32(p.x) & 3u;
  let y = u32(p.y) & 3u;
  let M = array<u32, 16>(
    0u, 8u, 2u, 10u, 12u, 4u, 14u, 6u, 3u, 11u, 1u, 9u, 15u, 7u, 13u, 5u
  );
  return f32(M[y * 4u + x]) * 0.0625;
}

fn sigmoidContrast(x: f32, k: f32) -> f32 {
  return 1.0 / (1.0 + exp(-k * (x - 0.5)));
}

fn halftoneDot(luma: f32, uv: vec2<f32>, freq: f32) -> f32 {
  let grid = fract(uv * freq) - 0.5;
  let radius = luma * 0.707;
  return 1.0 - smoothstep(radius - 0.02, radius, length(grid));
}

fn edgeVignette(uv: vec2<f32>, strength: f32) -> f32 {
  let d = length(uv - vec2<f32>(0.5));
  return mix(1.0, smoothstep(0.7, 0.35, d), strength);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
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

  let contrast = u.zoom_params.x * 8.0 + 2.0 + mids * 2.0;
  let grainAmt = clamp(u.zoom_params.y + bass * 0.15, 0.0, 1.0);
  let smearAmt = u.zoom_params.z * (1.0 + bass * 0.5) * select(1.0, 1.45, held);
  let threshold = clamp(u.zoom_params.w + treble * 0.05, 0.0, 1.0);

  var rippleSmear = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      rippleSmear += smoothstep(0.12, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age);
    }
  }

  let mouseSmear = smoothstep(0.18, 0.0, length((uv - smoothMouse) * vec2<f32>(aspect, 1.0))) * smearAmt * 0.08;
  let h = hash3_packed(uv * resolution * 0.01 + time * 0.1);
  let smearN = (h.x - 0.5) * (smearAmt + rippleSmear * 0.15 + mouseSmear);

  let smearUV = clamp(vec2<f32>(uv.x + smearN, uv.y), vec2<f32>(0.0), vec2<f32>(1.0));
  let src = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
  let paper = vec3<f32>(0.96, 0.96, 0.92);
  let oob = step(1.0, smearUV.x) + step(smearUV.x, 0.0);
  var color = mix(src.rgb, paper, min(oob, 1.0));

  let lumaRaw = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let contrasted = sigmoidContrast(clamp(lumaRaw - threshold + 0.5, 0.0, 1.0), contrast);

  let grain = fbm(uv * 40.0 + time * 0.5, 4) * 2.0 - 1.0;
  let grainUV = clamp(uv + vec2<f32>(grain * grainAmt * 0.02), vec2<f32>(0.0), vec2<f32>(1.0));
  let grainLuma = dot(textureSampleLevel(readTexture, u_sampler, grainUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

  let dither = bayer4x4(coord) - 0.5;
  let dotted = halftoneDot(contrasted + dither * 0.05, uv, 24.0 + mids * 16.0);
  let blendLuma = mix(contrasted, dotted, 0.6);
  let vign = edgeVignette(uv, 0.5 + treble * 0.5);

  let scatter = select(0.0, -0.4, h.y < grainAmt * 0.18) + select(0.0, 0.3, h.z > 1.0 - grainAmt * 0.18);
  let finalLuma = clamp((blendLuma + scatter * grainAmt) * vign + grain * grainAmt * 0.08 + grainLuma * grainAmt * 0.05, 0.0, 1.0);
  color = mix(vec3<f32>(0.05, 0.05, 0.12), paper, finalLuma);

  let prev = textureLoad(dataTextureC, coord, 0);
  color = mix(color, prev.rgb, smearAmt * 0.12 + rippleSmear * 0.06);

  color = acesToneMap(color * (0.95 + bass * 0.04));

  let alpha = clamp(src.a * (1.0 - (1.0 - finalLuma) * 0.35) + grainAmt * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
