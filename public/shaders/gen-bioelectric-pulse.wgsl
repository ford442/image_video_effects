// ═══════════════════════════════════════════════════════════════════
//  Bioelectric Pulse - Reaction-diffusion-like organic pulses
//  Category: generative
//  Features: generative, reaction-diffusion, organic-pulses, glow,
//            fbm-noise, audio-reactive, mouse-activation, depth-aware,
//            phosphor-trail feedback, kick-triggered mega-pulse
//  Agent 4a — Phase A shader upgrade swarm
//  Interactivist pass (batch 14): fixed mouse reads to engine
//  convention (zoom_config.yz = position, .w = down), added honest
//  dataTextureC phosphor-trail feedback, and a kick-transient
//  mega-pulse driven by a smoothed bass envelope in extraBuffer.
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=unused, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=PulseCount, y=Speed, z=PulseWidth, w=HueShift
  ripples: array<vec4<f32>, 50>,
};

// ── Chunk: hash12 (from gen_grid.wgsl / chunk-library) ────────────
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uS.x), mix(c, d, uS.x), uS.y);
}

// ── Chunk: fbm2 (from chunk-library) ──────────────────────────────
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: palette (from chunk-library) ───────────────────────────
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──────────────────────
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius + 1e-6)) * intensity;
}

// Reaction-diffusion wave kernel: sum of decaying radial pulses
fn rdPulse(p: vec2<f32>, center: vec2<f32>, time: f32, speed: f32, width: f32) -> f32 {
    let d = length(p - center);
    let phase = d * 8.0 - time * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    return wave * envelope * glow(d, width, 1.0);
}

// Kick mega-pulse: an expanding bioelectric shockwave ring launched
// from screen center on a bass transient. Age-based so it dies out
// a couple of seconds after the kick fires.
fn megaPulse(p: vec2<f32>, age: f32, speed: f32, width: f32) -> f32 {
    if (age < 0.0 || age > 2.5) { return 0.0; }
    let radius = age * (0.55 + speed * 0.45);
    let d = length(p);
    let ring = exp(-pow((d - radius) * (5.0 + width * 8.0), 2.0));
    let afterglow = glow(d, 0.2 + width, 0.6) * exp(-age * 4.0);
    let fade = exp(-age * 1.8);
    return (ring + afterglow) * fade;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Clamp/normalize zoom_params — each slider drives a real constant
    // of this shader's algorithm:
    //   x Pulse Count -> number of wandering reaction centers
    //   y Pulse Speed -> wave phase speed AND kick shockwave expansion
    //   z Pulse Width -> pulse glow radius AND trail injection strength
    //   w Hue Shift   -> palette phase AND phosphor trail tint
    let pulseCount = mix(1.0, 5.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let speed = mix(0.3, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulseWidth = mix(0.1, 0.4, clamp(u.zoom_params.z, 0.0, 1.0));
    let hueShift = clamp(u.zoom_params.w, 0.0, 1.0);

    // Mouse activation point (engine convention: zoom_config.yz = mouse
    // position, .w = down; .x is time — do NOT read it as mouse X).
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // ── Kick transient detector (persistent state) ─────────────────
    // extraBuffer[133] = smoothed bass envelope
    // extraBuffer[134] = time of last kick trigger
    // Only invocation (0,0) integrates the envelope to avoid races.
    var bassEnv = extraBuffer[133];
    var lastKick = extraBuffer[134];
    if (gid.x == 0u && gid.y == 0u) {
        // Fast attack / slow release envelope follower.
        let attack = select(0.04, 0.35, bass > bassEnv);
        bassEnv = mix(bassEnv, bass, attack);
        // Kick = bass pokes above its own envelope by a threshold,
        // with a ~0.3 s retrigger gap so it doesn't machine-gun.
        if (bass > bassEnv * 1.25 + 0.12 && time - lastKick > 0.3) {
            lastKick = time;
        }
        extraBuffer[133] = bassEnv;
        extraBuffer[134] = lastKick;
    }
    let kickAge = time - lastKick;
    let mega = megaPulse(p, kickAge, speed, pulseWidth);

    // Organic noise substrate
    let n1 = fbm2(p * 2.0 + vec2<f32>(0.0, time * 0.05), 4);
    let n2 = fbm2(p * 3.0 + vec2<f32>(5.2, 1.3) + time * 0.03, 4);
    let substrate = fbm2(p * 1.5 + 2.0 * vec2<f32>(n1, n2), 4);

    // Multiple organic pulse centers (wandering motion preserved)
    var pulseField = 0.0;
    let baseCenters = array<vec2<f32>, 5>(
        vec2<f32>(0.0, 0.0),
        vec2<f32>(0.35, 0.25),
        vec2<f32>(-0.3, 0.35),
        vec2<f32>(-0.25, -0.3),
        vec2<f32>(0.3, -0.35)
    );

    let nCenters = i32(pulseCount);
    for (var i = 0; i < 5; i = i + 1) {
        if (i >= nCenters) { break; }
        let fi = f32(i);
        let offset = vec2<f32>(
            sin(time * 0.1 + fi * 2.0) * 0.1,
            cos(time * 0.13 + fi * 1.5) * 0.1
        );
        let center = baseCenters[i] + offset;
        let pulse = rdPulse(p, center, time + fi, speed, pulseWidth * 0.25);
        pulseField += pulse * (1.0 + bass * 0.5);
    }

    // Mouse pulse when active (now at the real cursor position)
    let mousePulse = rdPulse(p, mouse, time, speed * 1.5, pulseWidth * 0.2) * mouseDown;
    pulseField += mousePulse * 2.0;

    // Kick mega-pulse rides on top of the organic pulse field
    pulseField += mega * (1.5 + bass);

    // Vein network driven by noise
    let vein = abs(substrate - 0.5) * 2.0;
    let veinMask = smoothstep(0.55, 0.75, vein);
    let veinGlow = glow(vein, 0.15, 0.5 + mids * 0.5);

    // Color palette: bioelectric greens / cyans / magentas
    let bioPhase = hueShift + time * 0.05 + substrate * 0.3;
    let bioColor = palette(
        bioPhase,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.25, 0.55, 0.85)
    );
    let pulseColor = palette(
        bioPhase + 0.4 + bass * 0.1,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 0.7, 0.4),
        vec3<f32>(0.1, 0.6, 0.9)
    );
    // Mega-pulse flashes hotter — whiter core tinted by the palette.
    let megaColor = mix(pulseColor, vec3<f32>(1.0), 0.45);

    // Combine
    var col = vec3<f32>(0.01, 0.02, 0.03);
    col += bioColor * substrate * 0.3;
    col += pulseColor * pulseField;
    col += bioColor * veinGlow * veinMask;
    col += megaColor * mega * 0.8;

    // Sparkle along high-energy ridges
    let sparkle = step(1.0 - treble * 0.4, hash12(floor(p * 40.0) + vec2<f32>(time * 2.0, 0.0)));
    col += vec3<f32>(0.8, 0.95, 1.0) * sparkle * pulseField * 0.5;

    // Vignette
    let v = 1.0 - length(uv - 0.5) * 0.35;
    col *= clamp(v, 0.0, 1.0);

    // ── Phosphor-trail feedback (earns the reaction-diffusion name) ─
    // Blend with the previous frame via dataTextureC so pulses leave
    // fading trails: ~0.9 decay, ~0.1 injection (Pulse Width widens
    // the injection), accumulated trail clamped pre-tint at ~1.2.
    let prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let trailDecay = 0.9;
    let inject = mix(0.07, 0.14, pulseWidth / 0.4);
    var trail = prevFrame * trailDecay + col * inject;
    trail = min(trail, vec3<f32>(1.2));

    // Hue Shift tints the persistent trail toward the live palette.
    let trailTint = mix(vec3<f32>(1.0), bioColor + vec3<f32>(0.3), 0.35 * hueShift);

    // Output as generative background (alpha = 1.0)
    let finalColor = clamp(trail * trailTint, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    // Persist the clamped, pre-tint trail for next frame's feedback.
    textureStore(dataTextureA, coord, vec4<f32>(trail, 1.0));
}
