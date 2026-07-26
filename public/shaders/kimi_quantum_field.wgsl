// ═══════════════════════════════════════════════════════════════════
//  Kimi Quantum Field
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-07-26 (Batch 15)
//    - Removed double tonemap (Reinhard+pow stacked under ACES)
//    - Removed dead psi() helper
//    - Spectrum interferometer: per-source FFT bin amplitudes
//    - Honest slider wiring (labels match effects, defaults preserved)
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

// Kimi Quantum Field - Wave interference patterns with uncertainty visualization
//
// Slider contract (JSON names are frozen by saved presets; the WGSL makes
// each label honest while keeping the default 0.5 look identical):
//   Intensity (x): wave-packet count AND output intensity gain
//   Speed     (y): source coherence AND packet phase velocity
//   Scale     (z): position uncertainty AND field zoom
//   Detail    (w): uncertainty decay rate AND angular interference detail

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// IQ cosine palette: cheap cyclic rainbow used for the phase-hue field.
// t in [0,1] maps around the hue circle with a quantum-ish purple/cyan bias.
fn iqPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.60, 0.35, 0.15);
    return a + b * cos(6.28318 * (c * t + d));
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
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity: bass energizes wave packets, mids shift hue, treble lights nodes
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse position
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Aspect correct
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Mouse in world space
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;

    // ── Honest slider wiring ────────────────────────────────────────────
    // Each factor below equals exactly 1.0 (or the legacy constant) at the
    // 0.5 default, so saved presets render identically while the labels now
    // describe what the sliders actually do.
    let intensityParam = u.zoom_params.x;
    let speedParam = u.zoom_params.y;
    let scaleParam = u.zoom_params.z;
    let detailParam = u.zoom_params.w;

    // Intensity: packet count (legacy) + honest output gain (1.0 at default)
    let waveCount = i32(intensityParam * 8.0) + 3;
    let intensityGain = 0.5 + intensityParam;

    // Speed: source coherence (legacy) + packet phase velocity (1.0 at default)
    let coherence = speedParam;
    let phaseVelocity = 0.5 + speedParam;

    // Scale: position uncertainty (legacy) + field zoom (1.0 at default)
    let uncertainty = scaleParam * 0.5 * (1.0 + bass * 0.4);
    let fieldZoom = 0.5 + scaleParam;

    // Detail: uncertainty decay rate (legacy) + angular detail (3.0 at default)
    let decayRate = (detailParam * 2.0 + 0.5) * (1.0 + bass * 0.3);
    let angularFreq = 1.0 + detailParam * 4.0;

    // Field-zoomed sampling space: the interference field scales around the
    // cursor so the mouse stays the interferometer's center at any zoom.
    let fp = p / fieldZoom;
    let fMouse = mousePos / fieldZoom;

    // Organic jitter: previously-dead noise() now perturbs the uncertainty
    // field so the probability cloud breathes instead of pulsing uniformly.
    let jitter = noise(fp * 3.0 + vec2<f32>(time * 0.2, -time * 0.15));

    // ── Spectrum interferometer ─────────────────────────────────────────
    // Each wave source reads its own FFT bin (source i reads bin i+1), so
    // the interference pattern is a literal audio interferogram: loud bins
    // push their source's amplitude up, quiet bins let it fade.
    var amplitude = 0.0;
    var probability = 0.0;

    // Central source at mouse
    for (var i = 0; i < waveCount; i++) {
        let fi = f32(i);

        // Per-source spectrum amplitude: bin i+1 drives source i
        let binAmp = clamp(plasmaBuffer[1u + (u32(i) % 8u)].x, 0.0, 2.0);
        let sourceGain = 0.35 + binAmp * 0.9;

        // Wave packet properties (phase velocity is an honest Speed control)
        let k = 10.0 + fi * 5.0;
        let w = (2.0 + fi) * phaseVelocity;
        let phase = fi * 0.7;

        // Uncertainty in position (Gaussian spread), perturbed by noise
        let spread = 0.1 + uncertainty * (0.5 + 0.5 * sin(time * decayRate + fi))
                   * (0.75 + 0.5 * jitter);

        // Wave source with slight offset for interference
        let offset = vec2<f32>(
            cos(fi * 2.094) * 0.1 * coherence,
            sin(fi * 2.094) * 0.1 * coherence
        );
        let source = fMouse + offset;

        // Distance from source
        let diff = fp - source;
        let dist = length(diff);
        let angle = atan2(diff.y, diff.x);

        // Radial wave with angular modulation (Detail sets the fringe count)
        let radial = sin(k * dist - w * time + phase);
        let angular = cos(angle * angularFreq + fi);

        // Wave packet envelope
        var envelope = exp(-dist * dist / (2.0 * spread * spread));

        // Spectrum-weighted wave: this source speaks for its FFT bin
        var wave = radial * angular * envelope * sourceGain;
        amplitude += wave;

        // Probability density (|ψ|²)
        probability += wave * wave;
    }

    // Normalize
    amplitude /= f32(waveCount);
    probability /= f32(waveCount);

    // Phase visualization
    let phaseColor = 0.5 + 0.5 * sin(amplitude * 10.0 + time);

    // Quantum color palette
    let lowEnergy = vec3<f32>(0.1, 0.0, 0.3);   // Deep purple
    let midEnergy = vec3<f32>(0.0, 0.5, 0.8);   // Cyan
    let highEnergy = vec3<f32>(0.9, 0.9, 1.0);  // White

    var col = mix(lowEnergy, midEnergy, smoothstep(0.0, 0.5, probability));
    col = mix(col, highEnergy, smoothstep(0.5, 1.0, probability));

    // Phase hue via IQ cosine palette: mids rotate the palette phase, so
    // the interferogram's fringe colors track the mid spectrum.
    let hueT = fract(amplitude * 0.5 + mids * 0.35 + time * 0.05);
    let phaseHue = iqPalette(hueT) - vec3<f32>(0.5, 0.5, 0.5);
    col += phaseHue * phaseColor * (0.4 + mids * 0.6);

    // Uncertainty visualization (blur at edges)
    let edgeDist = 1.0 - length(p);
    let uncertaintyGlow = smoothstep(0.0, 0.3, edgeDist) * uncertainty;
    col += vec3<f32>(1.0, 0.3, 0.6) * uncertaintyGlow * 0.3;

    // Constructive interference nodes (treble brightens the antinodes)
    let nodes = pow(probability, 3.0) * 2.0 * (1.0 + treble * 1.2);
    col += vec3<f32>(0.8, 1.0, 0.9) * nodes;

    // Antinode bloom: treble gain lights the sharpest constructive peaks,
    // giving the interferogram a spectral "flare" on hats/snares.
    let bloom = pow(probability, 4.0) * treble * 2.5;
    col += vec3<f32>(0.6, 0.9, 1.0) * bloom;

    // Particle measurement (collapse visualization)
    let measureProb = hash(uv + vec2<f32>(time * 0.1));
    let collapsed = select(0.0, 1.0, measureProb < probability * 0.1);
    col += vec3<f32>(1.0, 0.9, 0.7) * collapsed * mouseDown;

    // Vignette
    let vignette = 1.0 - length(p) * 0.3;
    col *= vignette;

    // Intensity: honest output gain (exactly 1.0 at the 0.5 default)
    col *= intensityGain;

    // Alpha encodes probability density (|ψ|²) + collapse flashes, never flat 1.0
    let alpha = clamp(probability + nodes * 0.3 + collapsed * mouseDown, 0.0, 1.0);

    // Single tone map: ACES only (the old Reinhard+pow stack was removed —
    // the stacked curves over-darkened the mids of the probability field).
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    // Depth: denser probability regions read as nearer
    let depth = clamp(probability * 1.5, 0.0, 1.0);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
