// ═══════════════════════════════════════════════════════════════
//  Glitch Ripple Drag — Batch 60
//  Liquid glitch smear: spring cursor, capped click ripples, held
//  drag boost, quantized wave geometry, exact C feedback, ACES + audio.
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

fn hash21(p: vec2<f32>) -> f32 {
  var n = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(n) * 43758.5453123);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len = length(v);
  return select(v / len, vec2<f32>(0.0), len < 0.001);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let dragStrength = u.zoom_params.x * 0.06 * (1.0 + bass * 0.3) * select(1.0, 1.5, held);
  let waveFreq = 10.0 + u.zoom_params.y * 45.0 + treble * 8.0;
  let persistence = 0.9 + (u.zoom_params.z * 0.099);
  let glitchAmt = u.zoom_params.w;
  let alphaFade = 1.0 - (u.zoom_params.z * 0.05);

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
      let omega = 10.0;
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

  let uvAspect = uv * vec2<f32>(aspect, 1.0);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let dVec = uvAspect - mouseAspect;
  let dist = length(dVec);

  var waveMask = 0.0;
  let wave = sin(dist * waveFreq - time * 5.5);
  waveMask = smoothstep(0.45, 0.85, wave) * smoothstep(1.0, 0.0, dist * 1.8);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.4) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      let rDist = length(uvAspect - rAspect);
      let ring = abs(rDist - age * 0.35);
      waveMask += smoothstep(0.04, 0.0, ring) * (1.0 - age * 0.7);
    }
  }

  var dir = safeNormalize(dVec);
  if (glitchAmt > 0.0) {
    let angle = atan2(dir.y, dir.x);
    let quant = PI / (4.0 + glitchAmt * 10.0);
    let qAngle = floor(angle / quant) * quant;
    dir = vec2<f32>(cos(qAngle), sin(qAngle));
  }

  let displacement = dir * dragStrength * waveMask;
  let sampleCoord = clamp(coord - vec2<i32>(displacement * resolution), vec2<i32>(0), dims - vec2<i32>(1));

  var history = textureLoad(dataTextureC, sampleCoord, 0);
  let inputSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  if (history.a < 0.1) {
    history = inputSample;
  }

  var finalColor = mix(inputSample.rgb, history.rgb, persistence);
  var finalAlpha = mix(inputSample.a, history.a * alphaFade, persistence);

  if (glitchAmt > 0.35 && waveMask > 0.08) {
    let rCoord = clamp(sampleCoord + vec2<i32>(i32(resolution.x * 0.005), 0), vec2<i32>(0), dims - vec2<i32>(1));
    let bCoord = clamp(sampleCoord - vec2<i32>(i32(resolution.x * 0.005), 0), vec2<i32>(0), dims - vec2<i32>(1));
    let r = textureLoad(dataTextureC, rCoord, 0).r;
    let b = textureLoad(dataTextureC, bCoord, 0).b;
    finalColor = vec3<f32>(r, finalColor.g, b);
    finalAlpha = finalAlpha * 0.97;
    let glitchTint = vec3<f32>(1.1, 0.85, 1.2) * (0.9 + mids * 0.15);
    finalColor = mix(finalColor, finalColor * glitchTint, glitchAmt * waveMask * 0.4);
  }

  let band = min(u32(uv.x * 8.0), 7u);
  finalColor += vec3<f32>(0.05, 0.02, 0.08) * plasmaBuffer[band + 1u].x * waveMask * 0.3;

  finalAlpha = clamp(finalAlpha, 0.1, 1.0);
  finalColor = acesToneMap(finalColor * (0.95 + bass * 0.08));
  let output = vec4<f32>(finalColor, finalAlpha);

  textureStore(writeTexture, coord, output);
  textureStore(dataTextureA, coord, output);

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
