// ═══════════════════════════════════════════════════════════════════
//  Lichtenberg Fractal — Phase A Upgrade
//  Category: simulation
//  Features: mouse-driven, depth-aware, audio-reactive, temporal
//  Complexity: High
//  Chunks From: original lichtenberg-fractal.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: branch_complexity  — curl-noise scale for organic path bias
//  Param2: decay_speed        — how fast arcs cool and fade
//  Param3: intensity          — glow brightness multiplier
//  Param4: depth_attraction   — bias growth toward foreground objects
//
//  State in dataTextureC (read) / dataTextureA (write):
//    R = charge  (1.0=active arc, 0.3-0.8=cooling, 0=empty)
//    G = age     (increments each frame, drives fade)
//    B = bias    (curl-noise direction encoded, unused in render)
//    A = unused
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BranchComplexity, y=DecaySpeed, z=Intensity, w=DepthAttraction
  ripples: array<vec4<f32>, 50>,
};

// ─── Noise / curl helpers ─────────────────────────────────────────

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash1b(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 73856.9341);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash1(i),                   hash1(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Curl noise: divergence-free flow field for organic branching bias
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let e = 0.002;
    let nx = vnoise(p + vec2<f32>(0.0, e)) - vnoise(p - vec2<f32>(0.0, e));
    let ny = vnoise(p + vec2<f32>(e, 0.0)) - vnoise(p - vec2<f32>(e, 0.0));
    return normalize(vec2<f32>(nx, -ny) + vec2<f32>(0.0001));
}

// Multi-octave noise for strike seeding
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0; var amp = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += amp * vnoise(pp);
        pp = pp * 2.1 + vec2<f32>(5.2, 1.3);
        amp *= 0.5;
    }
    return v;
}

// ─── Chromatic glow colour ────────────────────────────────────────

fn arcColour(charge: f32, age: f32, intensity: f32) -> vec3<f32> {
    if (charge > 0.85) {
        // Active core: white→electric blue
        let t = (charge - 0.85) / 0.15;
        return mix(vec3<f32>(0.3, 0.6, 1.0), vec3<f32>(1.0, 1.0, 1.0), t) * intensity * 2.5;
    } else if (charge > 0.55) {
        // Cooling channel: cyan → blue
        let t = (charge - 0.55) / 0.3;
        return mix(vec3<f32>(0.15, 0.1, 0.6), vec3<f32>(0.2, 0.6, 1.0), t) * intensity * 0.8;
    } else if (charge > 0.15) {
        // Old char: blue → deep purple
        let t = (charge - 0.15) / 0.4;
        return mix(vec3<f32>(0.12, 0.0, 0.18), vec3<f32>(0.1, 0.05, 0.55), t) * intensity * 0.35;
    }
    return vec3<f32>(0.0);
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv    = vec2<f32>(global_id.xy) / resolution;
    let time  = u.config.x;
    let mouse = u.zoom_config.yz;
    let px    = 1.0 / resolution;

    // Params
    let complexity      = u.zoom_params.x * 8.0 + 1.0;   // curl noise spatial scale
    let decaySpeed      = u.zoom_params.y * 0.025 + 0.005;
    let intensity       = u.zoom_params.z * 4.0 + 1.0;
    let depthAttraction = u.zoom_params.w;

    // Audio reactivity — bass triggers discharge energy
    let bass = select(0.0, plasmaBuffer[0].x, arrayLength(&plasmaBuffer) > 0u);

    // Read current state
    let oldState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var charge = oldState.r;
    var age    = oldState.g;

    // Depth at this pixel (1=near, 0=far)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Mouse ignition ───────────────────────────────────────────
    if (mouse.x >= 0.0) {
        let aspect = resolution.x / resolution.y;
        let mDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
        if (mDist < 0.012) {
            charge = 1.0;
            age = 0.0;
        }
    }

    // ── Ripple-triggered discharge origins ───────────────────────
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let r = u.ripples[ri];
        let elapsed = time - r.z;
        if (elapsed >= 0.0 && elapsed < 0.08) {
            let aspect = resolution.x / resolution.y;
            let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
            if (rDist < 0.015 + bass * 0.03) {
                charge = 1.0;
                age = 0.0;
            }
        }
    }

    // ── Spread from burning neighbours ───────────────────────────
    if (charge < 0.5) {
        // Curl-noise flow field for this pixel — gives organic branch direction
        let flowUV  = uv * complexity + vec2<f32>(time * 0.015);
        let flowDir = curlNoise(flowUV);

        var maxNeighborCharge = 0.0;
        var bestSpreadChance  = 0.0;

        for (var ni = -1; ni <= 1; ni++) {
            for (var nj = -1; nj <= 1; nj++) {
                if (ni == 0 && nj == 0) { continue; }
                let nOffset = vec2<f32>(f32(ni), f32(nj));
                let nUV     = uv + nOffset * px;
                let nState  = textureSampleLevel(dataTextureC, non_filtering_sampler, nUV, 0.0);
                let nCharge = nState.r;

                if (nCharge > 0.82) {
                    // Curl alignment: prefer spreading in flow direction
                    let alignment   = dot(normalize(nOffset), flowDir) * 0.5 + 0.5;
                    // Depth attraction: bias toward foreground pixels
                    let nDepth      = textureSampleLevel(readDepthTexture, non_filtering_sampler, nUV, 0.0).r;
                    let depthBonus  = nDepth * depthAttraction * 0.4;
                    // Audio: bass pulses increase spread chance
                    let audioBonus  = bass * 0.15;
                    // Stochastic gate
                    let chance      = (0.08 + alignment * 0.18 + depthBonus + audioBonus);

                    if (hash1(uv * 137.0 + vec2<f32>(time * 7.3, f32(ni * 3 + nj))) < chance) {
                        bestSpreadChance = max(bestSpreadChance, chance);
                        maxNeighborCharge = max(maxNeighborCharge, nCharge);
                    }
                }
            }
        }

        if (maxNeighborCharge > 0.0) {
            charge = 1.0;
            age = 0.0;
        }
    }

    // ── Age and decay active arcs ─────────────────────────────────
    if (charge > 0.0) {
        age += decaySpeed;
        // Exponential cool-down curve
        let cooled = charge - decaySpeed * 1.8 * (charge * charge);
        charge = max(0.0, cooled);
        // Old scorch marks eventually erase fully
        if (age > 1.0 && charge < 0.05) {
            charge = 0.0;
            age    = 0.0;
        }
    }

    // Persist new state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(charge, age, 0.0, 0.0));

    // ── Render ───────────────────────────────────────────────────
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Soft atmospheric glow — sample charge from a wider neighbourhood
    var glowSum = 0.0;
    let glowOffsets = array<vec2<f32>, 8>(
        vec2<f32>(-2.0,  0.0), vec2<f32>( 2.0,  0.0),
        vec2<f32>( 0.0, -2.0), vec2<f32>( 0.0,  2.0),
        vec2<f32>(-1.5, -1.5), vec2<f32>( 1.5, -1.5),
        vec2<f32>(-1.5,  1.5), vec2<f32>( 1.5,  1.5)
    );
    for (var gi = 0; gi < 8; gi++) {
        let gUV = uv + glowOffsets[gi] * px * 3.0;
        let gCharge = textureSampleLevel(dataTextureC, non_filtering_sampler, gUV, 0.0).r;
        glowSum += gCharge * select(0.04, 0.12, gCharge > 0.8);
    }
    let atmosphericGlow = vec3<f32>(0.1, 0.35, 1.0) * glowSum * intensity * 0.5;

    // Primary arc colour
    let arcCol = arcColour(charge, age, intensity);

    // RGBA alpha encodes discharge intensity
    let dischargeAlpha = clamp(charge * 2.0, 0.0, 1.0);

    let finalRGB = baseColor + arcCol + atmosphericGlow;
    textureStore(writeTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(finalRGB, 1.0 - dischargeAlpha * 0.3));

    // Depth pass-through
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(depth, 0.0, 0.0, 1.0));
}
