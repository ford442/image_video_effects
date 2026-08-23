// ═══════════════════════════════════════════════════════════════════
//  Datamosh Brush Diffusion — Batch 60
//  Perona-Malik anisotropic diffusion + datamosh brush: spring cursor,
//  held heat source, capped ripples, exact C loads, ACES + audio.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
  return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let brushSize = mix(0.02, 0.22, u.zoom_params.x) * (1.0 + bass * 0.3);
  let kappa = mix(0.01, 0.22, u.zoom_params.y) * (1.0 - mids * 0.15);
  let dt = mix(0.05, 0.28, u.zoom_params.z) * (1.0 + treble * 0.2);
  let alphaGhost = mix(0.3, 1.0, u.zoom_params.w);

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
      let springDt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.5;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * springDt;
      springPos += springVel * springDt;
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
  var blendedColor = mix(prevColor, inputSample.rgb, 0.05);
  var blendedAlpha = mix(prevAlpha, inputSample.a, 0.05);
  blendedAlpha = blendedAlpha * 0.98;

  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let dist = distance(uvAspect, mouseAspect);

  var rippleHeat = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.1) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      rippleHeat += smoothstep(0.12, 0.0, distance(uvAspect, rAspect)) * (1.0 - age);
    }
  }

  if ((held && dist < brushSize) || rippleHeat > 0.05) {
    let blockID = floor(uv * 24.0);
    let noiseVal = hash12(blockID + vec2<f32>(time));
    if (noiseVal > 0.28 || rippleHeat > 0.25) {
      let offsetUV = clamp(uv + hash22(blockID) * 0.06, vec2<f32>(0.0), vec2<f32>(1.0));
      let glitchSample = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);
      blendedColor = glitchSample.rgb;
      blendedAlpha = glitchSample.a * 0.8 + 0.1;
    } else {
      blendedColor = prevColor;
      blendedAlpha = prevAlpha * alphaGhost;
    }
    blendedAlpha = max(blendedAlpha, 0.1);
  }

  let center = blendedColor;
  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let nCoord = clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1));
  let sCoord = clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1));
  let eCoord = clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1));
  let wCoord = clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1));
  let n = textureLoad(dataTextureC, nCoord, 0).rgb;
  let s = textureLoad(dataTextureC, sCoord, 0).rgb;
  let e = textureLoad(dataTextureC, eCoord, 0).rgb;
  let w = textureLoad(dataTextureC, wCoord, 0).rgb;

  let gradN = length(n - center);
  let gradS = length(s - center);
  let gradE = length(e - center);
  let gradW = length(w - center);

  let cN = diffusionCoefficient(gradN, kappa);
  let cS = diffusionCoefficient(gradS, kappa);
  let cE = diffusionCoefficient(gradE, kappa);
  let cW = diffusionCoefficient(gradW, kappa);

  let mouseDist = length(uv - smoothMouse);
  let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * select(0.0, 1.0, held);
  let mouseBoost = 1.0 + mouseFactor * 6.0 + rippleHeat * 2.0;

  let fluxN = cN * (n - center);
  let fluxS = cS * (s - center);
  let fluxE = cE * (e - center);
  let fluxW = cW * (w - center);

  let diffused = center + dt * mouseBoost * (fluxN + fluxS + fluxE + fluxW);
  let avgCoeff = (cN + cS + cE + cW) * 0.25;
  var finalColor = mix(blendedColor, diffused, 0.45 + avgCoeff * 0.55);

  let oilTint = vec3<f32>(1.05, 0.95, 1.15) * (0.9 + mids * 0.15);
  finalColor = acesToneMap(finalColor * oilTint * (0.95 + bass * 0.08));
  blendedAlpha = clamp(blendedAlpha, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(finalColor, blendedAlpha));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, blendedAlpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
