// ═══════════════════════════════════════════════════════════════════
//  Magma Fissure
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, stateful-simulation, click-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-27, 2026-11-15
//  Ideas: isotropic 9-point thermal stencil (§12.2D) & buoyant heat haze; T^4 radiative cooling & fractured slag-crust plates
//  A packing: raw [heat, 0.0, 0.0, 1.0]
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0)), w.x), w.y);
}

fn heatAt(coord: vec2<i32>, dims: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
}

fn magmaPalette(t: f32, treble: f32) -> vec3<f32> {
  let cool = vec3<f32>(0.16, 0.012, 0.004);
  let ember = vec3<f32>(1.35, 0.09 + treble * 0.05, 0.01);
  let molten = vec3<f32>(2.8, 0.72, 0.08);
  let whiteHot = vec3<f32>(3.4, 2.25, 0.9);
  let low = mix(cool, ember, smoothstep(0.02, 0.45, t));
  let high = mix(molten, whiteHot, smoothstep(0.72, 1.0, t));
  return mix(low, high, smoothstep(0.42, 0.84, t));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let cooling = clamp(u.zoom_params.x, 0.9, 0.9995);
  let fissureWidth = mix(0.025, 0.24, u.zoom_params.y);
  let haze = mix(0.0, 0.035, u.zoom_params.z) * (1.0 + treble * 0.5);
  let brushRadius = mix(0.025, 0.22, u.zoom_params.w);

  let centerHeat = heatAt(coord, dims);
  // ── Idea 1: isotropic 9-point thermal stencil (§12.2D) ───────────────────
  let heatL = heatAt(coord + vec2<i32>(-1, 0), dims);
  let heatR = heatAt(coord + vec2<i32>(1, 0), dims);
  let heatT = heatAt(coord + vec2<i32>(0, -1), dims);
  let heatB = heatAt(coord + vec2<i32>(0, 1), dims);
  let heatTL = heatAt(coord + vec2<i32>(-1, -1), dims);
  let heatTR = heatAt(coord + vec2<i32>(1, -1), dims);
  let heatBL = heatAt(coord + vec2<i32>(-1, 1), dims);
  let heatBR = heatAt(coord + vec2<i32>(1, 1), dims);
  let neighborMean = 0.20 * (heatL + heatR + heatT + heatB) + 0.05 * (heatTL + heatTR + heatBL + heatBR);
  let lap9 = neighborMean - centerHeat;
  let heatGradient = vec2<f32>(
    (heatR - heatL) * 0.35 + (heatTR + heatBR - heatTL - heatBL) * 0.15,
    (heatB - heatT) * 0.35 + (heatBL + heatBR - heatTL - heatTR) * 0.15
  );

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let brush = smoothstep(brushRadius, brushRadius * 0.12, pointerDist);
  let hoverBranch = pow(max(0.0, 0.5 + 0.5 * sin(atan2(pointerDelta.y, pointerDelta.x) * (5.0 + u.zoom_params.y * 7.0)
                         + pointerDist * 92.0 - noise(floor(uv * 48.0)) * 8.0)), 7.0) * brush;
  let heldHeat = select(brush * 0.08, max(brush * 0.78, hoverBranch), held);

  var clickHeat = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.6) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.22 + bass * 0.12);
      let shell = exp(-abs(rd - front) * (38.0 + u.zoom_params.y * 30.0));
      let angular = 0.55 + 0.45 * noise((uv - ripple.xy) * 75.0 + vec2<f32>(age * 4.0, -age * 2.0));
      clickHeat += shell * angular * exp(-age * 1.1);
    }
  }

  let branchNoise = noise(uv * vec2<f32>(58.0, 31.0) + vec2<f32>(time * 0.18, -time * 0.34));
  let branching = smoothstep(0.78 - fissureWidth * 0.42, 0.91, branchNoise + neighborMean * 0.24 + bass * 0.025);
  let diffusion = centerHeat + lap9 * (0.045 + fissureWidth * 0.18 + mids * 0.025);

  // ── Idea 2: Stefan-Boltzmann T^4 cooling & fractured slag-crust plates ──
  // Exposed mid-temperature lava radiates heat faster than insulated molten cores,
  // solidifying into polygonal basalt plates veined with tensile ember seams.
  let t2 = diffusion * diffusion;
  let radLoss = t2 * t2 * (1.0 - cooling) * 1.45 * (1.0 - smoothstep(0.68, 0.96, diffusion));
  let retained = max(diffusion * cooling - radLoss, 0.0);
  let injected = max(heldHeat * (0.72 + bass * 0.25), clickHeat * (0.82 + bass * 0.3));
  let newHeat = clamp(max(retained, max(injected, branching * neighborMean * 0.985)), 0.0, 1.0);

  let flow = normalize(heatGradient + vec2<f32>(0.0001, 0.0));
  let perpFlow = vec2<f32>(-flow.y, flow.x);
  let shimmer = perpFlow * sin(time * (4.0 + treble * 3.0) + branchNoise * 9.0);
  let buoyantPlume = vec2<f32>(sin(uv.y * 26.0 - time * 3.4 + branchNoise * 5.0) * 0.22, -0.78) * (newHeat * newHeat);
  let hazeOffset = (flow * (newHeat - neighborMean) + shimmer * newHeat * 0.85 + buoyantPlume * 0.65) * haze;
  let distortedUV = clamp(uv + hazeOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let sourceG = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
  let sourceR = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + hazeOffset * 0.22, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let sourceB = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV - hazeOffset * 0.22, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let sourceRGB = vec3<f32>(sourceR, sourceG.g, sourceB);

  let crack = smoothstep(max(0.05, 0.64 - fissureWidth), 0.9, newHeat);
  let crust = smoothstep(0.08, 0.42 + fissureWidth * 0.2, newHeat) * (1.0 - crack);
  let plateUV = vec2<f32>(dot(uv * aspectVec, flow) * 34.0, dot(uv * aspectVec, perpFlow) * 24.0) + vec2<f32>(branchNoise * 2.3);
  let plateJitter = noise(floor(plateUV)) * 0.42;
  let jointDist = min(abs(fract(plateUV.x) - 0.5), abs(fract(plateUV.y + plateJitter) - 0.5));
  let slagPlate = smoothstep(0.045, 0.17, jointDist) * crust;
  let emberSeam = (1.0 - smoothstep(0.0, 0.065, jointDist)) * crust;

  let magma = magmaPalette(newHeat, treble) * (0.72 + bass * 0.5 + mids * newHeat * 0.25);
  var hdr = sourceRGB * (1.0 - crust * (0.62 + slagPlate * 0.24));
  hdr = mix(hdr, magma, clamp(crust * (0.42 - slagPlate * 0.16) + crack * 0.92 + emberSeam * 0.48, 0.0, 1.0));
  hdr += magma * (crack * (0.35 + mids * 0.45) + emberSeam * 0.32);
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(sourceG.a + (1.0 - sourceG.a) * smoothstep(0.05, 0.65, newHeat), 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(newHeat, 0.0, 0.0, 1.0));
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
