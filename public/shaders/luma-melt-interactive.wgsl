// ═══════════════════════════════════════════════════════════════════
//  Luma Melt
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-06
//  Ideas: molten-temperature memory (drips re-solidify); ledge pooling + meniscus lip
//  A packing: linear pre-ACES melt RGB (advected history mix, no display glow); A.a = molten temperature 0..1
//  History: created 2024-01-01; upgraded-rgba 2026-05-31; chunks warpedFBM, curl2D, bass_env
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// ═══ CHUNK: valueNoise ═══
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ═══ CHUNK: fbm ═══
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

// ═══ CHUNK: curl2D ═══
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t * 0.1, 3);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t * 0.1, 3);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

// ═══ CHUNK: bass_env ═══
fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.6 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let held = step(0.5, u.zoom_config.w);

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let meltSpeed = u.zoom_params.x * 0.03 * bass_env(bass, mids);
    let persistence = clamp(u.zoom_params.y, 0.5, 0.99);
    let radius = max(u.zoom_params.z, 0.01);
    let heat = u.zoom_params.w * 0.15;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Heat lowers viscosity; deep pixels remain more cohesive.
    let viscosity = clamp(mix(0.35, 1.0, depth) / (1.0 + heat * 3.0 + bass * 0.35), 0.18, 1.0);

    let diff = uv - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let mouseFactor = smoothstep(radius, 0.0, dist) * mix(0.12, 1.0, held);

    var clickHeat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
      let ripple = u.ripples[rippleIndex];
      let rippleAge = time - ripple.z;
      if (rippleAge < 0.0 || rippleAge > 3.2) { continue; }
      let rippleDelta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let front = abs(length(rippleDelta) - rippleAge * (0.17 + bass * 0.10));
      clickHeat += exp(-front * 125.0) * exp(-rippleAge * 1.55);
    }

    let newColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(newColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let meltMask = smoothstep(0.28 + heat * 0.12, 0.78 - heat * 0.08, luma);
    let branchNoise = fbm(vec2<f32>(uv.x * 11.0, uv.y * 4.0 - time * meltSpeed * 24.0), 4);
    let branch = smoothstep(0.54, 0.78, branchNoise + luma * 0.22) * meltMask;
    let meltRunner = pow(max(0.0, sin((uv.y + uv.x * (0.18 + branch * 0.2)) * 46.0 - time * (13.0 + mids * 6.0))), 14.0) * meltMask;
    let dripPacket = pow(max(0.0, sin(uv.y * 62.0 + branchNoise * 8.0 - time * (18.0 + treble * 7.0))), 18.0) * branch;
    let curl = curl2D(uv * 3.0, time * 0.2) * meltSpeed * (1.0 + bass * 0.5);
    let gravity = vec2<f32>((branch - 0.5) * meltSpeed * 0.16, meltSpeed * luma * meltMask * (1.0 + meltRunner * 0.7 + branch * 0.5));

    // IDEA 1 — molten-temperature memory. Last frame's temperature at this pixel (A.a) sets how
    // runny the melt is here; hot pixels flow up to 1.6x, cooled ones re-solidify toward 0.6x.
    let coord = vec2<i32>(global_id.xy);
    let hereTempRaw = textureLoad(dataTextureC, coord, 0).a;
    let hereTemp = clamp(select(0.0, hereTempRaw, hereTempRaw == hereTempRaw), 0.0, 1.0);
    let fluidity = mix(0.6, 1.6, smoothstep(0.05, 0.6, hereTemp));

    // IDEA 2 — ledge pooling. Molten pixel above a non-melting (dark) pixel = a ledge: the downward
    // flow stalls and the drip pools on the lip.
    let belowUV = vec2<f32>(uv.x, min(uv.y + 4.0 / resolution.y, 1.0));
    let lumaBelow = dot(textureSampleLevel(readTexture, u_sampler, belowUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let meltBelow = smoothstep(0.28 + heat * 0.12, 0.78 - heat * 0.08, lumaBelow);
    let ledge = smoothstep(0.08, 0.5, meltMask - meltBelow);

    let flow = (curl + gravity) * viscosity * fluidity;

    var totalFlow = flow + vec2<f32>(0.0, heat * (mouseFactor + clickHeat * 0.8 + dripPacket * 0.18));
    totalFlow.y = totalFlow.y * (1.0 - 0.85 * ledge);
    let sourceUV = clamp(uv - totalFlow, vec2<f32>(0.0), vec2<f32>(1.0));

    let historyCoord = clamp(vec2<i32>(sourceUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let historyRaw = textureLoad(dataTextureC, historyCoord, 0);
    let historyOk = all(historyRaw == historyRaw);
    // NaN fallback: source colour at ambient temperature 0 (newColor.a is coverage, not heat).
    let history = select(vec4<f32>(newColor.rgb, 0.0), clamp(historyRaw, vec4<f32>(0.0), vec4<f32>(16.0)), historyOk);

    // Temperature advects with the melt, cools ~3%/frame, and is re-heated by bright luma
    // (Heat Intensity), the pointer and click fronts.
    let heatIn = max(meltMask * u.zoom_params.w * 0.6, max(mouseFactor, min(clickHeat, 1.0)));
    let temp = clamp(max(history.a * 0.97, heatIn), 0.0, 1.0);

    // Pooled drips hold longer on the ledge.
    let localPersist = min(persistence + 0.08 * ledge, 0.99);
    let trebleGlow = treble * 0.1 * mouseFactor;
    let blended = mix(newColor, history, localPersist);
    let heated = blended + vec4<f32>(trebleGlow + meltRunner * mids * 0.05,
                                     trebleGlow * 0.5 + clickHeat * 0.05,
                                     trebleGlow * 0.2 + dripPacket * treble * 0.04,
                                     0.0);

    let meltAlpha = clamp(luma * 0.8 + mouseFactor * 0.3 + bass * 0.15, 0.0, 1.0);
    let molten = smoothstep(0.45, 1.0, temp);
    var hdr = heated.rgb + vec3<f32>(0.45, 0.12 + mids * 0.18, 0.04 + treble * 0.12) * (branch + clickHeat + molten * 0.6) * heat * 0.24;
    // Meniscus: the pooled lip catches light.
    hdr = hdr + vec3<f32>(1.0, 0.92, 0.8) * ledge * 0.10 * (0.4 + 0.6 * smoothstep(0.05, 0.6, temp));
    hdr = max(hdr, vec3<f32>(0.0));
    let mapped = clamp((hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    let finalColor = vec4<f32>(mapped, clamp(meltAlpha + branch * 0.12 + clickHeat * 0.08 + ledge * 0.1, 0.0, 1.0));

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, vec4<f32>(clamp(blended.rgb, vec3<f32>(0.0), vec3<f32>(16.0)), temp));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
