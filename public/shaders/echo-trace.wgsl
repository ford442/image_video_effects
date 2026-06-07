// ═══════════════════════════════════════════════════════════════════
//  Echo Trace
//  Category: artistic
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: Very High
//  Scientific: A 4D Kalman mouse-state estimator with covariance-driven Mahalanobis trails predicts motion and weights echo persistence by uncertainty.
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn clamp_uv(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hue_shift(color: vec3<f32>, shift: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735026919);
  let cs = cos(shift);
  let sn = sin(shift);
  return color * cs + cross(k, color) * sn + k * dot(k, color) * (1.0 - cs);
}

fn structure_tensor(uv: vec2<f32>, texel: vec2<f32>) -> mat2x2<f32> {
  let l = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv - vec2<f32>(texel.x, 0.0)), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + vec2<f32>(texel.x, 0.0)), 0.0).rgb;
  let t = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv - vec2<f32>(0.0, texel.y)), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + vec2<f32>(0.0, texel.y)), 0.0).rgb;
  let gx = dot((r - l) * 0.5, vec3<f32>(0.299, 0.587, 0.114));
  let gy = dot((b - t) * 0.5, vec3<f32>(0.299, 0.587, 0.114));
  return mat2x2<f32>(gx * gx, gx * gy, gx * gy, gy * gy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= size.x || global_id.y >= size.y) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(f32(size.x), f32(size.y));
  let texel = 1.0 / resolution;
  let uv = (vec2<f32>(f32(global_id.x), f32(global_id.y)) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let measurement = u.zoom_config.yz;

  let initialized = extraBuffer[8] > 0.5;
  var prevState = vec4<f32>(measurement, vec2<f32>(0.0));
  var pPos = vec2<f32>(0.0025, 0.0025);
  var pVel = vec2<f32>(0.02, 0.02);
  if (initialized) {
    prevState = vec4<f32>(extraBuffer[0], extraBuffer[1], extraBuffer[2], extraBuffer[3]);
    pPos = vec2<f32>(max(extraBuffer[4], 1e-5), max(extraBuffer[5], 1e-5));
    pVel = vec2<f32>(max(extraBuffer[6], 1e-5), max(extraBuffer[7], 1e-5));
  }

  let dt = 1.0 / 60.0;
  let sigmaA = 0.02 + u.zoom_params.x * 0.18 + bass * 0.35;
  let sigmaM = 0.002 + u.zoom_params.y * 0.03;
  let qPos = 0.25 * dt * dt * sigmaA * sigmaA;
  let qVel = dt * sigmaA * sigmaA;
  let rPos = sigmaM * sigmaM;

  let predictedPos = prevState.xy + prevState.zw * dt;
  let predictedVel = prevState.zw;
  let pPosPred = pPos + pVel * (dt * dt) + vec2<f32>(qPos);
  let pVelPred = pVel + vec2<f32>(qVel);
  let innovation = measurement - predictedPos;
  let s = pPosPred + vec2<f32>(rPos);
  let kPos = pPosPred / s;
  let kVel = (pVelPred * dt) / s;
  let updatedPos = predictedPos + kPos * innovation;
  let updatedVel = predictedVel + (kVel * innovation) / max(dt, 1e-4);
  let pPosUpd = max((vec2<f32>(1.0) - kPos) * pPosPred, vec2<f32>(1e-5));
  let pVelUpd = max((vec2<f32>(1.0) - kVel) * pVelPred, vec2<f32>(1e-5));

  let st = structure_tensor(uv, texel);
  let trace = st[0][0] + st[1][1];
  let eig = vec2<f32>(st[0][0] - st[1][1] + 1e-4, 2.0 * st[0][1]);
  let flowDir = normalize(select(vec2<f32>(1.0, 0.0), eig, trace > 1e-4));
  let velDir = normalize(select(vec2<f32>(1.0, 0.0), updatedVel * vec2<f32>(aspect, 1.0), length(updatedVel) > 1e-5));
  let residualMag = length(innovation * vec2<f32>(aspect, 1.0));

  let history = textureSampleLevel(dataTextureC, u_sampler, clamp_uv(uv), 0.0);
  let source = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv), 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp_uv(uv), 0.0).r;

  let deltaPred = (uv - predictedPos) * vec2<f32>(aspect, 1.0);
  let deltaUpd = (uv - updatedPos) * vec2<f32>(aspect, 1.0);
  let maha = deltaPred.x * deltaPred.x / max(pPosPred.x, 1e-5) + deltaPred.y * deltaPred.y / max(pPosPred.y, 1e-5);
  let ellipse = exp(-0.5 * maha);

  let dashPhase = fract(dot(deltaPred, velDir) * 28.0 + u.config.x * 6.0);
  let dashed = step(0.45, dashPhase);
  let predictedTrail = ellipse * dashed * smoothstep(0.002, 0.08, residualMag);
  let recentTrail = exp(-dot(deltaUpd, deltaUpd) / max(0.0003 + u.zoom_params.z * 0.012, 1e-4));
  let uncertainty = clamp((sqrt(pPosUpd.x + pPosUpd.y) + sqrt(pVelUpd.x + pVelUpd.y)) * 10.0, 0.0, 1.0);

  let advectUV = clamp_uv(uv - flowDir * trace * (0.02 + treble * 0.01) - velDir * residualMag * 0.06);
  let echo = textureSampleLevel(dataTextureC, u_sampler, advectUV, 0.0).rgb;
  var color = mix(history.rgb, echo, 0.35 + 0.15 * uncertainty);
  color = mix(color, source.rgb, recentTrail * (0.65 + 0.25 * bass));
  color = color + vec3<f32>(0.25, 0.55, 1.0) * predictedTrail;
  color = color + vec3<f32>(1.0, 0.85, 0.4) * clamp(residualMag * 6.0, 0.0, 1.0) * recentTrail * 0.35;
  color = hue_shift(color, uncertainty * 0.6 + mids * 0.18);

  let alpha = clamp(source.a * 0.9 + recentTrail * 0.25 + predictedTrail * 0.15, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
  textureStore(dataTextureA, coord, vec4<f32>(
    clamp(pPosUpd.x * 300.0, 0.0, 1.0),
    clamp(pPosUpd.y * 300.0, 0.0, 1.0),
    clamp(pVelUpd.x * 45.0, 0.0, 1.0),
    clamp(pVelUpd.y * 45.0, 0.0, 1.0)
  ));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * 0.88 + ellipse * 0.08 + predictedTrail * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));

  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[0] = updatedPos.x;
    extraBuffer[1] = updatedPos.y;
    extraBuffer[2] = updatedVel.x;
    extraBuffer[3] = updatedVel.y;
    extraBuffer[4] = pPosUpd.x;
    extraBuffer[5] = pPosUpd.y;
    extraBuffer[6] = pVelUpd.x;
    extraBuffer[7] = pVelUpd.y;
    extraBuffer[8] = 1.0;
  }
}
