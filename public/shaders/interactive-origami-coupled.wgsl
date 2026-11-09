// ═══════════════════════════════════════════════════════════════════
//  Interactive Origami Coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, fluid-simulation, geometric, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-11-09
//  Ideas: capillary pooling in crease valleys; Kármán street along a crease;
//         vorticity confinement (§12.2D); crease gutters (dense fluid drains downhill)
//  Rescue: previous pointer lives in A texel (0,0) (the extraBuffer[133..138] stash is
//          re-uploaded zero every frame, so pointer velocity, vortexDir and the Karman
//          street never ran); Karman phase no longer multiplies time by pointer speed;
//          A.z is now the true curl
//  A packing: raw (vx, vy, curl, density); texel (0,0) = (prevMouse.xy, 7, fract(time))
// ═══════════════════════════════════════════════════════════════════
//  Folded paper creases react to mouse position while viscous fluid
//  drags across the surface, warping the folds. Fluid thickness
//  creates color absorption and vortex streets from fast movement.
//  Alpha stores fluid density.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Rescue R1: previous pointer in A texel (0,0) ─────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so the old stash could
// never persist: prevMouse == mousePos, mouseVel == 0, and every pointer-speed
// term (drag, vortexDir, Karman street) was dead. State = A(0,0) =
// (prevMouse.x, prevMouse.y, GLIDE_MARK, fract(time)); only pixel (0,0) writes it.
// That texel is an edge cell (edge-damped to rest), so every fluid read masks it.
const GLIDE_MARK: f32 = 7.0;

fn loadFluid(coord: vec2<i32>, maxCoord: vec2<i32>) -> vec4<f32> {
  let cc = clamp(coord, vec2<i32>(0), maxCoord);
  let v = textureLoad(dataTextureC, cc, 0);
  return select(v, vec4<f32>(0.0), cc.x == 0 && cc.y == 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let foldScale = mix(2.0, 20.0, u.zoom_params.x);
  let foldDepth = u.zoom_params.y * 0.05;
  let viscosity = mix(0.92, 0.99, u.zoom_params.z);
  let vortexStrength = u.zoom_params.w * 2.0 * (1.0 + mids * 0.25);

  let mousePos = u.zoom_config.yz;
  let stash = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stashOk = abs(stash.z - GLIDE_MARK) < 0.01 && stash.w >= 0.0 && stash.w < 1.0;
  let prevMouse = select(mousePos, stash.xy, stashOk);
  let rawVel = (mousePos - prevMouse) * 60.0;
  // Dead zone: an f16 A texel quantises the stored pointer by ~5e-4, which would read as a
  // constant 0.03 uv/s drift at rest.
  let mouseVel = rawVel * smoothstep(0.04, 0.12, length(rawVel));
  let mouseSpeed = length(mouseVel);

  let px = vec2<f32>(1.0) / resolution;

  let prev = loadFluid(coord, maxCoord);
  let prevVel = prev.xy;

  // ── Idea 1: vorticity confinement (§12.2D) ─────────────────────────
  // The grid solver (advect + viscosity) damps exactly the small swirls the
  // Vortex Strength slider is named for. True curl from the four C neighbours,
  // grad|w| from their stored curl (A.z, one frame old), force = eps * (N x w).
  let nL = loadFluid(coord + vec2<i32>(-1, 0), maxCoord);
  let nR = loadFluid(coord + vec2<i32>(1, 0), maxCoord);
  let nT = loadFluid(coord + vec2<i32>(0, -1), maxCoord);
  let nB = loadFluid(coord + vec2<i32>(0, 1), maxCoord);
  let curl = 0.5 * ((nR.y - nL.y) - (nB.x - nT.x));
  let curlGrad = 0.5 * vec2<f32>(abs(nR.z) - abs(nL.z), abs(nB.z) - abs(nT.z));
  let curlN = curlGrad / (length(curlGrad) + 1e-4);
  let confine = vec2<f32>(curlN.y, -curlN.x) * prev.z * vortexStrength * 0.5;

  let backUV = uv - prevVel * px * 2.0;
  let backCoord = vec2<i32>(clamp(backUV, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution);
  let advected = loadFluid(backCoord, maxCoord);
  let advectedVel = advected.xy;
  let advectedDens = advected.a;

  var vel = (advectedVel + confine) * viscosity;
  var dens = advectedDens * viscosity;

  let toMouse = (uv - mousePos) * aspectVec;
  let dist = length(toMouse);
  let influence = smoothstep(0.15, 0.0, dist);
  vel = vel + mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * aspectVec;
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let uvDir = rToMouse / aspectVec;
      let outward = select(vec2<f32>(0.0), uvDir / max(length(uvDir), 0.001), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let n1 = vec2<f32>(cos(0.5), sin(0.5));
  let n2 = vec2<f32>(cos(2.1), sin(2.1));
  let n3 = vec2<f32>(cos(4.0), sin(4.0));

  let d1 = dot((uv - mousePos) * aspectVec, n1);
  let d2 = dot((uv - mousePos) * aspectVec, n2);
  let d3 = dot((uv - mousePos) * aspectVec, n3);

  let wave1 = abs(sin(d1 * foldScale));
  let wave2 = abs(sin(d2 * foldScale * 0.7));
  let wave3 = abs(sin(d3 * foldScale * 1.3));
  let height = wave1 + wave2 + wave3;

  let delta = 0.01;
  let h_right = abs(sin((d1 + delta) * foldScale)) + abs(sin((d2 + delta) * foldScale * 0.7)) + abs(sin((d3 + delta) * foldScale * 1.3));
  let h_up = abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n1) * foldScale)) +
             abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n2) * foldScale * 0.7)) +
             abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n3) * foldScale * 1.3));
  let grad = vec2<f32>(h_right - height, h_up - height) / delta;

  let foldInfluence = smoothstep(0.8, 0.0, dist);

  // Idea 1 — capillary pooling: density settles into crease valleys
  let valley = 1.0 - clamp(height / 3.0, 0.0, 1.0);
  dens = dens + valley * foldInfluence * (0.018 + bass * 0.012);

  // Idea 2 — Kármán street along crease 1 when the pointer is moving
  // (phase = time alone: multiplying time by pointer speed jumps the phase by time*dSpeed)
  let street = sin(d1 * foldScale * 2.2 - time * 4.0) * sign(d1 + 0.0001);
  let creaseTangent = vec2<f32>(-n1.y, n1.x);
  vel = vel + creaseTangent * street * mouseSpeed * vortexStrength * 0.04 * foldInfluence * (0.6 + treble * 0.4);

  // ── Idea 2: crease gutters ──────────────────────────────────────────
  // Capillary pooling collects fluid in the valleys; thick fluid also *runs* down
  // the crease slope (grad points uphill), so the pools drain along the folds.
  vel = vel - grad * dens * (0.0008 * (1.0 + bass * 0.5)) * foldInfluence;

  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let finalUV = clamp(uv - grad * foldDepth * foldInfluence + vel * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));

  let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

  let lightDir = vec2<f32>(-0.70710678, -0.70710678);
  let gLen = max(length(grad), 0.0001);
  let diffuse = dot(grad / gLen, lightDir);
  let ridge = pow(height / 3.0, 4.0);
  let lighting = (diffuse * 0.5 + ridge) * foldInfluence * 0.5;

  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
  let tinted = baseColor * fluidTint;

  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  var outColor = tinted + vec3<f32>(0.9, 0.95, 1.0) * specular + vec3<f32>(lighting);
  outColor = acesToneMap(outColor);

  // A.z is the true curl of the incoming field (the old `vel.x - vel.y` was not a curl).
  let stateOut = vec4<f32>(vel, curl, dens);
  let isStashTexel = global_id.x == 0u && global_id.y == 0u;
  textureStore(dataTextureA, coord,
               select(stateOut, vec4<f32>(mousePos, GLIDE_MARK, fract(time)), isStashTexel));

  let alpha = clamp(0.22 + dens * 0.38 + foldInfluence * 0.25, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(outColor, alpha));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
