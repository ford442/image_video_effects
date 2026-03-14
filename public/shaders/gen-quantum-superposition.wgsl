// ═══════════════════════════════════════════════════════════════════════════════
//  Quantum Superposition Lattice
//  Category: GENERATIVE | Complexity: VERY_HIGH
//  Particles exist in "superposition"—fading between multiple positions
//  simultaneously. Ghost trails, probability clouds, and wave function collapse
//  visualized as dreamy aesthetics. Bridges quantum uncertainty with art.
//  Mathematical approach: Wave function simulation via superposed Gaussian
//  packets, probability density |ψ|² rendering, interference fringes from
//  phase differences, lattice potential wells, temporal decoherence trails.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ParticleCount, y=MouseX, z=MouseY, w=DecoherenceRate
    zoom_params: vec4<f32>,  // x=WaveSpeed, y=LatticeScale, z=Uncertainty, w=InterferenceStr
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Hash functions
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 43758.5453)
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Complex multiplication
// ─────────────────────────────────────────────────────────────────────────────
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gaussian wave packet: ψ(x) = A * exp(-|x-x0|²/(4σ²)) * exp(i*k·x)
//  Returns complex amplitude (real, imaginary)
// ─────────────────────────────────────────────────────────────────────────────
fn wavePacket(pos: vec2<f32>, center: vec2<f32>, momentum: vec2<f32>, sigma: f32, time: f32) -> vec2<f32> {
    let diff = pos - center;
    let dist2 = dot(diff, diff);

    // Gaussian envelope
    let envelope = exp(-dist2 / (4.0 * sigma * sigma));

    // Phase: k·x - ωt where ω = |k|²/2 (free particle dispersion)
    let omega = dot(momentum, momentum) * 0.5;
    let phase = dot(momentum, pos) - omega * time;

    // Complex wave function
    return envelope * vec2<f32>(cos(phase), sin(phase));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lattice potential: creates a grid of potential wells
//  Particles tunnel between wells, creating the lattice structure
// ─────────────────────────────────────────────────────────────────────────────
fn latticePotential(p: vec2<f32>, scale: f32) -> f32 {
    let gridP = p * scale;
    let cell = fract(gridP) - 0.5;
    let well = 1.0 - exp(-dot(cell, cell) * 8.0);
    return well;
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = (fragCoord * 2.0 - dims) / dims.y;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let numParticles = i32(u.zoom_config.x * 10.0 + 3.0);  // 3 – 13
    let decoherence = u.zoom_config.w * 0.3 + 0.02;        // 0.02 – 0.32
    let waveSpeed = u.zoom_params.x * 3.0 + 0.5;           // 0.5 – 3.5
    let latticeScale = u.zoom_params.y * 6.0 + 2.0;        // 2 – 8
    let uncertainty = u.zoom_params.z * 0.4 + 0.1;         // 0.1 – 0.5 (σ)
    let interfStr = u.zoom_params.w * 2.0 + 0.5;           // 0.5 – 2.5

    // Mouse as observation point (collapses nearby superpositions)
    let mouseUV = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / dims * 2.0 - 1.0);

    // ─────────────────────────────────────────────────────────────────────────
    //  Superpose wave packets from all particles
    //  Each particle exists in multiple positions simultaneously
    // ─────────────────────────────────────────────────────────────────────────
    var totalPsi = vec2<f32>(0.0);    // Total wave function (complex)
    var totalProb = 0.0;              // |ψ|² probability density
    var phaseField = 0.0;             // For interference coloring

    for (var i = 0; i < 13; i++) {
        if (i >= numParticles) { break; }
        let fi = f32(i);
        let seed = vec2<f32>(fi * 17.3, fi * 31.7);

        // Particle's superposition: 3 simultaneous positions
        for (var s = 0; s < 3; s++) {
            let fs = f32(s);
            let subSeed = seed + vec2<f32>(fs * 7.1, fs * 13.3);

            // Position: oscillates between lattice sites
            let siteA = (hash22(subSeed) * 2.0 - 1.0) * 2.0;
            let siteB = (hash22(subSeed + 100.0) * 2.0 - 1.0) * 2.0;
            let tunnelPhase = sin(time * waveSpeed * (0.3 + fi * 0.1) + fs * 2.09);
            let center = mix(siteA, siteB, tunnelPhase * 0.5 + 0.5);

            // Momentum: derived from tunneling direction
            let momentum = (siteB - siteA) * waveSpeed * 0.5;

            // Superposition weight (decreases for higher states)
            let weight = 1.0 / (1.0 + fs);

            // Compute wave packet
            let psi = wavePacket(uv, center, momentum, uncertainty, time * waveSpeed) * weight;

            // "Observation" effect: near mouse, collapse to most probable
            let distToMouse = length(center - mouseUV);
            let collapseStr = exp(-distToMouse * 3.0) * 0.5;
            let effectivePsi = mix(psi, psi * (1.0 + collapseStr), collapseStr);

            totalPsi += effectivePsi;
        }
    }

    // Probability density: |ψ|²
    totalProb = dot(totalPsi, totalPsi);
    phaseField = atan2(totalPsi.y, totalPsi.x);

    // ─────────────────────────────────────────────────────────────────────────
    //  Interference fringes: where wave packets overlap
    // ─────────────────────────────────────────────────────────────────────────
    let interference = (cos(phaseField * interfStr * 4.0) + 1.0) * 0.5;
    let fringePattern = totalProb * interference;

    // ─────────────────────────────────────────────────────────────────────────
    //  Lattice potential visualization
    // ─────────────────────────────────────────────────────────────────────────
    let potential = latticePotential(uv, latticeScale);
    let latticeLines = smoothstep(0.95, 0.98, potential);

    // ─────────────────────────────────────────────────────────────────────────
    //  Coloring
    // ─────────────────────────────────────────────────────────────────────────
    // Probability cloud: cool blues/purples
    let probHue = fract(0.6 + phaseField / 6.28318 * 0.3 + time * 0.02);
    let probSat = 0.5 + 0.5 * interference;
    let probVal = sqrt(totalProb) * 3.0;
    var col = hsv2rgb(probHue, probSat, min(probVal, 1.0));

    // Interference brightens with warm tones
    let fringeColor = hsv2rgb(fract(phaseField / 6.28318 + 0.1), 0.7, 1.0);
    col += fringeColor * fringePattern * 0.4 * interfStr;

    // Lattice grid: subtle structural lines
    let gridColor = vec3<f32>(0.15, 0.25, 0.4);
    col = mix(col, gridColor, latticeLines * 0.3);

    // ─────────────────────────────────────────────────────────────────────────
    //  Decoherence trails: ghostly afterimages
    // ─────────────────────────────────────────────────────────────────────────
    let history = textureSampleLevel(dataTextureC, u_sampler, fragCoord / dims, 0.0).rgb;
    let trail = mix(col, history, 1.0 - decoherence);
    col = max(col, trail * 0.85); // Ghosts persist as faded versions

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: "measurement" events create collapse waves
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let rUV = (r.xy * 2.0 - 1.0);
        let dist = length(uv - rUV);
        let age = time - r.z;
        if (age > 0.0 && age < 4.0) {
            // Collapse wave: probability redistributes
            let collapseRing = exp(-abs(dist - age * 0.8) * 15.0) * exp(-age * 0.5);
            let collapseColor = hsv2rgb(fract(dist * 2.0 + age), 0.8, 1.0);
            col += collapseColor * collapseRing * 0.4;

            // Probability spike at measurement point
            let spike = exp(-dist * 10.0) * exp(-age * 2.0);
            col += vec3<f32>(1.0, 0.9, 0.7) * spike * 0.5;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Background: dark with subtle quantum foam
    // ─────────────────────────────────────────────────────────────────────────
    let bgNoise = hash21(uv * 100.0 + time * 0.01) * 0.02;
    col += vec3<f32>(0.01, 0.015, 0.03) + bgNoise;

    // Vignette
    col *= 1.0 - 0.4 * dot(uv, uv) * 0.3;

    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
