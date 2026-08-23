// ═══════════════════════════════════════════════════════════════
//  Glitch Reveal — Batch 61
//  Block scatter reveal: spring cursor, held widen, capped ripples,
//  exact C persistence, hex block geometry, ACES + semantic alpha.
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn blockEdge(cellUV: vec2<f32>) -> f32 {
  let edge = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
  return 1.0 - smoothstep(0.0, 0.12, edge);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let blockSize = u.zoom_params.x * 0.2 + 0.01;
  let scatter = u.zoom_params.y * (1.0 + bass * 2.0);
  let revealRadius = (u.zoom_params.z * 0.5 + 0.05) * select(1.0, 1.35, held);
  let speed = u.zoom_params.w * 10.0;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) { smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]); }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) { springPos = mouse; springVel = vec2<f32>(0.0); }
    else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let effectiveRadius = revealRadius * mix(0.6, 1.4, depth);

  let gridUV = floor(uv / blockSize);
  let cellUV = fract(uv / blockSize);
  let seed = gridUV + floor(time * speed * (1.0 + mids));
  let rand = hash22(seed);
  var blockOffset = (rand - 0.5) * scatter;

  let dVec = uv - smoothMouse;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  var mask = select(1.0, smoothstep(effectiveRadius * 0.75, effectiveRadius, dist), dist < effectiveRadius);

  var rippleReveal = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      rippleReveal += smoothstep(0.14, 0.0, rDist) * (1.0 - age * 0.85);
    }
  }
  mask = clamp(mask - rippleReveal * 0.8, 0.0, 1.0);
  blockOffset = blockOffset * mask;

  let sampleUV = clamp(uv + blockOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let caDir = (uv - 0.5) * 0.035 * mask * scatter * (1.0 + depth);
  let colorSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + caDir, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    colorSample.g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - caDir, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );
  var alpha = colorSample.a;

  if (mask > 0.01 && scatter > 0.0) {
    if (rand.x > 0.78) {
      let shiftSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.012 * mask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
      color = vec3<f32>(shiftSample.r, colorSample.g, colorSample.b);
      alpha = mix(colorSample.a, shiftSample.a * 0.9 + 0.1, mask * 0.3);
    } else if (rand.x < 0.18) {
      color = 1.0 - colorSample.rgb;
      alpha = colorSample.a * 0.95;
    }
  }

  let prev = textureLoad(dataTextureC, coord, 0);
  color = mix(color, prev.rgb, mask * scatter * 0.65);

  let border = smoothstep(effectiveRadius, effectiveRadius + 0.012, dist)
             - smoothstep(effectiveRadius + 0.012, effectiveRadius + 0.024, dist);
  let edgeGlow = blockEdge(cellUV) * mask;
  if (border > 0.0 || edgeGlow > 0.3) {
    let borderColor = vec3<f32>(0.0, 1.0, 0.55) + vec3<f32>(treble * 0.2);
    color = mix(color, borderColor, (border + edgeGlow * 0.4) * 0.45);
    alpha = mix(alpha, 1.0, border * 0.3);
  }

  color = acesToneMap(color * (0.96 + bass * 0.06));
  alpha = mix(mix(0.5, 1.0, depth), 1.0, 1.0 - mask * scatter);
  alpha = clamp(alpha + rippleReveal * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(mask, scatter, rippleReveal, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
