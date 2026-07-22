// ═══════════════════════════════════════════════════════════════════
//  Wave Equation Simulation v3 - Audio-reactive fluid ripple solver
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware, temporal
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-07-22 (swarm b11, Algorithmist)
//    - FIXED feedback-state bug: the solver reads (height, velocity)
//      from dataTextureC.rg but previously wrote finalColor into
//      dataTextureA, so the feedback loop carried color, not state.
//      Sim state (height, velocity, energy) now goes to dataTextureA
//      so the engine A->C copy (A wins) feeds real state back.
//    - 9-point Laplacian (ortho weight 1.0, diagonal 0.5, renormalized)
//      for isotropic, less grid-aligned wave propagation.
//    - Click droplets: gaussian height pulse on the mouse-down rising
//      edge (tracked via extraBuffer[133]) instead of continuous forcing.
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,  // xy=ripple uv, z=time_created, w=strength
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Canonical hashes (shared across codebase for consistent noise character)
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// Edge-safe height fetch for the Laplacian neighborhood
fn sampleHeight(p: vec2<i32>, maxCoord: vec2<i32>) -> f32 {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), maxCoord), 0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sample input from previous layer
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Slider params (saved-preset contract: same ids/defaults/mapping order)
    let intensity   = clamp(u.zoom_params.x * (1.0 + bass * 0.2), 0.0, 1.0);
    let speedParam  = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
    let scaleParam  = clamp(u.zoom_params.z * (1.0 + treble * 0.1), 0.0, 1.0);
    let detailParam = clamp(u.zoom_params.w, 0.0, 1.0);

    // Wave physics parameters — each slider drives a real solver constant
    let damping    = mix(0.96, 0.999, detailParam);              // Detail: trail persistence
    let wave_speed = max(mix(0.1, 1.0, speedParam), 0.001);      // Speed: propagation rate
    let tension    = max(mix(0.001, 0.05, scaleParam), 0.0001);  // Scale: restoring force
    let dropletAmp = mix(0.6, 3.0, intensity);                   // Intensity: pulse energy

    // ── Feedback state read ────────────────────────────────────────
    // dataTextureC now carries solver state (via engine A->C copy), not color.
    let state = textureLoad(dataTextureC, px, 0);
    var height   = state.r;
    var velocity = state.g;

    // Sanitize: kill NaN and clamp stale pre-fix color values (0..1 garbage)
    height   = select(height, 0.0, height != height);
    velocity = select(velocity, 0.0, velocity != velocity);
    height   = clamp(height, -8.0, 8.0);
    velocity = clamp(velocity, -8.0, 8.0);

    // Initialize flat surface (branchless)
    let flatMask = f32(abs(height) < 0.001 && abs(velocity) < 0.001);
    height   = mix(height, 0.0, flatMask);
    velocity = mix(velocity, 0.0, flatMask);

    // ── 9-point Laplacian (isotropic stencil) ──────────────────────
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let n  = sampleHeight(px + vec2<i32>( 0,  1), maxCoord);
    let s  = sampleHeight(px + vec2<i32>( 0, -1), maxCoord);
    let e  = sampleHeight(px + vec2<i32>( 1,  0), maxCoord);
    let w  = sampleHeight(px + vec2<i32>(-1,  0), maxCoord);
    let ne = sampleHeight(px + vec2<i32>( 1,  1), maxCoord);
    let nw = sampleHeight(px + vec2<i32>(-1,  1), maxCoord);
    let se = sampleHeight(px + vec2<i32>( 1, -1), maxCoord);
    let sw = sampleHeight(px + vec2<i32>(-1, -1), maxCoord);
    // Weights: 1.0 orthogonal, 0.5 diagonal; total neighbor weight = 6.0
    let laplacian = ((n + s + e + w) + 0.5 * (ne + nw + se + sw) - 6.0 * height) * (1.0 / 6.0);

    // ── Click droplets: rising-edge gaussian height pulses ─────────
    let mouse     = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseDown = u.zoom_config.w > 0.5;
    let wasDown   = extraBuffer[133] > 0.5;
    let clickEdge = f32(mouseDown) * (1.0 - f32(wasDown));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = f32(mouseDown);  // single writer; read by all next frame
    }
    let dropSigma = mix(0.025, 0.060, scaleParam);
    let dm      = distance(uv, mouse);
    let droplet = exp(-(dm * dm) / (dropSigma * dropSigma)) * clickEdge * dropletAmp;

    // Engine ripple events (click ring buffer) also seed droplets
    var ripplePulse = 0.0;
    for (var i = 0; i < 50; i = i + 1) {
        let rp  = u.ripples[i];
        let age = time - rp.z;
        if (rp.w > 0.001 && age >= 0.0 && age < 0.2) {
            let rd = distance(uv, rp.xy);
            ripplePulse += exp(-(rd * rd) / (dropSigma * dropSigma)) * rp.w * (1.0 - age * 5.0);
        }
    }

    // Audio rain: strong bass transients seed small ambient droplets
    let beatSeed  = floor(time * 8.0);
    let beatPos   = hash22(vec2<f32>(beatSeed, beatSeed * 1.37 + 7.7));
    let beatForce = max(bass - 1.0, 0.0) * intensity * 0.6;
    let db        = distance(uv, beatPos);
    let rainDrop  = exp(-(db * db) / (0.02 * 0.02)) * beatForce;

    // ── Klein-Gordon / Sine-Gordon nonlinear term (preserved) ──────
    let nonlinear  = clamp(detailParam, 0.0, 1.0);
    let massKG     = tension * 0.5;
    let massSG     = nonlinear * tension * sin(height * PI);
    let nonlinTerm = mix(-massKG * height, -massSG, nonlinear);

    // Bass amplifies droplet energy and mouse impact
    let audioBoost = 1.0 + bass * detailParam * 2.0;

    // ── Wave equation integration with nonlinear term ──────────────
    let acceleration = laplacian * wave_speed * wave_speed + nonlinTerm;
    velocity = velocity * damping + acceleration;
    height   = height + velocity + (droplet + ripplePulse + rainDrop) * audioBoost;

    // ── Colour by topological charge and energy density ────────────
    let kinetic     = velocity * velocity;
    let potential_e = 1.0 - cos(height);
    let energy      = clamp((kinetic + potential_e) * 0.5, 0.0, 1.0);

    let topoCharge = clamp(laplacian * 10.0, -1.0, 1.0);

    let kinkPhase = fract(height / TAU);
    let kinkColor = vec3<f32>(
        0.5 + 0.5 * sin(kinkPhase * TAU),
        0.5 + 0.5 * sin(kinkPhase * TAU + 2.09440),
        0.5 + 0.5 * sin(kinkPhase * TAU + 4.18879)
    );

    let wallGlow     = abs(topoCharge);
    let energyBright = energy * (1.0 + bass * 0.5);

    let t = height * 0.5 + 0.5;
    let waterColor = mix(
        vec3<f32>(0.03, 0.08, 0.25),
        vec3<f32>(0.85, 0.95, 1.0),
        smoothstep(0.0, 1.0, t)
    );
    // Crest/trough relief shading from the isotropic Laplacian
    let relief = clamp(laplacian * 4.0, -0.5, 0.5);
    let shaded = waterColor * (1.0 + relief);
    let generatedColor = mix(shaded, kinkColor, wallGlow * nonlinear)
                       + vec3<f32>(1.0, 0.8, 0.4) * energyBright * 0.4;

    // Alpha derived from wave intensity and energy (no hardcoded 1.0)
    let waveIntensity = clamp(abs(height) + abs(velocity) * 2.0 + energy, 0.0, 1.0);
    let opacity       = mix(0.5, 0.95, intensity);
    let finalRGB      = mix(inputColor.rgb, generatedColor, opacity);
    let finalAlpha    = clamp(waveIntensity * opacity + energy * 0.3 + inputColor.a * 0.2, 0.0, 1.0);

    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), finalAlpha);

    // Depth
    let depth = clamp(energy + inputDepth * 0.5, 0.0, 1.0);

    // ── Mandatory writes ───────────────────────────────────────────
    textureStore(writeTexture, px, finalColor);
    // Solver state -> dataTextureA (engine copies A->C; A wins).
    // Layout: r = height, g = velocity, b = energy, a = wave intensity.
    textureStore(dataTextureA, px, vec4<f32>(height, velocity, energy, waveIntensity));
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
