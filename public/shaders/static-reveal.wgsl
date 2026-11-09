// ═══════════════════════════════════════════════════════════════════
//  Static Reveal v3 (VCR Tracking Edition)
//  Category: image
//  Features: mouse-driven, audio-reactive, multi-layer-static, temporal,
//            VCR tracking noise, horizontal hold instability, snow patterns,
//            signal acquisition phase, chrominance noise
//  Upgraded: 2026-09-21, 2026-11-09 (first 2026-08-21, Batch 42 - VCR Tracking)
//  Ideas: vertical-hold roll with a blanking bar while a region is only partly locked;
//         multipath antenna ghost that fades as the signal locks;
//         head-switching noise (sheared foot of the field + snowy switch line);
//         tape dropout bursts (§12.2B: white streak, exponential tail, 6 Hz event windows)
//  A packing: display RGB + reveal mask in alpha
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
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

fn perlinOctaves(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * noise2(pp + t * 0.05 * f32(i + 1));
    pp = pp * 2.03;
    a *= 0.5;
  }
  return v;
}

fn blueNoise(p: vec2<f32>) -> f32 {
  let bayer = hash12(p * 73.0) * 0.25 + hash12(p * 137.0) * 0.25 +
              hash12(p * 251.0) * 0.25 + hash12(p * 379.0) * 0.25;
  return bayer;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let uv = vec2<f32>(global_id.xy) / u.config.zw;
  let aspect = u.config.z / u.config.w;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let decaySpeed = u.zoom_params.x * 0.05;
  let brushRadius = u.zoom_params.y * 0.3 + 0.05;
  let noiseIntensity = clamp(u.zoom_params.z + treble * 0.2, 0.0, 1.0);
  let noiseScale = 30.0 + u.zoom_params.w * 250.0;

  let mouse = u.zoom_config.yz;
  // Was u.zoom_config.y (mouse X), so how much the brush revealed depended on where the cursor
  // sat horizontally. A fixed lock threshold keeps the reveal the same across the frame.
  let revealThreshold = 0.3;
  let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthDecay = mix(0.7, 1.3, depth);
  
  let reactiveRadius = brushRadius * (1.0 + bass * 0.3 + mids * 0.1);
  let prevMask = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).a; // Using alpha for mask
  let brush = smoothstep(reactiveRadius, reactiveRadius * 0.5, dist);
  let mask = clamp(max(prevMask - decaySpeed * depthDecay, brush), 0.0, 1.0);

  let staticTime = time * 2.0;
  
  // VCR Tracking noise - horizontal bands
  let trackingOffset = hash12(vec2<f32>(floor(time * 30.0), floor(uv.y * 50.0))) * 0.05;
  let trackingBand = smoothstep(0.0, 0.1, abs(sin(time * 0.5 + uv.y * 10.0)));
  
  // Horizontal hold instability
  let hHold = sin(uv.y * 30.0 + time * 10.0) * 0.02 * (1.0 - mask) * bass;

  // ── Idea 3: head-switching noise ─────────────────────────────────────
  // A VCR's rotating heads hand over just above the bottom of the field. Sync is torn
  // there, so the last lines are sheared sideways and the switching point prints a
  // snowy bright line. Only unlocked picture shows it — brushed picture has sync.
  let footZone = smoothstep(0.925, 1.0, uv.y);
  let headSkew = footZone * footZone * (0.07 + 0.035 * sin(time * 2.3 + uv.y * 90.0)) * (1.0 - mask);
  let switchOff = (uv.y - 0.935) * 120.0;
  let switchLine = exp(-switchOff * switchOff) * (1.0 - mask);

  let dUV = uv + vec2<f32>(hHold + trackingOffset * trackingBand * (1.0 - mask) + headSkew, 0.0);

  // Snow pattern
  let snowHash = hash22(dUV * 500.0 + time);
  let snow = dot(snowHash, vec2<f32>(0.5)) * noiseIntensity;
  
  // Signal acquisition phase (bright flashes)
  let acqFlash = smoothstep(0.95, 1.0, sin(time * 2.0)) * (1.0 - mask);
  
  let staticFlicker = 1.0 + bass * 0.6 + mids * 0.2;
  
  // Chrominance noise
  let chromaNoiseYUV = vec3<f32>(
      perlinOctaves(dUV * noiseScale, staticTime),
      perlinOctaves(dUV * noiseScale * 0.8 + 10.0, staticTime * 1.1),
      perlinOctaves(dUV * noiseScale * 1.2 - 20.0, staticTime * 0.9)
  );
  
  let grainR = snow + chromaNoiseYUV.y * 0.1;
  let grainG = snow;
  let grainB = snow + chromaNoiseYUV.z * 0.1;
  let grainColor = vec3<f32>(grainR, grainG, grainB) * staticFlicker;

  let vig = smoothstep(1.0, 0.3, length(uv - 0.5) * 1.5);
  let unrevealedVig = (1.0 - mask) * vig;
  
  // Tinted snow based on signal loss
  let tintedGrain = mix(grainColor, grainColor * vec3<f32>(0.5, 0.6, 0.9), unrevealedVig) + acqFlash * 0.2;

  let revealBias = smoothstep(revealThreshold, revealThreshold + 0.2, mask);
  // Idea 1 — vertical-hold roll. A set that has horizontal lock but not vertical lock rolls the
  // picture, with the black vertical-blanking bar passing through it. Only regions the brush has
  // partly locked roll; fully brushed picture holds still.
  let partialLock = smoothstep(0.02, 0.2, mask) * (1.0 - revealBias);
  let rollY = fract(dUV.y + fract(time * 0.23) * partialLock);
  let vUV = vec2<f32>(dUV.x, rollY);
  let blanking = smoothstep(0.0, 0.035, rollY) * smoothstep(1.0, 0.965, rollY);
  let videoColor = textureSampleLevel(readTexture, u_sampler, vUV, 0.0).rgb;
  // Chrominance shift in video color based on tracking
  let shiftAmount = trackingBand * (1.0 - revealBias) * 0.02;
  let videoColorShiftR = textureSampleLevel(readTexture, u_sampler, vUV + vec2<f32>(shiftAmount, 0.0), 0.0).r;
  let videoColorShiftB = textureSampleLevel(readTexture, u_sampler, vUV - vec2<f32>(shiftAmount, 0.0), 0.0).b;
  var finalVideoColor = vec3<f32>(videoColorShiftR, videoColor.g, videoColorShiftB);
  // Idea 2 — multipath ghost. A reflected copy of the signal arrives late and prints as a faint
  // echo displaced to the right; strong while the lock is weak, a trace once fully cleared.
  let ghost = textureSampleLevel(readTexture, u_sampler, clamp(vUV - vec2<f32>(0.028, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let ghostAmt = 0.12 + 0.88 * (1.0 - revealBias) * smoothstep(0.02, 0.15, mask);
  finalVideoColor = mix(finalVideoColor, finalVideoColor * 0.8 + ghost * 0.35, ghostAmt);
  finalVideoColor *= 1.0 - (1.0 - blanking) * partialLock * 0.9;

  var finalColor = mix(tintedGrain, finalVideoColor, revealBias);

  // Idea 3 (cont.): the head-switch line itself — grainy, per-column, at field rate.
  let switchSnow = hash12(vec2<f32>(floor(uv.x * u.config.z * 0.5), floor(time * 30.0)));
  finalColor += vec3<f32>(0.9, 0.95, 1.0) * switchLine * (0.25 + 0.6 * switchSnow) * (0.35 + 0.65 * noiseIntensity);

  // ── Idea 4: tape dropouts (§12.2B dropout bursts) ────────────────────
  // Oxide shed from the tape leaves the head with no signal for a moment: a short
  // white streak on one scanline whose tail dies off to the right. Events live in
  // 6 Hz windows under a smooth envelope, so they come and go instead of strobing.
  let dropLine = floor(uv.y * 270.0);
  let dropWin = floor(time * 6.0);
  let dropEnv = sin(3.14159265 * fract(time * 6.0));
  let dropFire = step(0.975, hash12(vec2<f32>(dropLine, dropWin)));
  let dropStart = hash12(vec2<f32>(dropLine + 7.3, dropWin));
  let dropDx = fract(uv.x - dropStart);
  let dropStreak = dropFire * dropEnv * exp(-dropDx * 11.0) * (1.0 - mask) * (0.3 + 0.7 * noiseIntensity);
  finalColor += vec3<f32>(1.0, 0.98, 0.95) * dropStreak * 0.9;

  finalColor = finalColor + vec3<f32>(unrevealedVig * 0.08, unrevealedVig * 0.05, 0.0);
  finalColor = acesToneMap(finalColor * 1.1);

  let staticStrength = 1.0 - revealBias;
  let alpha = clamp(mask * (1.0 - staticStrength * 0.7) + 0.15 + acqFlash * 0.5, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, mask)); // store mask in alpha
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
