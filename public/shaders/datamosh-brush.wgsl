// ═══════════════════════════════════════════════════════════════
//  Datamosh Brush — Batch 60
//  Interactive MPEG smear: spring brush, held smear vector, capped
//  click ripples, macroblock geometry, exact C feedback, ACES + audio.
// ═══════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len = length(v);
  return select(v / len, vec2<f32>(0.0), len < 0.0001);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn macroblockEdge(uv: vec2<f32>, blockSize: f32) -> f32 {
  if (blockSize < 0.005) { return 0.0; }
  let blocks = 1.0 / blockSize;
  let cell = fract(uv * blocks);
  let edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
  return 1.0 - smoothstep(0.0, 0.08, edge);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let brushSize = mix(0.02, 0.22, u.zoom_params.x) * (1.0 + bass * 0.45) * select(1.0, 1.2, held);
  let blockSize = mix(0.0, 0.12, u.zoom_params.y) * (1.0 + mids * 0.5);
  let decay = mix(0.0, 0.12, u.zoom_params.z);
  let alphaGhost = clamp(mix(0.3, 1.0, u.zoom_params.w) + treble * 0.2, 0.0, 1.0);

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

  let prevSample = textureLoad(dataTextureC, coord, 0);
  var prevColor = prevSample.rgb;
  var prevAlpha = prevSample.a;
  if (prevAlpha < 0.01) {
    let currSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    prevColor = currSample.rgb;
    prevAlpha = currSample.a;
  }

  let inputSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var blendedColor = mix(prevColor, inputSample.rgb, decay);
  var blendedAlpha = mix(prevAlpha, inputSample.a, decay);
  blendedAlpha = blendedAlpha * (1.0 - decay * 0.5);

  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let dist = distance(uvAspect, mouseAspect);

  var rippleCorrupt = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      let rDist = distance(uvAspect, rAspect);
      rippleCorrupt += smoothstep(0.1, 0.0, rDist) * (1.0 - age);
    }
  }

  let smearDir = safeNormalize(uvAspect - mouseAspect);
  let smearOffset = smearDir * length(vec2<f32>(extraBuffer[135], extraBuffer[136])) * 0.15 * select(0.0, 1.0, held);

  if ((held && dist < brushSize) || rippleCorrupt > 0.01) {
    let blockID = floor(uv / max(0.001, blockSize + 0.001));
    let noiseVal = hash12(blockID + vec2<f32>(time));
    if (noiseVal > 0.25 || rippleCorrupt > 0.3) {
      let offsetUV = clamp(uv + hash22(blockID + vec2<f32>(time)) * 0.06 + smearOffset * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
      let glitchSample = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);
      let channelSwap = vec3<f32>(glitchSample.g, glitchSample.b, glitchSample.r);
      blendedColor = mix(glitchSample.rgb, channelSwap, mids * 0.25);
      blendedAlpha = glitchSample.a * 0.75 + 0.12;
    } else {
      blendedColor = prevColor;
      blendedAlpha = prevAlpha * alphaGhost;
    }
    blendedAlpha = max(blendedAlpha, 0.1);
  }

  if (blockSize > 0.01) {
    let blockCorrupt = hash12(floor(uv / blockSize) + vec2<f32>(time * 0.1));
    if (blockCorrupt > 0.78) {
      blendedAlpha = mix(blendedAlpha, blockCorrupt, 0.35);
    }
    let edge = macroblockEdge(uv, blockSize);
    blendedColor = mix(blendedColor, blendedColor * vec3<f32>(1.2, 0.9, 1.3), edge * mids * 0.4);
  }

  blendedAlpha = clamp(blendedAlpha, 0.0, 1.0);
  blendedColor = acesToneMap(blendedColor * (0.95 + bass * 0.08));

  textureStore(dataTextureA, coord, vec4<f32>(blendedColor, blendedAlpha));
  textureStore(writeTexture, coord, vec4<f32>(blendedColor, blendedAlpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
