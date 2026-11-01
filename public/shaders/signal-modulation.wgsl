// ═══════════════════════════════════════════════════════════════════
//  Signal Modulation
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-01
//  Ideas: AM excursion; zero-crossing ticks
//  A packing: ACES display RGBA (C is not read)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

fn huePreserveClamp(col: vec3<f32>, maxRGB: f32) -> vec3<f32> {
  let mx = max(max(col.r, col.g), col.b);
  if (mx > maxRGB) {
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    return mix(col * (maxRGB / mx), vec3<f32>(lum), 0.15);
  }
  return col;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    let depthAtten = mix(1.0, 0.6, depth);

    // ── Slider params (saved-preset contract: same roles, same order) ──
    //  x 'Base Frequency'  → carrier frequency, swollen by the bass envelope
    //  y 'Distortion Amt'  → carrier amplitude / displacement strength
    //  z 'Scroll Speed'    → phase scroll rate of the carrier
    //  w 'Color Split'     → r/b chromatic separation around the signal line
    let freq = mix(1.0, 50.0, u.zoom_params.x) * bass_env(bass, mids);
    let amp = mix(0.0, 0.5, u.zoom_params.y) * (1.0 + mids * 0.3);
    let speed = mix(0.0, 10.0, u.zoom_params.z) * (1.0 + treble * 0.25);
    let colorSplit = u.zoom_params.w * 0.02 * (1.0 + bass * 0.1);
    let lineWidth = (0.006 + amp * 0.03) * select(1.0, 1.25, held);

    var springPos = mousePos;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[138] > 0.5) {
      springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
      var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
      if (extraBuffer[138] <= 0.5) {
        springPos = mousePos;
        springVel = vec2<f32>(0.0);
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 9.0;
        let accel = (mousePos - springPos) * (omega * omega) - springVel * (2.0 * omega);
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

    // Carrier wave construction: the proximity warp now measures distance to
    // the spring-glided origin, so the waveform eases after the cursor.
    let proximity = distance(uv, springPos);
    let phase = (uv.x + proximity * 2.0) * freq + time * speed;
    // ── Idea 1: AM excursion
    // The carrier amplitude swells with the FFT band under this row.
    // The distortion slider stays the depth.
    let band = floor(uv.y * 8.0);
    let bandFFT = fftBin(u32(clamp(band, 0.0, 7.0)));
    let am = 1.0 + bandFFT * 0.45;
    let wave = 0.5 + amp * am * sin(phase);
    let distanceToWave = abs(uv.y - wave);

    // ── Click carrier bursts ──
    // Each live ripple injects a decaying signal spike at its click point and
    // extra chromatic split inside an expanding radial band (~1.2s fade).
    var clickBoost = 0.0;
    var clickChroma = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age <= 0.0 || age > 1.2) { continue; }
        let ringDist = distance(uv, rp.xy);
        let ringRadius = age * 0.35;
        let ringDelta = (ringDist - ringRadius) * 10.0;
        let ringBand = exp(-ringDelta * ringDelta);
        let fade = 1.0 - age / 1.2;
        let pulse = ringBand * fade * fade;
        clickBoost = clickBoost + pulse;
        clickChroma = clickChroma + pulse;
    }

    var signal = 1.0 - smoothstep(lineWidth, lineWidth + 0.005, distanceToWave);
    signal = clamp(signal + clickBoost * 0.85, 0.0, 1.0);
    // ── Idea 2: zero-crossing ticks
    // Short vertical marks where the carrier crosses the mid-line.
    let tick = exp(-abs(sin(phase)) * 36.0) * smoothstep(0.04, 0.0, abs(uv.y - 0.5)) * smoothstep(0.02, 0.12, amp);
    signal = clamp(max(signal, tick * 0.9), 0.0, 1.0);
    let displacement = signal * amp * 0.1;

    // Spectral band visualization: divide screen into 8 frequency bands.
    // Bands 0-7 read engine FFT bins extraBuffer[5..12].
    // The hash survives only as a slow ±10% jitter. The bass boost stays on top.
    let bandJitter = fract(sin(band * 12.9898 + floor(time * 4.0)) * 43758.5453);
    let bandAmp = mix(0.1, 1.0, bandFFT) * (1.0 + bass * 0.5) * (0.9 + 0.2 * bandJitter);
    let bandMask = smoothstep(0.0, 0.02, abs(fract(uv.y * 8.0) - 0.5)) * signal * bandAmp;

    let baseUV = clamp(uv + vec2<f32>(0.0, displacement), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let offset = vec2<f32>(colorSplit * (1.0 + clickChroma * 2.0) * signal * (0.5 + treble * 0.5), 0.0);
    let uvR = clamp(baseUV + offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvG = baseUV;
    let uvB = clamp(baseUV - offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
    let glow = vec3<f32>(0.15 + bandMask * 0.5, 0.35 + treble * 0.08 + bandMask * 0.3, 0.55 + bandMask * 0.2) * signal;
    var finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
        baseColor.g,
        textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
    ) + glow;

    // Noise floor
    let noiseFloor = (fract(sin(dot(uv + time, vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.02 * signal;
    finalColor = finalColor + vec3<f32>(noiseFloor);

    finalColor = huePreserveClamp(finalColor, 1.8) * depthAtten;
    finalColor = acesToneMap(finalColor * (0.96 + bass * 0.05));
    let alpha = clamp(baseColor.a * 0.45 + signal * 0.35 + bass * 0.05 + bandMask * 0.2, 0.08, 1.0);
    let depthOut = clamp(depth + signal * 0.04, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
