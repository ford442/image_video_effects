// ═══════════════════════════════════════════════════════════════════
//  Plasma Orb v3
//  Category: generative
//  Features: audio-reactive, mouse-driven, mhd-turbulence, magnetic-reconnection,
//            tokamak-field-lines, synchrotron-emission, worley-arc-ridges,
//            spring-damper-drift, corona-shimmer, temporal-glow, aces-tone-map
//  Complexity: Very High
//  Created: 2026-05-31
//  Upgraded: 2026-07-22 (swarm Optimizer: worley arcs, spring drift, corona shimmer)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ArcInt, y=ArcChaos, z=GlowSize, w=CoreBright
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// Worley F2-F1 cellular ridge: thin bright lines along cell boundaries.
// Feature points jitter over time so the arc network crawls like live plasma.
fn worleyF2F1(p: vec2<f32>, time: f32, jitter: f32) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var f1 = 8.0;
    var f2 = 8.0;
    for (var gy = -1; gy <= 1; gy = gy + 1) {
        for (var gx = -1; gx <= 1; gx = gx + 1) {
            let g = vec2<f32>(f32(gx), f32(gy));
            let h = hash22(i + g);
            let o = 0.5 + jitter * 0.45 * vec2<f32>(
                sin(time * 1.7 + h.x * TAU),
                cos(time * 1.3 + h.y * TAU)
            );
            let d = length(g + o - f);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    return f2 - f1;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let pixel = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;

    // Slider wiring: each param drives a real constant of this algorithm.
    let arcInt = u.zoom_params.x * (1.0 + bass * 0.6);      // field-line + worley arc brightness
    let arcChaos = u.zoom_params.y * (1.0 + treble * 0.8);  // worley jitter, arc density, ridge width
    let glowSize = u.zoom_params.z;                          // corona radius + sheet thickness
    let coreBright = u.zoom_params.w;                        // core luminance + exposure

    // ── Spring-damper orb drift (state: extraBuffer[133..136] = offset.xy, vel.xy; 5..132 = engine FFT bins)
    // Offset is stored relative to screen center so a zeroed buffer = no drift.
    if (global_id.x == 0u && global_id.y == 0u) {
        var driftC = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var driftV = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        let driftTarget = mouse - vec2<f32>(0.5);
        let dt = 0.016;
        let springK = 24.0;  // lunge stiffness
        let dampK = 5.0;     // sub-critical damping → visible overshoot + settle
        let acc = (driftTarget - driftC) * springK - driftV * dampK;
        driftV = driftV + acc * dt;
        driftC = driftC + driftV * dt;
        extraBuffer[133] = driftC.x;
        extraBuffer[134] = driftC.y;
        extraBuffer[135] = driftV.x;
        extraBuffer[136] = driftV.y;
    }
    let drift = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    let aspect = res.x / res.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    // Orb center lunges toward the cursor with damped overshoot
    p = p - drift * vec2<f32>(aspect, 1.0) * 0.45;
    let dist = length(p);

    // Mouse pinch compression toward cursor
    let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
    let pinch = smoothstep(0.5, 0.0, length(mp)) * 0.4 * u.zoom_config.w;
    p = p - normalize(p + vec2<f32>(0.0001)) * pinch * smoothstep(0.3, 0.0, dist);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Temporal glow feedback from previous frame
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Divergence-free magnetic field via curl of scalar potential ψ
    let freq = 4.0 + depth * 6.0;
    let psi = sin(p.x * freq + time * 1.5) * cos(p.y * freq * 0.7 + time);
    let dpsidx = freq * cos(p.x * freq + time * 1.5) * cos(p.y * freq * 0.7 + time);
    let dpsidy = -freq * 0.7 * sin(p.x * freq + time * 1.5) * sin(p.y * freq * 0.7 + time);
    var B = vec2<f32>(dpsidy, -dpsidx);
    let Bmag = length(B) + 0.001;

    // Alfvén wave perturbation propagating along field lines
    let alfv = sin(dot(p, B / Bmag) * 8.0 - time * 4.0) * 0.15 * (1.0 + mids);
    B = B + vec2<f32>(-B.y, B.x) / Bmag * alfv;

    // Tokamak toroidal-poloidal field line wrapping
    let toroidal = atan2(p.y, p.x);
    let poloidal = dist * 6.28;
    let q = 2.0 + mids * 2.0;
    let fieldLine = sin(toroidal * 3.0 + poloidal * q + time * 0.5);
    let lineMask = smoothstep(0.15, 0.0, abs(fieldLine)) * smoothstep(0.35, 0.1, dist);

    // Magnetic reconnection events triggered by treble
    let reconnPhase = hash21(vec2<f32>(floor(time * 3.0), 0.0));
    let reconn = smoothstep(0.7 - treble * 0.3, 0.0, abs(fieldLine - reconnPhase)) * step(0.3, treble);
    let flare = reconn * 3.0;

    // ── Worley F2-F1 secondary lightning arcs between core and shell ──
    // Domain slowly rotates with the field so arcs branch along flow lines.
    let arcScale = 5.0 + arcChaos * 6.0;
    let rotA = time * 0.1 + toroidal * 0.15;
    let ca2 = cos(rotA);
    let sa2 = sin(rotA);
    let arcP = mat2x2<f32>(ca2, -sa2, sa2, ca2) * p * arcScale;
    let ridge = worleyF2F1(arcP, time * (0.6 + arcChaos), arcChaos);
    let ridgeWidth = 0.12 - arcChaos * 0.07;
    let arcMask = 1.0 - smoothstep(0.0, max(ridgeWidth, 0.02), ridge);
    // Confine arcs to the annulus between core and outer shell
    let annulus = smoothstep(0.07, 0.15, dist) * smoothstep(0.48, 0.30, dist);
    let arcPulse = 0.6 + 0.4 * sin(time * 7.0 + ridge * 20.0 + treble * 4.0);
    let arcs = arcMask * annulus * arcPulse * arcChaos;

    // Equatorial current sheet
    let sheet = smoothstep(0.04 + glowSize * 0.03, 0.0, abs(p.y)) * smoothstep(0.3, 0.0, dist);

    // Plasma beta = thermal pressure / magnetic pressure
    let thermal = 0.5 + bass * 1.5;
    let beta = thermal / (Bmag * Bmag + 0.1);

    // Synchrotron emission color: blue high-energy → red low-energy
    let energy = Bmag * (1.0 + flare);
    let syncCol = mix(vec3<f32>(1.0, 0.2, 0.05), vec3<f32>(0.1, 0.4, 1.0), clamp(energy / 3.0, 0.0, 1.0));

    // Chromatic aberration on fast radial particles
    let ca = dist * 0.02 * (1.0 + treble);
    let rCol = syncCol * vec3<f32>(1.0, 0.9, 0.8) * (1.0 + ca);
    let bCol = syncCol * vec3<f32>(0.8, 0.9, 1.0) * (1.0 - ca * 0.5);

    let lineCol = (rCol + bCol) * 0.5 * lineMask * arcInt;
    let arcCol = mix(vec3<f32>(0.5, 0.7, 1.0), vec3<f32>(0.9, 0.5, 1.0), arcPulse) * arcs * arcInt * 1.6;
    let sheetCol = vec3<f32>(0.6, 0.8, 1.0) * sheet * beta;
    let flareCol = vec3<f32>(1.0, 0.9, 0.7) * flare * (1.0 + bass);

    var col = lineCol + arcCol + sheetCol + flareCol;

    // Core plasma glow
    let core = smoothstep(0.12, 0.0, dist) * coreBright * beta;
    col = col + vec3<f32>(0.4, 0.7, 1.0) * smoothstep(0.25 + glowSize * 0.2, 0.0, dist) * 0.5;
    col = col + vec3<f32>(1.0, 0.95, 0.9) * core;

    // ── Corona shimmer: mids drive a slow rotating shimmer on the outer glow ──
    let coronaRadius = 0.35 + glowSize * 0.30;
    let shimAngle = toroidal - time * 0.35;
    let shimmer = 0.5 + 0.5 * sin(shimAngle * 6.0 + sin(shimAngle * 2.0 + time * 0.6) * 1.5);
    let coronaMask = smoothstep(coronaRadius, coronaRadius * 0.45, dist) * smoothstep(0.12, 0.24, dist);
    let coronaCol = mix(vec3<f32>(0.2, 0.5, 1.0), vec3<f32>(0.6, 0.85, 1.0), shimmer);
    col = col + coronaCol * coronaMask * (0.25 + mids * 0.55) * (0.5 + glowSize);

    // Temporal glow accumulation
    col = mix(prev.rgb * 0.85, col, 0.25);

    // Clamp accumulated glow pre-tint (luma-echo-warp lesson: no runaway feedback)
    col = min(col, vec3<f32>(1.2));

    // ACES tone mapping (single pass; exposure driven by Core Brightness)
    col = acesToneMap(col * (1.0 + coreBright) * 1.1);

    // Alpha encodes plasma beta × reconnection × depth perspective, plus arc energy
    let alpha = clamp(beta * reconn * depth + sheet * 0.3 + lineMask * 0.15 + arcs * 0.4, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(smoothstep(0.3, 0.0, dist), 0.0, 0.0, 0.0));
}
