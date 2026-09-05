// Cyber Trace Structure — Composer batch cyber/digital/glitch
// Structure-tensor LIC mouse trace: spring cursor, held brush, capped
// ripples, exact C history, three-band audio, ACES + semantic alpha.

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

fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
  var tc = t;
  if (tc < 0.0) { tc = tc + 1.0; }
  if (tc > 1.0) { tc = tc - 1.0; }
  if (tc < 1.0 / 6.0) { return p + (q - p) * 6.0 * tc; }
  if (tc < 1.0 / 2.0) { return q; }
  if (tc < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - tc) * 6.0; }
  return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
  if (s == 0.0) { return vec3<f32>(l); }
  var q: f32;
  if (l < 0.5) { q = l * (1.0 + s); } else { q = l + s - l * s; }
  let p = 2.0 * l - q;
  return vec3<f32>(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
  let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
  return dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn structureTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  let gx =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) + -2.0 * sampleLuma(uv, pixelSize, -1, 0) + -1.0 * sampleLuma(uv, pixelSize, -1, 1) +
     1.0 * sampleLuma(uv, pixelSize, 1, -1) +  2.0 * sampleLuma(uv, pixelSize, 1, 0) +  1.0 * sampleLuma(uv, pixelSize, 1, 1);
  let gy =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) + -2.0 * sampleLuma(uv, pixelSize, 0, -1) + -1.0 * sampleLuma(uv, pixelSize, 1, -1) +
     1.0 * sampleLuma(uv, pixelSize, -1, 1) +  2.0 * sampleLuma(uv, pixelSize, 0, 1) +  1.0 * sampleLuma(uv, pixelSize, 1, 1);
  return vec4<f32>(gx * gx, gy * gy, gx * gy, 0.0);
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      sum += structureTensor(uv + vec2<f32>(f32(dx), f32(dy)) * pixelSize, pixelSize);
    }
  }
  return sum / 9.0;
}

fn lic(uv: vec2<f32>, direction: vec2<f32>, pixelSize: vec2<f32>, steps: i32, stepSize: f32) -> f32 {
  var pos = uv;
  var accum = 0.0;
  var weight = 0.0;
  for (var i = 0; i < steps; i++) {
    let lum = dot(textureSampleLevel(readTexture, u_sampler, clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let w = 1.0 - f32(i) / f32(steps);
    accum += lum * w;
    weight += w;
    pos += direction * stepSize * pixelSize;
  }
  pos = uv;
  for (var j = 0; j < steps; j++) {
    let lum = dot(textureSampleLevel(readTexture, u_sampler, clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let w = 1.0 - f32(j) / f32(steps);
    accum += lum * w;
    weight += w;
    pos -= direction * stepSize * pixelSize;
  }
  return accum / max(weight, 0.001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
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

  let decaySpeed = u.zoom_params.x * (1.0 + bass * 0.1);
  let glowIntensity = u.zoom_params.y * (1.0 + mids * 0.2);
  let hueShiftParam = u.zoom_params.z;
  let brushSize = mix(0.04, 0.18, u.zoom_params.w);

  let tensor = smoothTensor(uv, pixelSize);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;
  let trace = Jxx + Jyy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;
  let lambda2 = (trace - diff) * 0.5;

  var eigenvec = vec2<f32>(1.0, 0.0);
  if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
    eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
  }

  let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);

  let dist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
  let brush = smoothstep(brushSize, brushSize * 0.5, dist) * select(0.5, 1.0, held);

  let mouseFactor = exp(-dist * dist * 8.0);
  let mouseAngle = atan2(uv.y - smoothMouse.y, uv.x - smoothMouse.x);
  let vortex = vec2<f32>(-sin(mouseAngle), cos(mouseAngle)) * mouseFactor;
  eigenvec = normalize(mix(eigenvec, vortex, mouseFactor * 0.5));

  var rippleTurb = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rElapsed = time - ripple.z;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let wave = exp(-pow((rDist - rElapsed * 0.3) * 8.0, 2.0));
      let turbAngle = atan2(uv.y - ripple.y, uv.x - ripple.x) + rElapsed * 3.0;
      rippleTurb += vec2<f32>(cos(turbAngle), sin(turbAngle)) * wave * (1.0 - rElapsed / 3.0);
    }
  }
  eigenvec = normalize(eigenvec + rippleTurb * 2.0);

  let licValue = lic(uv, eigenvec, pixelSize, 16, 1.5);
  let history = textureLoad(dataTextureC, coord, 0);

  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let drawColor = hslToRgb(fract(flowAngle + hueShiftParam + time * 0.05 + treble * 0.08), 1.0, 0.5);

  let flowDecay = decaySpeed * (0.8 + 0.2 * coherency);
  let newHistory = clamp(history.rgb * flowDecay + drawColor * brush, vec3<f32>(0.0), vec3<f32>(2.0));

  let inputSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let traceTint = mix(vec3<f32>(1.0, 0.9, 0.7), vec3<f32>(0.7, 0.9, 1.0), flowAngle);
  var finalColor = inputSample.rgb + newHistory * glowIntensity * traceTint * (0.5 + 0.5 * licValue);

  let bandBin = min(u32(uv.x * 8.0), 7u) + 1u;
  finalColor += vec3<f32>(0.04, 0.08, 0.12) * plasmaBuffer[bandBin].x * coherency * 0.2;

  finalColor = acesToneMap(finalColor * (0.95 + bass * 0.05));

  let alpha = clamp(inputSample.a * 0.85 + pow(coherency, 0.5) * (0.5 + 0.5 * licValue) * 0.35 + brush * 0.15, 0.0, 1.0);
  let historyAlpha = clamp(history.a * flowDecay + brush * 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(newHistory, historyAlpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
