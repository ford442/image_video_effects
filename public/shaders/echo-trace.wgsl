// ═══════════════════════════════════════════════════════════════════
//  Echo Trace
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: Kalman lag ghosts (3 tinted image copies stamped at pos − vel·k); redshift aging (echo hue drifts to amber with age); 2σ covariance ellipse outline around the predicted cursor
//  A packing: linear trail RGB + echo energy; texel (0,0) = Kalman pos.xy/vel.xy,
//             texel (1,0) = pPos.xy, pVel.x, w = 7 + pVel.y*100 (sentinel), texel (2,0).x = last time
//  Rescue: Kalman state lived in extraBuffer[133..141] (zeroed every upload → filter
//  never initialised); A held covariance diagnostics but C was read back as colour → black frame.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=prediction_horizon, y=velocity_smoothing,

const TAU: f32 = 6.28318530718;

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
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

fn predHorizonGhost(h: f32) -> f32 { return h * 0.15; }
fn brushWidthGhost(d: f32) -> f32 { return max(0.0003 + d * 0.012, 1e-4); }

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
  let time = u.config.x;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  var binShimmer = 0.0;
  if (arrayLength(&plasmaBuffer) > 3u) {
    binShimmer = (plasmaBuffer[1].x + plasmaBuffer[2].y + plasmaBuffer[3].z) * 0.33;
  }

  let measurement = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);

  // Kalman state from A texels (0,0)/(1,0) via C (every invocation reads the same values).
  let ks0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let ks1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let initialized = ks1.w > 6.5 && ks1.w < 8.5;
  var prevState = vec4<f32>(measurement, vec2<f32>(0.0));
  var pPos = vec2<f32>(0.0025, 0.0025);
  var pVel = vec2<f32>(0.02, 0.02);
  if (initialized) {
    prevState = vec4<f32>(ks0.xy, clamp(ks0.zw, vec2<f32>(-20.0), vec2<f32>(20.0)));
    pPos = vec2<f32>(max(ks1.x, 1e-5), max(ks1.y, 1e-5));
    pVel = vec2<f32>(max(ks1.z, 1e-5), max((ks1.w - 7.0) * 0.01, 1e-5));
  }

  // Real frame dt from the time stamped in texel (2,0) (HEAD assumed 60 Hz).
  let ks2 = textureLoad(dataTextureC, vec2<i32>(2, 0), 0);
  let dt = select(1.0 / 60.0, clamp(time - ks2.x, 1.0 / 240.0, 0.1), initialized);
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
  let updatedVel = clamp(predictedVel + (kVel * innovation) / max(dt, 1e-4), vec2<f32>(-6.0), vec2<f32>(6.0));
  let pPosUpd = max((vec2<f32>(1.0) - kPos) * pPosPred, vec2<f32>(1e-5));
  let pVelUpd = max((vec2<f32>(1.0) - kVel) * pVelPred, vec2<f32>(1e-5));


  let st = structure_tensor(uv, texel);
  let stTrace = st[0][0] + st[1][1];
  let eig = vec2<f32>(st[0][0] - st[1][1] + 1e-4, 2.0 * st[0][1]);
  let flowDir = normalize(select(vec2<f32>(1.0, 0.0), eig, stTrace > 1e-4));
  let velDir = normalize(select(vec2<f32>(1.0, 0.0), updatedVel * vec2<f32>(aspect, 1.0), length(updatedVel) > 1e-5));
  let residualMag = length(innovation * vec2<f32>(aspect, 1.0));

  // Exact (non-filtered) history / depth loads.
  var history = textureLoad(dataTextureC, coord, 0);
  if (!initialized) { history = vec4<f32>(0.0); } // foreign/zero C: start clean
  let source = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv), 0.0);
  let depth = textureLoad(readDepthTexture, coord, 0).r;

  let deltaPred = (uv - predictedPos) * vec2<f32>(aspect, 1.0);
  let deltaUpd = (uv - updatedPos) * vec2<f32>(aspect, 1.0);
  let maha = deltaPred.x * deltaPred.x / max(pPosPred.x, 1e-5) + deltaPred.y * deltaPred.y / max(pPosPred.y, 1e-5);
  let ellipse = exp(-0.5 * maha);

  // Held tightens brush radius (higher Mahalanobis falloff + denser dashes).
  let dashScale = mix(28.0, 42.0, held);
  let dashPhase = fract(dot(deltaPred, velDir) * dashScale + time * 6.0);
  let dashed = step(mix(0.45, 0.38, held), dashPhase);
  let predHorizon = u.zoom_params.x;
  let deform = u.zoom_params.z;
  let velThresh = u.zoom_params.w;
  let predictedTrail = ellipse * dashed * smoothstep(0.002, 0.08, residualMag)
                     * (0.85 + predHorizon * 0.4);
  let brushWidth = max(0.0003 + deform * 0.012, 1e-4) * mix(1.0, 0.55, held);
  let recentTrail = exp(-dot(deltaUpd, deltaUpd) / brushWidth);
  let uncertainty = clamp((sqrt(pPosUpd.x + pPosUpd.y) + sqrt(pVelUpd.x + pVelUpd.y)) * 10.0, 0.0, 1.0);
  let velGate = smoothstep(velThresh * 0.5, velThresh + 0.05, length(updatedVel));

  // Bounded advect sample from C (no filtered history).
  let advectUV = clamp_uv(uv - flowDir * stTrace * (0.02 + treble * 0.01) - velDir * residualMag * 0.06);
  let advectCoord = vec2<i32>(clamp(advectUV * resolution, vec2<f32>(0.0), resolution - 1.0));
  var echoT = textureLoad(dataTextureC, advectCoord, 0);
  if (!initialized) { echoT = vec4<f32>(0.0); }

  // Trail layer (stored in A): advected echo that fades; energy in .a.
  var trail = mix(history.rgb, echoT.rgb, 0.35 + 0.15 * uncertainty);
  var energy = mix(history.a, echoT.a, 0.35) * 0.975;
  trail *= 0.975;
  let stamp = recentTrail * (0.65 + 0.25 * bass) * (0.7 + velGate * 0.3);
  let dragSrc = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + updatedVel * 0.04), 0.0).rgb;
  trail = mix(trail, dragSrc, stamp);

  // Kalman lag ghosts: image copies stamped at past positions behind the cursor.
  let speed = length(updatedVel);
  for (var g = 1; g <= 3; g = g + 1) {
    let lag = f32(g) * (0.05 + predHorizonGhost(u.zoom_params.x));
    let gp = (uv - (updatedPos - updatedVel * lag)) * vec2<f32>(aspect, 1.0);
    let gw = exp(-dot(gp, gp) / (brushWidthGhost(u.zoom_params.z) * (1.0 + f32(g))));
    let gTint = mix(vec3<f32>(0.6, 0.85, 1.0), vec3<f32>(1.0, 0.55, 0.85), f32(g) / 3.0);
    let gSrc = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + updatedVel * lag), 0.0).rgb;
    trail = mix(trail, gSrc * gTint * 1.25, gw * smoothstep(0.05, 0.4, speed) * (0.6 - f32(g) * 0.12));
    energy = max(energy, gw * 0.8);
  }
  energy = max(energy, stamp);

  // Redshift aging: low energy (old echo) drifts warm, fresh echo stays cool.
  let age = 1.0 - clamp(energy, 0.0, 1.0);
  let trailAged = mix(trail, trail * vec3<f32>(1.25, 0.8, 0.5), age * 0.6);

  // Composite over the source.
  var color = mix(source.rgb, trailAged, clamp(energy * 1.3, 0.0, 1.0));

  // Oil-slick / psychedelic trail color keyed to Mahalanobis + audio.
  let film = 0.5 + 0.5 * cos(TAU * (vec3<f32>(maha * 0.08 + time * 0.11)
                                 + vec3<f32>(0.0, 0.33, 0.67)
                                 + vec3<f32>(mids * 0.2)));
  let trailTint = mix(vec3<f32>(0.25, 0.55, 1.0), vec3<f32>(1.0, 0.35, 0.85), uncertainty)
                * film;
  color = color + trailTint * predictedTrail * (0.9 + held * 0.35 + binShimmer * 0.25);
  color = color + vec3<f32>(1.0, 0.85, 0.4) * clamp(residualMag * 6.0, 0.0, 1.0) * recentTrail * 0.35;
  color = color + vec3<f32>(0.2, 0.95, 0.65) * recentTrail * held * 0.22 * (0.5 + treble);
  // 2σ covariance ellipse outline.
  let ring2 = exp(-pow((sqrt(maha) - 2.0) * 6.0, 2.0)) * (0.25 + uncertainty);
  color = color + vec3<f32>(0.55, 0.8, 1.0) * film * ring2 * 0.5;

  // Capped click spark echoes along past ripple centers.
  let rippleCount = min(u32(u.config.y), 50u);
  var spark = 0.0;
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = max(time - r.z, 0.0);
    let rd = (uv - r.xy) * vec2<f32>(aspect, 1.0);
    let rdist = length(rd);
    let ring = abs(sin(rdist * 48.0 - age * 14.0)) * exp(-age * 1.8) * smoothstep(0.22, 0.0, rdist);
    spark += ring;
  }
  let sparkCol = vec3<f32>(0.95, 0.55, 1.0) * film * spark * (0.35 + treble * 0.4);
  color = color + sparkCol;

  color = hue_shift(color, uncertainty * 0.6 + mids * 0.18 + held * 0.08);

  // ACES on display path only (A stores covariance diagnostics).
  var display = acesToneMap(color * (0.92 + mids * 0.15 + bass * 0.08));
  let alpha = clamp(source.a * 0.9 + recentTrail * 0.25 + predictedTrail * 0.15 + spark * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  var aOut = vec4<f32>(trail, clamp(energy, 0.0, 1.0));
  if (global_id.x == 0u && global_id.y == 0u) { aOut = vec4<f32>(updatedPos, updatedVel); }
  if (global_id.x == 2u && global_id.y == 0u) { aOut = vec4<f32>(time, 0.0, 0.0, 0.0); }
  if (global_id.x == 1u && global_id.y == 0u) { aOut = vec4<f32>(pPosUpd, pVelUpd.x, 7.0 + clamp(pVelUpd.y * 100.0, 0.0, 1.4)); }
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(
    clamp(depth * 0.88 + ellipse * 0.08 + predictedTrail * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0
  ));
}
