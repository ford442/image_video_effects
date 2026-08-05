// ═══════════════════════════════════════════════════════════════════
//  Phase-Transition Memory Weave — Interactivist upgrade (Batch 36)
//  Category: generative
//  Description: Viscous history-dependent field undergoing phase
//  transitions between fluid, crystalline, and chaotic states.
//  TRUE hysteresis via dataTextureC feedback: the order field relaxes
//  toward a diffused copy of its own past (domains coarsen over time —
//  emergent spinodal-like behavior). Spring-smoothed mouse stirs the
//  fluid phase with its velocity; click-hold nucleates crystal. Clicks
//  seed expanding crystallization fronts. Smoothed bass lags thresholds.
//  Complexity: Medium-High
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

// Order parameter field (like Landau theory)
// Low: fluid/chaotic, medium: mixed, high: crystalline
fn orderParameter(uv: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
                  viscosity: f32) -> f32 {
    // Multi-scale order fluctuations
    let n1 = smoothNoise(uv * 4.0 + vec2<f32>(t * 0.08, 0.0));
    let n2 = smoothNoise(uv * 8.0 - vec2<f32>(t * 0.05, t * 0.04));
    let n3 = smoothNoise(uv * 16.0 + vec2<f32>(t * 0.12, t * 0.09));

    // Order driven by audio: bass=fluid chaos, treble=crystalline order
    let audioOrder = treble - bass * 0.7 + mids * 0.2;

    // Spatial pattern blending
    let base = n1 * 0.5 + n2 * 0.35 + n3 * 0.15;

    // Hysteresis: past configurations "resist" change (viscosity)
    // Approximated by mixing with a slower-evolving noise layer
    let slowNoise = smoothNoise(uv * 3.0 + vec2<f32>(t * 0.02, 0.0));
    let viscousBase = mix(base, slowNoise, viscosity * 0.6);

    return clamp(viscousBase + audioOrder * 0.4, 0.0, 1.0);
}

// Crystalline lattice pattern for high-order regions
fn crystallineLattice(uv: vec2<f32>, t: f32, latticeScale: f32, treble: f32) -> f32 {
    let lp = uv * latticeScale;
    // Hexagonal lattice approximation
    let q = vec2<f32>(lp.x + lp.y * 0.5773, lp.y * 1.1547);
    let qr = fract(q);
    let qi = floor(q);
    _ = qi; // suppress warning
    // Distance to nearest lattice point
    let hexDist = length(qr - 0.5);
    let latticeIntensity = smoothstep(0.35, 0.2, hexDist);

    // Lattice oscillates with treble
    let pulsing = latticeIntensity * (0.7 + 0.3 * sin(t * 3.0 + treble * PI));
    return pulsing;
}

// Fluid flow field for low-order regions
fn fluidFlow(uv: vec2<f32>, t: f32, bass: f32) -> vec2<f32> {
    let n1x = smoothNoise(uv * 3.0 + vec2<f32>(t * 0.1, 0.5));
    let n1y = smoothNoise(uv * 3.0 + vec2<f32>(0.5, t * 0.1));
    return vec2<f32>(n1x - 0.5, n1y - 0.5) * (0.2 + bass * 0.15);
}

// Chaotic attractor contribution (Lorenz-like)
fn chaoticPattern(uv: vec2<f32>, t: f32, bass: f32, mids: f32) -> f32 {
    // Fast-evolving chaotic hash
    let timeSlice = floor(t * (2.0 + bass * 3.0));
    let ch = hash13(vec3<f32>(uv * 20.0, timeSlice));
    let ch2 = hash13(vec3<f32>(uv * 30.0, timeSlice + 1.0));
    return ch * ch2 * mids;
}

// Color map: fluid=blue-cyan, crystalline=white-gold, chaotic=red-purple
fn phaseColor(order: f32, t: f32, bass: f32, mids: f32, treble: f32) -> vec3<f32> {
    // Fluid phase color
    let fluidCol = vec3<f32>(0.05 + bass * 0.1, 0.3 + mids * 0.3, 0.7 + treble * 0.2);
    // Crystalline phase color
    let crystalCol = vec3<f32>(0.9 + treble * 0.1, 0.85, 0.5 + mids * 0.3);
    // Chaotic phase color
    let chaoticCol = vec3<f32>(0.7 + bass * 0.3, 0.1, 0.5 + treble * 0.3);

    // Three-phase blend based on order parameter
    var col = fluidCol;
    col = mix(col, chaoticCol, smoothstep(0.3, 0.5, order));
    col = mix(col, crystalCol, smoothstep(0.6, 0.85, order));
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let px = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let viscosity    = u.zoom_params.x;               // 0..1 material memory
    let phaseScale   = u.zoom_params.y * 1.5 + 0.5;  // 0.5..2.0
    let transitionSharpness = u.zoom_params.z * 4.0 + 1.0; // 1..5
    let glowAmt      = u.zoom_params.w * 2.0 + 0.5;  // 0.5..2.5

    // ── Persistent state: spring mouse [133..136], prevDown [137], smoothed bass [138] ──
    let sbLen = arrayLength(&extraBuffer);
    let canState = sbLen > 138u;
    let rawMouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseDown = u.zoom_config.w;
    if (global_id.x == 0u && global_id.y == 0u && canState) {
        let h = 0.016;
        let spx = extraBuffer[133];
        let spy = extraBuffer[134];
        let svx = extraBuffer[135];
        let svy = extraBuffer[136];
        let nvx = clamp(svx + ((rawMouse.x - spx) * 70.0 - svx * 11.0) * h, -3.0, 3.0);
        let nvy = clamp(svy + ((rawMouse.y - spy) * 70.0 - svy * 11.0) * h, -3.0, 3.0);
        extraBuffer[133] = clamp(spx + nvx * h, 0.0, 1.0);
        extraBuffer[134] = clamp(spy + nvy * h, 0.0, 1.0);
        extraBuffer[135] = nvx;
        extraBuffer[136] = nvy;
        extraBuffer[137] = mouseDown;
        extraBuffer[138] = mix(extraBuffer[138], bass, 0.08);
    }
    var sm = rawMouse;
    var smVel = vec2<f32>(0.0, 0.0);
    var bassSmooth = bass;
    if (canState) {
        sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        smVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        bassSmooth = extraBuffer[138];
    }

    // ── Guarded FFT bands (engine bins 1-8 at extraBuffer[6..13]) ──
    var fftLo = 0.0;
    var fftHi = 0.0;
    if (sbLen > 13u) {
        fftLo = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) * 0.3333;
        fftHi = (extraBuffer[11] + extraBuffer[12] + extraBuffer[13]) * 0.3333;
    }

    // ── Feedback: previous order/memory field + 4-tap diffusion ──
    // Domains coarsen over time (emergent, history-dependent coarsening).
    let prevState = textureLoad(dataTextureC, px, 0);
    let rx = max(i32(res.x) - 1, 0);
    let ry = max(i32(res.y) - 1, 0);
    var diffSum = prevState.r;
    diffSum += textureLoad(dataTextureC, vec2<i32>(min(px.x + 1, rx), px.y), 0).r;
    diffSum += textureLoad(dataTextureC, vec2<i32>(max(px.x - 1, 0), px.y), 0).r;
    diffSum += textureLoad(dataTextureC, vec2<i32>(px.x, min(px.y + 1, ry)), 0).r;
    diffSum += textureLoad(dataTextureC, vec2<i32>(px.x, max(px.y - 1, 0)), 0).r;
    let lapOrder = diffSum * 0.2;

    // Mouse: press nucleates crystal, motion stirs (melts) the fluid phase
    let mousePos = vec2<f32>(sm.x * aspect, sm.y);
    let mouseDist = length(uvA - mousePos);
    let mouseForce = exp(-mouseDist * mouseDist * 12.0);
    let stir = clamp(length(smVel) * 1.5, 0.0, 1.0);
    let press = step(0.5, mouseDown);
    let mouseOrderForce = mouseForce * (press * 0.8 * (0.5 + treble * 0.5) - stir * 0.45);

    // Compute order parameter (smoothed bass -> slow, lagging thresholds)
    let baseOrder = orderParameter(uvA * phaseScale, t, bassSmooth, mids, treble, viscosity);
    var order = clamp(baseOrder + mouseOrderForce, 0.0, 1.0);

    // Click nucleation fronts: expanding crystallization rings (guarded, finite)
    var boundaryBoost = 0.0;
    let nRip = min(u32(u.config.y), 50u);
    for (var i = 0u; i < nRip; i++) {
        let rip = u.ripples[i];
        let age = t - rip.z;
        if (age > 0.0 && age < 4.0) {
            let rp = vec2<f32>(rip.x * aspect, rip.y);
            let rd = length(uvA - rp);
            let frontD = (rd - age * 0.35) * 14.0;
            let ringW = exp(-frontD * frontD) * exp(-age * 1.2);
            order = clamp(order + ringW * 0.6, 0.0, 1.0);
            boundaryBoost += ringW;
        }
    }
    boundaryBoost = min(boundaryBoost, 1.0);

    // TRUE hysteresis: order relaxes toward the diffused memory of its past.
    // Viscosity controls how strongly history resists new configurations.
    let memK = mix(0.55, 0.96, viscosity);
    order = clamp(mix(order, lapOrder, memK), 0.0, 1.0);

    // Phase identification (with hysteresis-like sharp transitions)
    let fluidFraction    = smoothstep(0.4, 0.2, order);
    let crystallineFraction = smoothstep(0.6, 0.8, order) *
                              pow(smoothstep(0.55, 0.9, order), transitionSharpness * 0.1);
    let chaoticFraction  = smoothstep(0.25, 0.45, order) * (1.0 - smoothstep(0.55, 0.75, order));

    // Structural patterns per phase (FFT bins sharpen lattice detail)
    let lattice = crystallineLattice(uvA * phaseScale, t, 8.0 + treble * 4.0 + fftHi * 6.0, treble);
    let flow = fluidFlow(uvA * phaseScale, t, bass + stir * mouseForce);
    let chaos = chaoticPattern(uvA * phaseScale, t, bass, mids);

    // Warped UV for memory effects (fluid flow advects the pattern history)
    let warpedUV = uvA + flow * viscosity;
    let memoryPattern = smoothNoise(warpedUV * 6.0 + vec2<f32>(t * 0.03, 0.0));
    // Memory field itself is temporal: weave past memory into the present
    let mem = mix(memoryPattern, prevState.g, memK);

    // Base color from phase
    var color = phaseColor(order, t, bass, mids, treble);

    // Crystalline lattice glow
    color += vec3<f32>(0.9, 0.85, 0.5) * lattice * crystallineFraction * glowAmt * 0.8;

    // Fluid shimmer (low FFT bins modulate shimmer amplitude)
    let fluidShimmer = sin(uvA.x * 20.0 * phaseScale + t * 1.5 + flow.x * 10.0) * 0.5 + 0.5;
    color += vec3<f32>(0.1, 0.5, 0.8) * fluidShimmer * fluidFraction * (0.3 + fftLo * 0.4);

    // Chaotic noise overlay
    color += vec3<f32>(0.6, 0.1, 0.4) * chaos * chaoticFraction * 0.6;

    // Memory weave: history retention visible as subtle pattern ghost
    color = mix(color, color * 0.4 + phaseColor(mem, t, bass, mids, treble) * 0.6,
                viscosity * 0.4);

    // Phase boundary glow (hysteresis + nucleation front visualization)
    let phaseBoundary = select(0.0, 1.0, abs(order - 0.5) < 0.08);
    color += vec3<f32>(1.0, 0.9, 0.7) * phaseBoundary * (mids * 0.6 + boundaryBoost * 0.8);

    // Mouse forced region highlight + stirred wake
    color += vec3<f32>(0.9, 0.95, 1.0) * mouseForce * 0.3;
    color += vec3<f32>(0.2, 0.6, 0.9) * mouseForce * stir * 0.5;

    // Vignette
    let vig = 1.0 - smoothstep(0.3, 0.75, length(uv - 0.5) * 1.2);
    color *= vig;

    // Semantic alpha: luminous phase structure carries coverage, dark voids recede
    let finalCol = clamp(color * glowAmt, vec3<f32>(0.0), vec3<f32>(1.0));
    let luma = dot(finalCol, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(0.3 + luma * 1.2 + phaseBoundary * 0.15, 0.0, 1.0);
    textureStore(writeTexture, px, vec4<f32>(finalCol * alpha, alpha));

    // Relief depth: crystalline order and lattice sit near (near = 1)
    let depth = clamp(0.1 + order * 0.5 + lattice * crystallineFraction * 0.25 +
                      mouseForce * press * 0.15, 0.0, 1.0);
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // State for next frame: r = order field, g = memory weave, b = flow magnitude
    textureStore(dataTextureA, px, vec4<f32>(order, mem, length(flow), 1.0));
}
