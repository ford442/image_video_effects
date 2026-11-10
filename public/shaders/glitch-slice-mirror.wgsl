// ═══════════════════════════════════════════════════════════════════
//  Glitch Slice Mirror — Batch 62
//  Category: glitch
//  Features: mouse-driven, audio-reactive, upgraded-rgba, click-reactive, held-drag, aces-tone-map
//  Upgraded: 2026-11-09
//  Ideas: macroblock hold (block quantization, §12.2B); interlace comb at the seam (field interlace, §12.2B)
//  A packing: ACES display RGBA (C only read for the packet echo)
//  fp128 seam integration, racing horizontal fracture packet, capped click
//  bands, held widens glitch halo, per-block tears, ACES applied once + semantic alpha.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 {
  return Fp128(x, 0.0);
}

fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  let f = e - (t - s);
  return Fp128(t, f);
}

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Reflect t back into [0,1] (t in [-1,2] is enough here: seam in [0,1], uv in [0,1], small tears).
fn pingPong01(t: f32) -> f32 {
  let a = abs(t);
  return clamp(1.0 - abs(1.0 - a), 0.0, 1.0);
}

fn fracture_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (1.8 + speed * 5.0));
  let d = abs(uv.x - head);
  return pow(max(0.0, 1.0 - d * 16.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let aspect = u.config.z / max(u.config.w, 0.001);
    let held = u.zoom_config.w > 0.5;
    // Rescue R3: HEAD's spring lived in extraBuffer[133..138], which the host zeroes every frame, so its
    // guard (extraBuffer[138] > 0.5) was never true and `mouse` was already the raw cursor. Dead block removed.
    let mouse = u.zoom_config.yz;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let paramIntensity = u.zoom_params.x;
    let paramSpeed = u.zoom_params.y;
    let paramScale = u.zoom_params.z;
    let paramDetail = u.zoom_params.w;

    let audioBoost = (1.0 + bass * 0.5 + mids * 0.25) * (1.0 + select(0.0, 0.2, held));

    var clickShift = 0.0;
    var clickDamage = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      let safeAge = max(age, 0.0);
      // fades 0.9 -> 1.4 s and is exactly 0 at the cutoff (HEAD cut at exp(-2.8) = 0.06 with a step: a visible pop)
      let live = step(0.0, age) * (1.0 - smoothstep(0.9, 1.4, age));
      let yBand = 1.0 - smoothstep(0.012, 0.085, abs(uv.y - rp.y));
      let xWindow = 1.0 - smoothstep(0.12, 0.75, abs(uv.x - rp.x) * aspect);
      let damage = yBand * (0.3 + xWindow * 0.7) * exp(-safeAge * 2.0) * live;
      let direction = select(-1.0, 1.0, fract(rp.x * 29.0 + rp.y * 13.0) > 0.5);
      clickShift += damage * direction * (0.035 + paramIntensity * 0.05);
      clickDamage = max(clickDamage, damage);
    }

    let seamPhase = fp128_sum(fp128(mouse.x), fp128(clickShift));
    let seamX = clamp(fp128_val(seamPhase), 0.0, 1.0);
    let packet = fracture_packet(uv, time, paramSpeed);

    let mirrorActive = uv.x > seamX;
    var target_uv = uv;
    target_uv.x = select(target_uv.x, seamX - (uv.x - seamX), mirrorActive);

    let glitch_width = 0.1 * max(paramIntensity * 2.0, 0.001) * select(1.0, 1.3, held);
    let dist_to_seam = abs(uv.x - seamX);

    let seamIntensity = clamp(1.0 - dist_to_seam / max(glitch_width, 0.001), 0.0, 1.0) * audioBoost;
    // Soft gate (HEAD: binary `dist < width || click > 0.02 || packet > 0.05`): the halo, the click bands and the
    // fracture packet fade the glitch in over their first 0.05 of strength, so scanline bars and the mix do not
    // start/stop abruptly at the halo edge. Interior of the halo is unchanged.
    let glitchAmt = smoothstep(0.0, 0.05, max(seamIntensity, max(clickDamage, packet)));
    let intensity = max(seamIntensity, clickDamage * audioBoost) * glitchAmt;

    let block_size = max(vec2<f32>(
        0.02 + paramScale * 0.06,
        0.01 + paramScale * 0.02
    ), vec2<f32>(0.001));
    // Rescue R5: HEAD hashed fract(floor(uv/block) + time*k) = fract(time*k) for EVERY block (the integer cell
    // drops out of fract), so the "block tears" were one whole-frame flicker. Hash the block id plus a step
    // that advances at the Speed-driven cadence instead, so blocks tear independently. R4: the FFT read
    // plasmaBuffer[1..8] is out of range (single-vec4 buffer), replaced by the real bass.
    let blockId = floor(uv / block_size);
    let seedStep = floor(time * (0.15 + paramSpeed * 2.5));
    let noise = fract(hash(blockId + vec2<f32>(seedStep, seedStep * 0.37)) + bass * 0.17 + treble * clickDamage * 0.25);

    let bigNoise = noise > 0.8;
    let tearX = select(0.0, (noise - 0.5) * 0.1 * intensity, bigNoise);
    target_uv.x = target_uv.x + tearX;

    // ── Idea 2: interlace comb at the seam (§12.2B field interlace) ──
    // A broadcast tear starts as an interlace field offset: even rows shift one way, odd rows the other,
    // inside the glitch halo and the click bands. Static per row parity — no per-frame strobing.
    let rowSign = select(-1.0, 1.0, (global_id.y & 1u) == 0u);
    target_uv.x = target_uv.x + rowSign * (0.003 + paramDetail * 0.02) * intensity;
    // Ping-pong fold: with the seam left of 0.5 the mirrored column goes below 0 and HEAD clamped it to column 0,
    // painting a flat stripe over uv.x > 2*seam (20 % of the frame at seam 0.4). Reflect it back instead.
    target_uv = vec2<f32>(pingPong01(target_uv.x), clamp(target_uv.y, 0.0, 1.0));

    let split = (0.005 + paramDetail * 0.03) * (intensity + clickDamage * 0.8 + packet * 0.5) * noise;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(target_uv + vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(target_uv - vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // ── Idea 1: macroblock hold (§12.2B block quantization) ──
    // A torn block is a failed macroblock: it stops being a continuous picture and holds ONE colour, posterised.
    // One tap at the block centre (mirrored and torn the same way as its pixels), Q from Scale, strength
    // from the existing seam/click intensity.
    var blockTap = (blockId + 0.5) * block_size;
    blockTap.x = select(blockTap.x, seamX - (blockTap.x - seamX), blockTap.x > seamX);
    blockTap = vec2<f32>(pingPong01(blockTap.x + tearX), clamp(blockTap.y, 0.0, 1.0));
    let levels = mix(8.0, 4.0, paramScale);
    let blockQ = floor(clamp(textureSampleLevel(readTexture, u_sampler, blockTap, 0.0).rgb, vec3<f32>(0.0), vec3<f32>(1.0)) * levels + 0.5) / levels;
    let holdAmt = clamp(intensity, 0.0, 1.0) * 0.75 * f32(bigNoise);
    let tornRgb = mix(vec3<f32>(r, g, b), blockQ, holdAmt);

    let lum = dot(tornRgb, vec3<f32>(0.299, 0.587, 0.114));
    var glitchColor = vec4<f32>(tornRgb, clamp(lum, 0.3, 1.0));

    let scanline = sin(uv.y * (50.0 + paramDetail * 300.0));
    let inScanline = scanline > 0.9;
    glitchColor = select(glitchColor, vec4<f32>(glitchColor.rgb * 0.5, glitchColor.a), inScanline);

    let baseColor = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0);
    let finalColor = mix(baseColor, glitchColor, glitchAmt);

    // Rescue R2: HEAD ran ACES on the glitch colour AND again on the composite, so the halo was lifted and
    // flattened twice (brighter, lower contrast than the picture around it). ACES now runs once, on the
    // composite (clamped >= 0 first).
    let toned = acesToneMap(max(finalColor.rgb * (0.96 + mids * 0.04), vec3<f32>(0.0)));
    let prev = textureLoad(dataTextureC, coords, 0);
    let displayRgb = mix(toned, prev.rgb, packet * 0.12);
    let finalLum = dot(displayRgb, vec3<f32>(0.299, 0.587, 0.114));
    let finalAlpha = clamp(0.5 + intensity * 0.3 + finalLum * 0.2 + packet * 0.1, 0.06, 0.98);
    // Rescue R1: HEAD assigned `finalColor.rgb = …` (swizzle assignment — naga rejects it); built whole here.
    let outColor = vec4<f32>(displayRgb, finalAlpha);

    let depth = textureLoad(readDepthTexture, coords, 0).r;

    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, coords, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
