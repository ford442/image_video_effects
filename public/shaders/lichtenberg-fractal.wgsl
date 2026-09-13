// ═══════════════════════════════════════════════════════════════════
//  Lichtenberg Fractal
//  Category: simulation
//  Features: mouse-driven, depth-aware, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12
//  Ideas: streamer tips at high-charge empty-neighbor ends; residual scorch along cooled channels
//  A packing: raw (charge, age, curl bias, scorch)
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
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
    let coord = vec2<i32>(global_id.xy);
    let dims  = vec2<i32>(resolution);

    // Params
    let complexity      = u.zoom_params.x * 8.0 + 1.0;   // curl noise spatial scale
    let decaySpeed      = u.zoom_params.y * 0.025 + 0.005;
    let intensity       = u.zoom_params.z * 4.0 + 1.0;
    let depthAttraction = u.zoom_params.w;

    // Audio reactivity — bass triggers discharge energy
    let bass = select(0.0, plasmaBuffer[0].x, arrayLength(&plasmaBuffer) > 0u);
    let treble = select(0.0, plasmaBuffer[0].z, arrayLength(&plasmaBuffer) > 0u);

    // Read current state (exact C load)
    let oldState = stateAt(coord, dims);
    var charge = oldState.r;
    var age    = oldState.g;
    var scorch = oldState.a;

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

    // Curl-noise flow field — organic branch direction (always, for bias packing)
    let flowUV  = uv * complexity + vec2<f32>(time * 0.015);
    let flowDir = curlNoise(flowUV);

    // ── Spread from burning neighbours ───────────────────────────
    if (charge < 0.5) {
        var maxNeighborCharge = 0.0;
        var bestSpreadChance  = 0.0;

        for (var ni = -1; ni <= 1; ni++) {
            for (var nj = -1; nj <= 1; nj++) {
                if (ni == 0 && nj == 0) { continue; }
                let nOffset = vec2<f32>(f32(ni), f32(nj));
                let nState  = stateAt(coord + vec2<i32>(ni, nj), dims);
                let nCharge = nState.r;

                if (nCharge > 0.82) {
                    // Curl alignment: prefer spreading in flow direction
                    let alignment   = dot(normalize(nOffset), flowDir) * 0.5 + 0.5;
                    // Depth attraction: bias toward foreground pixels
                    let nDepth      = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + nOffset * px, 0.0).r;
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

    // Idea 1 — streamer tips: high charge, empty neighbors
    let nL = stateAt(coord + vec2<i32>(-1, 0), dims).r;
    let nR = stateAt(coord + vec2<i32>(1, 0), dims).r;
    let nU = stateAt(coord + vec2<i32>(0, -1), dims).r;
    let nD = stateAt(coord + vec2<i32>(0, 1), dims).r;
    let nAvg = (nL + nR + nU + nD) * 0.25;
    let tip = charge * (1.0 - nAvg) * smoothstep(0.72, 0.96, charge);

    // Idea 2 — residual scorch along cooled channels
    scorch = max(scorch * 0.978, age * smoothstep(0.08, 0.55, 1.0 - charge) * 0.16);
    scorch = clamp(scorch, 0.0, 1.0);

    let bias = flowDir.x * 0.5 + 0.5;
    textureStore(dataTextureA, coord, vec4<f32>(charge, age, bias, scorch));

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
        let gOff = vec2<i32>(i32(glowOffsets[gi].x * 3.0), i32(glowOffsets[gi].y * 3.0));
        let gCharge = stateAt(coord + gOff, dims).r;
        glowSum += gCharge * select(0.04, 0.12, gCharge > 0.8);
    }
    let atmosphericGlow = vec3<f32>(0.1, 0.35, 1.0) * glowSum * intensity * 0.5;

    // Primary arc colour
    let arcCol = arcColour(charge, age, intensity);
    let tipCol = vec3<f32>(1.35, 1.55, 2.1) * tip * intensity * (0.7 + treble * 0.4);

    // RGBA alpha encodes discharge intensity + scorch coverage
    let dischargeAlpha = clamp(charge * 2.0 + tip * 0.4 + scorch * 0.25, 0.0, 1.0);

    var finalRGB = baseColor * (1.0 - scorch * 0.55) + arcCol + atmosphericGlow + tipCol;
    finalRGB = aces(max(finalRGB, vec3<f32>(0.0)));
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, dischargeAlpha));

    // Depth pass-through
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
