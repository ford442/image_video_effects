// ═══════════════════════════════════════════════════════════════════
//  digital-reveal-guided — Batch 60
//  Matrix rain + depth-guided filter: spring brush, held widen, capped
//  click ripples, exact C trail mask, audio glyph density, ACES.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx+p3.yz)*p3.zy);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn glyphShape(cellUV: vec2<f32>, id: f32) -> f32 {
  let bars = step(0.3, cellUV.x) * step(cellUV.x, 0.7) * step(0.2, cellUV.y);
  let dots = step(length(cellUV - vec2<f32>(0.5)), 0.18);
  return max(bars, dots * step(fract(id * 0.37), 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let aspect = res.x / res.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let density = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + treble * 0.3);
  let revealSize = u.zoom_params.y;
  let trailFade = u.zoom_params.z;
  let depthInfluence = u.zoom_params.w;

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

  let prevVal = textureLoad(dataTextureC, coord, 0).r;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let dist = distance(uvCorrected, mouseCorrected);
  let brushRadius = (revealSize * 0.32 + 0.05) * select(1.0, 1.35, held);
  let brush = smoothstep(brushRadius, brushRadius * 0.45, dist);
  let fadeFactor = 0.78 + trailFade * 0.21;

  var rippleReveal = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      rippleReveal += smoothstep(0.14, 0.0, distance(uvCorrected, rAspect)) * (1.0 - age * 0.85);
    }
  }

  let newVal = clamp(max(prevVal * fadeFactor, brush + rippleReveal), 0.0, 1.0);

  let radiusBase = i32(mix(2.0, 7.0, revealSize));
  let epsilonBase = mix(0.0001, 0.05, depthInfluence);
  let mouseDist = length(uv - smoothMouse);
  let mouseFactor = exp(-mouseDist * mouseDist * 6.0);
  let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.35, mouseFactor));
  let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.08, mouseFactor);
  let maxRadius = min(radius, 6);

  var sumGuide = 0.0;
  var sumInput = vec3<f32>(0.0);
  var sumGuideInput = vec3<f32>(0.0);
  var sumGuide2 = 0.0;
  var count = 0.0;

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
      let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
      let inputVal = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      sumGuide += guideVal;
      sumInput += inputVal;
      sumGuideInput += inputVal * guideVal;
      sumGuide2 += guideVal * guideVal;
      count += 1.0;
    }
  }

  let meanGuide = sumGuide / max(count, 1.0);
  let meanInput = sumInput / max(count, 1.0);
  let meanGI = sumGuideInput / max(count, 1.0);
  let meanGuide2 = sumGuide2 / max(count, 1.0);
  let varGuide = meanGuide2 - meanGuide * meanGuide;

  let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
  let b = meanInput - a * meanGuide;
  let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let filtered = a * guide + b;
  let confidence = length(a) * depthInfluence;

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let filteredResult = mix(original, filtered, depthInfluence * newVal);

  let gridSize = vec2<f32>(18.0 + density * 24.0, (18.0 + density * 24.0) * aspect);
  let cellUV = fract(uv * gridSize);
  let cellID = floor(uv * gridSize);
  let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (3.0 + mids * 2.0);
  let verticalPos = cellID.y + time * colSpeed;
  let charID = floor(verticalPos);
  let dropVal = fract(verticalPos);
  let charBright = smoothstep(0.0, 0.18, dropVal) * smoothstep(1.0, 0.75, dropVal);
  let flicker = step(0.08, hash22(vec2<f32>(cellID.x, charID)).x);
  let glyph = glyphShape(cellUV, hash22(vec2<f32>(cellID.x, charID)).x);
  var rainColor = vec3<f32>(0.05, 0.95, 0.35) * charBright * flicker * glyph;
  if (hash22(vec2<f32>(cellID.x, charID)).y > 0.97 - density * 0.12) {
    rainColor = vec3<f32>(0.85, 1.0, 0.75);
  }
  rainColor += vec3<f32>(0.1, 0.0, 0.15) * bass;

  let band = min(u32(uv.x * 8.0), 7u);
  rainColor *= 1.0 + plasmaBuffer[band + 1u].x * 0.2;

  var finalColor = mix(rainColor, filteredResult, clamp(newVal, 0.0, 1.0));
  finalColor = acesToneMap(finalColor * (0.96 + bass * 0.06));
  let alpha = clamp(confidence * newVal + 0.35, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(newVal, confidence, glyph, 1.0));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
