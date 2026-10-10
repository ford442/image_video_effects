// ═══════════════════════════════════════════════════════════════════
//  Pixel Scattering
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-06
//  Ideas: advected history tails along own velocity; vacated-home gaps that refill
//  A packing: linear pre-ACES RGB; .a = 2 + vacancy (0..1); .a outside [2,3] reads as no vacancy
//  Motion: curl velocity field advection + Fibonacci scatter + click shock rings
//  History: hygiene/motion pass 2026-09-06
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ScatterRadius, y=ScatterDistance, z=TrailLength, w=Chaos

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.015;
  let n = noise2(p + vec2<f32>(0.0, eps) + t);
  let s = noise2(p - vec2<f32>(0.0, eps) + t);
  let e = noise2(p + vec2<f32>(eps, 0.0) + t);
  let w = noise2(p - vec2<f32>(eps, 0.0) + t);
  return vec2<f32>(n - s, -(e - w)) / (2.0 * eps);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // FIX: the extraBuffer[133..138] spring never persisted (buffer is re-uploaded every frame),
  // so it always collapsed to the raw pointer — use the pointer directly.
  let spring = mouse;

  // Four saved controls preserved
  let scatterRadius = mix(0.08, 0.75, u.zoom_params.x);
  let scatterDistance = mix(0.01, 0.18, u.zoom_params.y);
  let trailLength = mix(0.1, 1.0, u.zoom_params.z);
  let chaos = u.zoom_params.w;

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.7, 1.3, depth);

  // Proximity to spring cursor
  let toSpring = (uv - spring) * aspectVec;
  let distSpring = length(toSpring);
  let mouseInteraction = smoothstep(scatterRadius, 0.01, distSpring) * select(1.0, 1.6, held);

  // Click ripple wavefronts
  var rippleScatter = 0.0;
  var rippleDir = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let dVec = (uv - r.xy) * aspectVec;
      let d = length(dVec);
      let ring = exp(-abs(d - age * 0.46) * 30.0) * exp(-age * 1.5);
      rippleScatter += ring;
      if (d > 0.001) {
        rippleDir += (dVec / d) * ring;
      }
    }
  }

  // Curl noise velocity
  let curlCoord = uv * 6.0 + vec2<f32>(time * 0.12, -time * 0.08);
  let curlVel = curlNoise(curlCoord, time * 0.2) * (0.01 + chaos * 0.035) * (1.0 + mids * 0.5);

  // Fibonacci spiral angle component
  let fibCell = floor(uv * 45.0);
  let fibIndex = hash12(fibCell + cell_time(time));
  let fibAngle = fibIndex * 2.39996 + time * (0.5 + chaos);
  let fibDir = vec2<f32>(cos(fibAngle), sin(fibAngle));

  // Tangential vortex rotation around pointer
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-toSpring.y, toSpring.x) / max(distSpring, 0.001), distSpring > 0.001);

  // Combined physical velocity vector in aspect-corrected space; convert back to UV once for sampling.
  let mouseWind = tangent * mouseInteraction * (0.02 + scatterDistance * 0.6);
  let bassKick = 1.0 + bass * 0.7;
  let shockKick = rippleDir * (0.03 + scatterDistance * 0.8);
  let curlVelAspect = curlVel * aspectVec;
  let fibDrift = fibDir * (chaos * 0.015) * aspectVec;

  let velocityAspect = (mouseWind + curlVelAspect + fibDrift + shockKick) * bassKick * depthFactor;
  let velocity = velocityAspect / aspectVec;
  let velMag = length(velocityAspect);

  // Multi-tap advection accumulation
  var accum = vec3<f32>(0.0);
  let sampleCount = 6;
  let stepMult = trailLength * 0.012;
  var weightSum = 0.0;

  for (var k: i32 = 0; k < sampleCount; k = k + 1) {
    let t = f32(k) / f32(sampleCount - 1);
    let sampleUV = clamp(uv - velocity * (f32(k) * 2.5) * stepMult, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Chromatic separation along velocity vector
    let chroma = velMag * 0.04 * (1.0 + treble * 0.8) * t;
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + velocity * chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - velocity * chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    let w = 1.0 - t * 0.6;
    accum += vec3<f32>(rSample, gSample, bSample) * w;
    weightSum += w;
  }
  let blurred = accum / max(weightSum, 1e-4);

  // Velocity excitation glow
  let glowPalette = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + velMag * 80.0 + time * 2.0);
  let glow = glowPalette * velMag * (12.0 + treble * 8.0) * (mouseInteraction + rippleScatter * 0.8);

  var hdr = blurred + glow;

  // Idea 1: advected history tails — read C upstream along this pixel's own velocity, so the
  // streak tail left last frame travels with the scattered pixels instead of ghosting in place.
  let histUV = clamp(uv - velocity * (0.1 + trailLength * 0.3), vec2<f32>(0.0), vec2<f32>(1.0));
  let histCoord = clamp(vec2<i32>(histUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let hist = textureLoad(dataTextureC, histCoord, 0);
  // FIX: guard NaN / garbage left in C by a previous shader.
  let histRGB = clamp(select(vec3<f32>(0.0), hist.rgb, hist.rgb == hist.rgb), vec3<f32>(0.0), vec3<f32>(16.0));
  let feedbackWeight = mix(0.08, 0.35, clamp(velMag * 20.0 + mouseInteraction * 0.3, 0.0, 1.0));
  hdr = mix(hdr, histRGB, feedbackWeight);

  // Idea 2: vacated-home gaps. Pixel blocks kicked out of their home leave a hole that refills.
  // Vacancy rides in A.a as 2 + v (anything outside [2,3] is a foreign alpha -> no vacancy),
  // advected with the same upstream read as the tails.
  let vacRaw = select(0.0, hist.a, hist.a == hist.a);
  let vacPrev = select(0.0, vacRaw - 2.0, vacRaw >= 2.0 && vacRaw <= 3.0);
  //   (a) Fibonacci launch: every 0.5 s a chaos-gated ~8%*chaos of the 45-grid cells are blown out
  let launchEpoch = floor(time * 2.0);
  let launchHash = hash12(fibCell * 1.37 + vec2<f32>(launchEpoch * 17.13, launchEpoch * 3.71));
  let launch = step(1.0 - chaos * 0.08, launchHash) * exp(-fract(time * 2.0) * 8.0);
  //   (b) the eye of the pointer vortex is emptied while held (idle pointer parks at the frame
  //       centre, so an always-on eye would stamp a permanent dark disc there)
  let eye = mouseInteraction * smoothstep(0.06, 0.0, distSpring) * select(0.0, 1.0, held);
  //   (c) click shock rings punch a travelling gap
  let excite = clamp(max(launch, max(eye, rippleScatter * 1.2)), 0.0, 1.0);
  let vacancy = clamp(max(vacPrev * 0.94, excite), 0.0, 1.0);
  let refillGlint = 4.0 * vacancy * (1.0 - vacancy);
  let shown = mix(hdr, hdr * 0.15, vacancy * 0.8) + hdr * refillGlint * 0.18;

  let finalRGB = acesToneMap(max(shown, vec3<f32>(0.0)));
  let semanticAlpha = clamp(0.70 + velMag * 15.0 + mouseInteraction * 0.25 + rippleScatter * 0.3, 0.0, 1.0)
                    * (1.0 - 0.5 * vacancy);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  // Store the un-holed colour so gaps do not compound into the tails.
  textureStore(dataTextureA, coord, vec4<f32>(hdr, 2.0 + vacancy));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + velMag * 2.0, 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn cell_time(t: f32) -> vec2<f32> {
  return vec2<f32>(sin(t * 0.3), cos(t * 0.3));
}
