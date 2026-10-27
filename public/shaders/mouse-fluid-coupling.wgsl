// ═══════════════════════════════════════════════════════════════════
//  Fluid Coupling
//  Category: interactive-mouse
//  Features: mouse-driven, fluid-simulation, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-26
//  Ideas: speed-thinning (§12.2C); Kármán street
//  A packing: raw vel.xy, vorticity, density
//  Pointer: extraBuffer[133..134] previous mouse, [136] seeded
// ═══════════════════════════════════════════════════════════════════
//  The mouse drags a viscous fluid over the image. Fluid thickness
//  determines color absorption and blur. Fast movement sheds a street.
//  Alpha carries fluid density. A is the sim, not display.

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(pixel: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn historyBilinear(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let p = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(dims) - vec2<f32>(0.5);
  let base = vec2<i32>(floor(p));
  let f = fract(p);
  let s00 = loadC(base, dims);
  let s10 = loadC(base + vec2<i32>(1, 0), dims);
  let s01 = loadC(base + vec2<i32>(0, 1), dims);
  let s11 = loadC(base + vec2<i32>(1, 1), dims);
  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let dims = vec2<i32>(resolution);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let viscosity = mix(0.92, 0.99, u.zoom_params.x);
  let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
  let colorShift = u.zoom_params.z;
  let vortexStrength = u.zoom_params.w * 2.0;

  // Previous pointer lives in extraBuffer. The old (0,0) texel was
  // overwritten by the fluid store every frame, so drag never persisted.
  let mousePos = u.zoom_config.yz;
  let canPersist = arrayLength(&extraBuffer) > 136u;
  var prevMouse = mousePos;
  if (canPersist && extraBuffer[136] > 0.5) {
    let stored = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (stored.x >= 0.0 && stored.x <= 1.0 && stored.y >= 0.0 && stored.y <= 1.0) {
      prevMouse = stored;
    }
  }
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);
  if (canPersist && global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = mousePos.x;
    extraBuffer[134] = mousePos.y;
    extraBuffer[136] = 1.0;
  }

  let px = vec2<f32>(1.0) / resolution;
  let prevState = historyBilinear(uv, dims);
  let prevVel = prevState.xy;

  let backUV = clamp(uv - prevVel * px * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = historyBilinear(backUV, dims);

  var vel = advected.xy * viscosity;
  var dens = advected.w * viscosity;

  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let influence = smoothstep(mouseRadius, 0.0, dist);

  vel = vel + mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  // ── Idea 1: speed-thinning (§12.2C) ────────────────────────────
  // A slow stroke pools. A fast stroke leaves a thread. Viscosity
  // still decays whatever was deposited.
  let thin = 1.0 / (1.0 + mouseSpeed * 2.2);
  dens = dens + influence * thin * 0.018;

  // ── Idea 2: Kármán street ──────────────────────────────────────
  // Alternating shed vortices in the wake behind the pointer.
  // Quiet when the pointer is still. Vortex strength still scales it.
  let wakeSpeed = max(mouseSpeed, 0.001);
  let wakeDir = mouseVel / wakeSpeed;
  let behind = (mousePos - uv) * vec2<f32>(aspect, 1.0);
  let along = dot(behind, wakeDir);
  let across = abs(dot(behind, vec2<f32>(-wakeDir.y, wakeDir.x)));
  let streetPhase = sin(along * 42.0 - time * 7.0);
  let streetMask = smoothstep(0.0, 0.015, along) * exp(-along * 2.4) * exp(-across * 16.0);
  let shedding = smoothstep(0.05, 0.22, mouseSpeed);
  vel = vel + vec2<f32>(-wakeDir.y, wakeDir.x) * streetPhase * streetMask * vortexStrength * shedding * 0.15;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;

  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let blurAmount = dens * colorShift * 0.02;
  let blurUV = clamp(uv + vel * blurAmount * 5.0, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, blurUV, 0.0);

  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * colorShift);
  let tinted = baseColor.rgb * fluidTint;

  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  let outColor = tinted + vec3<f32>(0.9, 0.95, 1.0) * specular;

  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));

  let alpha = clamp(dens * 0.45 + influence * 0.12 + baseColor.a * 0.35, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces(max(outColor, vec3<f32>(0.0))), alpha));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
