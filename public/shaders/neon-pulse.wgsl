// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Pulse — Blackbody Plasma Cell Array
//  Category: interactive-mouse
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, blackbody, plasma-arcs, thermal-diffusion,
//            depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 60)
// ═══════════════════════════════════════════════════════════════════════════════
//  BUG FIXED IN THIS PASS — the shader was catalogued `mouse-driven` but never
//  read the mouse. `zoom_config` appeared exactly once in the file: in the
//  Uniforms struct declaration. The cursor did nothing at all. It is now a
//  local heat source: hovering warms the cells under it, holding drives them
//  toward arc breakdown, and clicks inject bounded thermal shock fronts.
//
//  Also fixed:
//    - canonical `@workgroup_size(16, 16, 1)` (house convention).
//    - Depth clobber: `writeDepthTexture` was fed the emission luma, so chained
//      depth-aware shaders read glow instead of geometry. Scene depth preserved.
//    - Unbounded additive HDR: `bg + emitted` was written straight out with
//      `alpha = luma` uncapped. Blackbody emission times the glow term easily
//      exceeds 1, so highlights clipped hard and alpha went out of range. Now
//      ACES-mapped with a clamped semantic alpha.
//    - `dataTextureA` held diagnostics that nothing read. It now carries the
//      THERMAL STATE the diffusion below reads back (r = T/20000 K), display
//      goes to writeTexture, and B carries the diagnostics.
//
//  TWO NEW STRUCTURES
//
//    1. Per-cell FFT band ownership — every cell hashes to one of the eight
//       spectrum bins, which sets its base temperature and flicker rate. The
//       array now reads as a spectrum analyser made of hot filaments rather
//       than one globally-modulated grid.
//
//    2. Thermal diffusion with radiative cooling — cell temperature is carried
//       through dataTextureC and relaxed toward its target with a Stefan-
//       Boltzmann-style T^4 cooling term, so filaments heat quickly under the
//       cursor and cool slowly afterwards instead of snapping instantly.
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,  // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=GridDensity, y=BaseTemp, z=AudioHeat, w=GlowWidth
    ripples:     array<vec4<f32>, 50>,
}

// Planck blackbody colour (1000K–20000K) → approximate linear RGB
fn blackbody(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 20000.0);
    var r: f32; var g: f32; var b: f32;
    if (t <= 6600.0) {
        r = 1.0;
        g = clamp((99.47 * log(t / 100.0) - 161.12) / 255.0, 0.0, 1.0);
        b = select(0.0, clamp((138.52 * log(t / 100.0 - 10.0) - 305.04) / 255.0, 0.0, 1.0), t > 2000.0);
    } else {
        let lt = t / 100.0 - 60.0;
        r = clamp(329.70 * pow(lt, -0.1332) / 255.0, 0.0, 1.0);
        g = clamp(288.12 * pow(lt, -0.0755) / 255.0, 0.0, 1.0);
        b = 1.0;
    }
    return vec3<f32>(r, g, b);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 127.1 + 311.7) * 43758.5453);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord   = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    let uv      = vec2<f32>(global_id.xy) / resolution;
    let time    = u.config.x;
    let bass    = plasmaBuffer[0].x;
    let mids    = plasmaBuffer[0].y;
    let treble  = plasmaBuffer[0].z;
    let mouse   = u.zoom_config.yz;
    let held    = step(0.5, u.zoom_config.w);

    let gridN     = mix(4.0, 20.0, u.zoom_params.x);
    let baseT     = mix(800.0, 12000.0, u.zoom_params.y);   // Kelvin
    let audioHeat = mix(0.0, 8000.0, u.zoom_params.z);
    let glowW     = mix(0.02, 0.45, u.zoom_params.w);

    let aspect = resolution.x / resolution.y;
    let gridUV = vec2<f32>(uv.x * aspect, uv.y) * gridN;
    let cell   = floor(gridUV);
    let frac   = fract(gridUV);

    // Each cell has a unique base temperature & oscillation phase
    let h    = hash22(cell);
    let h1   = hash11(cell.x * 13.7 + cell.y * 7.3);

    // ── Structure 1: each cell owns one FFT bin ──────────────────────────────
    // The bin sets the cell's base temperature and its flicker rate, so the
    // array behaves like a filament spectrum analyser instead of one grid all
    // pulsing together.
    let bandIdx = u32(h.x * 8.0) % 8u;
    let band = plasmaBuffer[bandIdx + 1u].x;

    let osc  = 0.5 + 0.5 * sin(time * (1.0 + h.x * 3.0 + band * 4.0) + h.y * 6.28318);
    let audioBoost = bass * audioHeat + mids * audioHeat * 0.3 + treble * audioHeat * 0.15
                   + band * audioHeat * 0.8;

    // ── Mouse as a local heat source (was never read at all) ─────────────────
    let aspectV = vec2<f32>(aspect, 1.0);
    let mouseDist = length((uv - mouse) * aspectV);
    let mouseHeat = exp(-mouseDist * mouseDist * 26.0) * (2500.0 + held * 7000.0);

    // ── Bounded click thermal shocks ─────────────────────────────────────────
    var shockHeat = 0.0;
    var shockGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.2) {
            let r = length((uv - rp.xy) * aspectV);
            let front = r - age * 0.55;
            let env = exp(-front * front * 150.0) * exp(-age * 1.5);
            shockHeat += env * 9000.0;
            shockGlow += env * env;
        }
    }
    shockGlow = min(shockGlow, 1.2);

    let targetT = baseT + h1 * 4000.0 + osc * 2500.0 + audioBoost + mouseHeat + shockHeat;

    // ── Structure 2: thermal diffusion with radiative cooling ────────────────
    // Previous cell temperature is carried in dataTextureC (r channel, scaled by
    // 20000 K). Heating is fast; cooling follows a Stefan-Boltzmann-style T^4
    // law, so filaments linger after the cursor leaves.
    let prevState = textureLoad(dataTextureC, coord, 0);
    let prevT = prevState.r * 20000.0;
    let tNorm = clamp(prevT / 20000.0, 0.0, 1.0);
    let t2 = tNorm * tNorm;
    let radiative = 0.06 + 0.32 * t2 * t2;                  // ~T^4 cooling
    let heating = 0.55;
    let rate = select(radiative, heating, targetT > prevT);
    let T = mix(prevT, targetT, clamp(rate, 0.02, 1.0));

    // Distance from cell centre: multiple emission shapes
    let centre = vec2<f32>(0.5);
    let d      = length(frac - centre);

    // Secondary: Voronoi-style nearest feature for texture
    let d2 = length(frac - (centre + (h - 0.5) * 0.3));

    // Gaussian hotspot brightness (depends on temperature)
    let sigmaGlow = glowW * (T / 8000.0); // hotter = wider glow
    let spot      = exp(-d * d / (sigmaGlow * sigmaGlow));

    // Halo: faint outer glow at lower temperature
    let haloT  = T * 0.5;
    let halo   = exp(-d2 * d2 / (sigmaGlow * sigmaGlow * 4.0)) * 0.3;

    // Blackbody colour for hotspot and halo
    let bbHot  = blackbody(T);
    let bbHalo = blackbody(haloT);

    // Combine
    var emitted = bbHot * spot + bbHalo * halo;

    // Flicker: Poisson-style random intensity variation
    let flicker = 0.85 + 0.15 * sin(time * (5.0 + h.x * 20.0) + h.y * 100.0);
    emitted *= flicker;

    // Plasma arc: thin bright lines connecting neighbouring cells (high treble)
    let arcUV  = frac - 0.5;
    let arcLine = exp(-abs(arcUV.y) * 25.0 / max(treble * 0.5 + 0.1, 0.1));
    let arcGlow = arcLine * treble * 0.4;
    emitted += blackbody(18000.0) * arcGlow * h.x;

    // Read background for compositing with depth
    let bg    = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Objects in foreground cast shadows (near depth blocks light)
    let shadowMask = mix(0.3, 1.0, depth);
    emitted *= shadowMask;

    emitted += vec3<f32>(1.0, 0.75, 0.45) * shockGlow * (1.2 + bass * 1.4);
    emitted += vec3<f32>(0.35, 0.65, 1.0) * exp(-mouseDist * mouseDist * 40.0) * (0.3 + held * 0.9);

    // Add glow onto background, then tone map (was written raw and clipped).
    let luma     = dot(emitted, vec3<f32>(0.2126, 0.7152, 0.0722));
    let finalRGB = acesFilm(bg + emitted);

    // Semantic alpha: emission is the content, the plate behind it is not.
    let alpha = clamp(luma * 0.85 + shockGlow * 0.3 + 0.08, 0.0, 1.0);
    let outColor = vec4<f32>(finalRGB, alpha);

    textureStore(writeTexture, coord, outColor);
    // A carries THERMAL STATE, not display RGBA — the diffusion above reads it
    // back as dataTextureC next frame, and a half-colour/half-temperature
    // packing would hand chained shaders a red channel that is really Kelvin.
    // Same convention as the Batch 58B liquid sims: state in A, display in
    // writeTexture, diagnostics in B.
    textureStore(dataTextureA, coord, vec4<f32>(T / 20000.0, spot, luma, osc));
    textureStore(dataTextureB, coord, vec4<f32>(finalRGB, shockGlow));

    // Depth: scene geometry preserved (was overwritten with emission luma).
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

