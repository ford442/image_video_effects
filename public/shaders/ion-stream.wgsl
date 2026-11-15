// ═══════════════════════════════════════════════════════════════════
//  Ion Stream
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-11-15
//  Ideas: charge split; cyclotron tightening; sausage pinch; magnet pile-up
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let q = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), q.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), q.x), q.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let speed = mix(1.0, 8.0, u.zoom_params.x);
    let curlStrength = u.zoom_params.y;
    let streamDensity = max(u.zoom_params.z, 0.02);
    let colorIntensity = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;

    let phaseNoise = valueNoise(uv * 5.0 + vec2<f32>(time * 0.16, -time * 0.11));
    let flow = vec2<f32>(cos(phaseNoise * 6.283 + time), sin(phaseNoise * 6.283 - time * 0.7)) * curlStrength;
    let advectedUV = clamp(uv + flow * 0.018 * (1.0 + audio.x * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDelta = vec2<f32>((uv.x - u.zoom_config.y) * aspect, uv.y - u.zoom_config.z);
    let safeDist = max(length(mouseDelta), 0.001);
    let bendDir = vec2<f32>(-mouseDelta.y, mouseDelta.x) / safeDist;
    let magnetic = exp(-safeDist * 5.0) * (0.004 + curlStrength * 0.018) * (1.0 + u.zoom_config.w);
    let bentUV = clamp(advectedUV + bendDir * magnetic, vec2<f32>(0.0), vec2<f32>(1.0));
    let source = textureSampleLevel(readTexture, u_sampler, bentUV, 0.0);

    let lanes = max(2.0, floor(4.0 + streamDensity * 42.0));
    let lane = floor(uv.x * lanes);
    let laneCenter = (lane + 0.5) / lanes;
    // Field strength of the cursor magnet (hover half, held full), shared by both ideas.
    let fieldB = exp(-safeDist * 5.0) * (1.0 + u.zoom_config.w) * 0.5;
    // Idea 2 — cyclotron tightening. Gyration frequency grows with B and the Larmor radius
    // shrinks as 1/B, so near the magnet the helix coils into a tight, fast spring.
    let cyclo = 1.0 + fieldB * 4.0;
    // ── Idea 3: sausage pinch ────────────────────────────────────────
    // A beam's radius breathes along its length. Stream Speed sets the rate,
    // Stream Density sets how deep the waist goes.
    let sausage = sin(uv.y * (9.0 + streamDensity * 14.0) - time * speed * 0.65);
    let pinch = 1.0 + sausage * 0.42 * clamp(streamDensity, 0.0, 1.0);
    let helix = sin(lane * 2.17 + uv.y * 18.0 * cyclo - time * speed * (1.0 + fieldB * 2.0))
        * (0.018 + curlStrength * 0.05) / (1.0 + fieldB * 3.0) * pinch;
    // Idea 1 — charge split. Alternate lanes carry opposite charge, so the magnet pushes them
    // opposite ways and the stream parts around the cursor like a mass spectrometer.
    let charge = select(-1.0, 1.0, (i32(lane) & 1) == 0);
    let deflect = charge * fieldB * (0.45 / lanes) * (0.5 + curlStrength);
    let coreDist = abs(uv.x - laneCenter - helix - deflect);
    let core = exp(-coreDist * (90.0 + streamDensity * 140.0) / max(pinch, 0.35));
    let packetPhase = fract(uv.y * (3.0 + streamDensity * 9.0) - time * speed * 0.42 + lane * 0.173);
    // ── Idea 4: magnet pile-up ────────────────────────────────────────
    // Packets tighten where fieldB is strong, so the beam stalls at the cursor.
    let packetWidth = 0.10 / (1.0 + fieldB * 2.0);
    let packetDelta = (packetPhase - 0.5) / max(packetWidth, 0.02);
    let packet = exp(-packetDelta * packetDelta);
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.6) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.24 + audio.x * 0.09));
            clickFront += (1.0 - smoothstep(0.0, 0.024, ring)) * (1.0 - age / 2.6);
        }
    }

    let wakeUV = clamp(uv - vec2<f32>(flow.x * 0.010, 0.006 + speed * 0.0015), vec2<f32>(0.0), vec2<f32>(1.0));
    let wake = historyLoadUV(wakeUV);
    let ionGlow = (core * (0.25 + packet * 1.6) + clickFront * 0.9) * colorIntensity * (1.0 + audio.y) * (1.0 + fieldB * 1.35);
    let ionColor = mix(vec3<f32>(0.12, 0.45, 1.0), vec3<f32>(0.75, 0.2, 1.0), clamp(packet + audio.z * 0.4 + select(-0.1, 0.35, charge < 0.0), 0.0, 1.0)) * ionGlow;
    let finalRGB = aces(max(mix(source.rgb, wake.rgb, 0.18 + curlStrength * 0.24) + ionColor, vec3<f32>(0.0)));
    let alpha = clamp(max(source.a, wake.a * 0.88) + ionGlow * 0.45, 0.0, 1.0);
    let output = vec4<f32>(finalRGB, alpha);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
