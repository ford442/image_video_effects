// Cyber Terminal ASCII — Composer batch cyber/digital/glitch cohort 3
// Scrolling hex dump, phosphor-green mono vs color blend, spring decoder lens,
// held decode widen, click packet burst, exact C phosphor persistence, ACES.

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
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 { return length(p) - r; }

fn getCharacter(id: i32, uv: vec2<f32>) -> f32 {
  let p = uv - 0.5;
  var d = 1.0;
  if (id == 0) { return 0.0; }
  else if (id == 1) { d = sdCircle(p, 0.05); }
  else if (id == 2) { d = min(sdCircle(p - vec2<f32>(0.0, -0.15), 0.05), sdCircle(p - vec2<f32>(0.0, 0.15), 0.05)); }
  else if (id == 3) { d = sdBox(p, vec2<f32>(0.25, 0.05)); }
  else if (id == 4) { d = min(abs(p.x), abs(p.y)) - 0.05; }
  else if (id == 5) {
    let rot45 = mat2x2<f32>(0.707, -0.707, 0.707, 0.707);
    let pr = rot45 * p;
    d = min(min(abs(p.x), abs(p.y)) - 0.05, min(abs(pr.x), abs(pr.y)) - 0.05);
  }
  else if (id == 6) { d = min(sdBox(p - vec2<f32>(0.0, -0.1), vec2<f32>(0.25, 0.04)), sdBox(p - vec2<f32>(0.0, 0.1), vec2<f32>(0.25, 0.04))); }
  else if (id == 7) {
    d = min(min(sdBox(p - vec2<f32>(-0.1, 0.0), vec2<f32>(0.04, 0.3)), sdBox(p - vec2<f32>(0.1, 0.0), vec2<f32>(0.04, 0.3))),
          min(sdBox(p - vec2<f32>(0.0, -0.1), vec2<f32>(0.3, 0.04)), sdBox(p - vec2<f32>(0.0, 0.1), vec2<f32>(0.3, 0.04))));
  }
  else { d = min(abs(sdCircle(p, 0.25)) - 0.04, sdCircle(p - vec2<f32>(0.0, 0.05), 0.08)); }
  return 1.0 - smoothstep(0.0, 0.05, d);
}

fn getBinaryChar(id: i32, uv: vec2<f32>) -> f32 {
  let p = uv - 0.5;
  let d = select(sdBox(p, vec2<f32>(0.05, 0.25)), abs(sdBox(p, vec2<f32>(0.15, 0.25))) - 0.05, id % 2 == 0);
  return 1.0 - smoothstep(0.0, 0.05, d);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 11.0;
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

  let density = mix(10.0, 200.0, u.zoom_params.x);
  let colorMode = u.zoom_params.y;
  let glowStrength = u.zoom_params.z;
  let decoderRadius = mix(0.05, 0.4, u.zoom_params.w);

  let gridDims = vec2<f32>(density * aspect, density);
  let scroll = fract(time * (0.08 + bass * 0.12 + mids * 0.05));
  let cellUV = fract(uv * gridDims + vec2<f32>(0.0, scroll));
  let cellId = floor(uv * gridDims + vec2<f32>(0.0, scroll));
  let cellCenter = (cellId + 0.5) / gridDims - vec2<f32>(0.0, scroll);

  let inputColor = textureSampleLevel(readTexture, u_sampler, clamp(cellCenter, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let luma = dot(inputColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let toMouse = (cellCenter - smoothMouse) * vec2<f32>(aspect, 1.0);
  let distMouse = length(toMouse);
  let decodeRadius = decoderRadius * select(1.0, 1.35, held);
  let isDecoder = step(distMouse, decodeRadius);

  var charMask = 0.0;
  let seed = dot(cellId, vec2<f32>(12.9898, 78.233)) + time * (5.0 + treble * 3.0);
  let rand = hash12(vec2<f32>(seed, cellId.y));
  if (isDecoder > 0.5) {
    charMask = getBinaryChar(i32(step(0.5, rand)), cellUV);
    if (rand > 0.95 - treble * 0.05) { charMask = 0.0; }
  } else {
    var glyphIdx = clamp(i32(pow(luma, 1.2) * 8.0 + 0.5), 0, 8);
    charMask = getCharacter(glyphIdx, cellUV);
  }

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst = max(clickBurst, exp(-age * 3.0) * (1.0 - smoothstep(0.0, 0.1, radius)));
    }
  }

  let phosphor = vec3<f32>(0.0, 1.0, 0.2) * luma * 2.0;
  var outputColor = mix(phosphor, inputColor.rgb, colorMode) * charMask * glowStrength;
  outputColor = mix(outputColor, vec3<f32>(0.8, 1.0, 1.0), isDecoder * 0.8) * (1.0 + clickBurst * 0.5);

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  outputColor = mix(outputColor, prev, 0.08 * charMask);

  let cursorBlink = step(0.5, fract(time * 2.0 + cellId.x * 0.1));
  if (abs(cellId.y - floor(scroll * gridDims.y)) < 1.0 && cellId.x < 3.0) {
    outputColor += vec3<f32>(0.0, 1.0, 0.3) * cursorBlink * 0.15;
  }

  outputColor *= smoothstep(0.8, 0.2, length(uv - 0.5));
  outputColor *= sin(uv.y * resolution.y * 0.5) * 0.1 + 0.9;
  outputColor = acesToneMap(outputColor * (0.95 + bass * 0.05));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let alpha = clamp(charMask * mix(0.7, 1.0, luma) * inputColor.a + clickBurst * 0.2 + isDecoder * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(outputColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(outputColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
