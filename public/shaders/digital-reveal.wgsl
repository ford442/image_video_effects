// ═══════════════════════════════════════════════════════════════════
//  Digital Reveal — Batch 61
//  Matrix rain + glyph shapes: spring brush at extraBuffer[133..138],
//  exact C mask, capped ripples, held enlarges brush, ACES composite.
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
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
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
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = u.zoom_config.w > 0.5;

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthReveal = mix(0.3, 1.0, depth);

  let density = u.zoom_params.x * bass_env(bass, mids);
  let revealSize = u.zoom_params.y * select(1.0, 1.3, held);
  let trailFade = u.zoom_params.z;
  let rainSpeed = u.zoom_params.w * (1.0 + treble * 0.5);

  let prevVal = textureLoad(dataTextureC, pixel, 0).r;

  var springPos = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
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
  }

  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(springPos.x * aspect, springPos.y));
  let brushRadius = revealSize * 0.3 + 0.05;
  let mouseValid = select(0.0, 1.0, mouse.x >= 0.0);
  let brush = mouseValid * smoothstep(brushRadius, brushRadius * 0.5, dist);

  let fadeFactor = 0.8 + trailFade * 0.19;
  var newVal = max(prevVal * fadeFactor, brush) * depthReveal;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let liveF = step(0.0, age) * step(age, 2.0);
    let rpDist = length((rp.xy - uv) * vec2<f32>(aspect, 1.0));
    let blob = 1.0 - smoothstep(0.0, 0.15, rpDist);
    newVal = max(newVal, blob * liveF * (1.0 - age * 0.5));
  }

  textureStore(dataTextureA, pixel, vec4<f32>(newVal, 0.0, 0.0, 1.0));

  let gridSize = vec2<f32>(18.0 + density * 26.0, (18.0 + density * 26.0) * aspect);
  let cellUV = fract(uv * gridSize);
  let cellID = floor(uv * gridSize);
  let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (rainSpeed * 5.0 + 1.0);
  let verticalPos = cellID.y + time * colSpeed;
  let charID = floor(verticalPos);
  let dropVal = fract(verticalPos);
  let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);
  let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);
  let glyph = glyphShape(cellUV, hash22(vec2<f32>(cellID.x, charID)).x);

  let band = min(u32(uv.x * 8.0), 7u);
  var rainColor = vec3<f32>(0.05, 0.95, 0.32) * charBright * flicker * glyph;
  rainColor *= 1.0 + plasmaBuffer[band + 1u].x * 0.25;
  rainColor.g += bass * 0.3 * charBright * glyph;
  if (hash22(vec2<f32>(cellID.x, charID)).y > 0.98 - density * 0.1) {
    rainColor = vec3<f32>(0.8 + treble * 0.2, 1.0, 0.8 + treble * 0.2);
  }

  let depthGlow = mix(1.0, mix(0.6, 1.2, depth), 0.4);
  rainColor *= depthGlow;

  let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var finalColor = mix(rainColor, imageColor, clamp(newVal, 0.0, 1.0));
  finalColor = acesToneMap(finalColor * (0.95 + mids * 0.05));
  let alpha = clamp(newVal + charBright * glyph * 0.2 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
