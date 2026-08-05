// ----------------------------------------------------------------
// Fractal Chrono-Dendrite Forge (Visualist Upgrade)
// Category: generative
// ----------------------------------------------------------------

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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1, y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4 (normalized 0-1 sliders)
  ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// CONSTANTS & UTILITIES
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// SCENE SDF
// ----------------------------------------------------------------
fn map(p_in: vec3<f32>, time: f32, mouse_pos: vec2<f32>, click: f32, complexity: f32, entropy: f32, gravity: f32, bass: f32) -> f32 {
    var p = p_in;

    // Spacetime Distortion (Mouse gravity)
    // The cursor position acts as a gravitational singularity: bounded by an
    // exponential falloff (finite, spatially local). Click deepens the well.
    let m_dist = length(p.xy - mouse_pos);
    let twist_amt = exp(-m_dist * 0.5) * gravity * 2.0 * (1.0 + click * 0.8);
    p = vec3<f32>(rot(twist_amt * sin(time)) * p.xy, p.z);

    // Global rotation and movement
    p = vec3<f32>(rot(time * 0.1) * p.xy, p.z);
    p = vec3<f32>(p.x, rot(time * 0.15) * p.yz);

    var d = 1000.0;

    // Fractal Spanning Trees: L-system inspired 3D recursive paths
    var scale = 1.0;
    let iterations = i32(mix(2.0, 5.0, complexity));
    var p_fract = p;

    for (var i = 0; i < iterations; i++) {
        p_fract = abs(p_fract) - vec3<f32>(0.5, 0.4, 0.6) * (1.0 + sin(time * entropy + f32(i)) * 0.2);
        p_fract = vec3<f32>(rot(0.5 + f32(i) * 0.1) * p_fract.xy, p_fract.z);
        p_fract = vec3<f32>(p_fract.x, rot(0.7 - f32(i) * 0.15) * p_fract.yz);
        scale *= 1.5;
        p_fract *= 1.5;

        let cylinder = length(p_fract.xy) - (0.1 + bass * 0.2) * (1.0 - f32(i) / f32(iterations));
        d = min(d, cylinder / scale);
    }

    // Chronos Node Intersections (Apollonian gasket-like spheres at junctions)
    let node_dist = length(p_fract) - (0.3 + bass * 0.5);
    d = max(d, -node_dist / scale); // Subtraction for hollow intersections

    return d;
}

// ----------------------------------------------------------------
// NORMALS & SHADING
// ----------------------------------------------------------------
fn getNormal(p: vec3<f32>, time: f32, mouse_pos: vec2<f32>, click: f32, complexity: f32, entropy: f32, gravity: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, mouse_pos, click, complexity, entropy, gravity, bass) - map(p - e.xyy, time, mouse_pos, click, complexity, entropy, gravity, bass),
        map(p + e.yxy, time, mouse_pos, click, complexity, entropy, gravity, bass) - map(p - e.yxy, time, mouse_pos, click, complexity, entropy, gravity, bass),
        map(p + e.yyx, time, mouse_pos, click, complexity, entropy, gravity, bass) - map(p - e.yyx, time, mouse_pos, click, complexity, entropy, gravity, bass)
    ));
}

// Spectral Interference colors for bismuth look
fn getBismuthColor(t: f32, dispersion: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0) * dispersion;
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

// ----------------------------------------------------------------
// MAIN RENDER LOOP
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let pixel = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // UI Sliders (updatedParams index order, normalized 0-1 → rescaled here)
    let complexity = u.zoom_params.x;                          // Dendrite Complexity
    let entropy = u.zoom_params.y * 2.0;                       // Entropy Pulse Rate (0..2)
    let dispersion = 0.1 + u.zoom_params.z * 2.9;              // Spectral Dispersion (0.1..3)
    let gravity = u.zoom_params.w * 2.0;                       // Gravity Well Strength (0..2)

    // Audio reaction
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Guarded engine FFT bins 1–8 → spectral shimmer on the thin-film phase
    var fftShimmer = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        for (var k = 1u; k <= 8u; k = k + 1u) {
            fftShimmer += extraBuffer[5u + k];
        }
        fftShimmer = clamp(fftShimmer * 0.125, 0.0, 1.5);
    }

    // Mouse Interaction (uv is 0-1, y=0 top; recentered to scene space)
    let mouse_pos = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let click = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching with bounded volumetric glow accumulation
    var d0 = 0.0;
    var col = vec3<f32>(0.0);
    var hit = false;
    var glowAccum = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * d0;
        let d = map(p, time, mouse_pos, click, complexity, entropy, gravity, bass);

        // Volumetric glow approximation: energy bleeds from near-misses.
        // Bounded: per-step term ≤ 0.02, total ≤ 2.4.
        glowAccum += exp(-max(d, 0.0) * 4.0) * 0.02;

        if (d < SURF_DIST) {
            hit = true;
            let n = getNormal(p, time, mouse_pos, click, complexity, entropy, gravity, bass);

            // Bismuth spectral dispersion shading (thin-film interference)
            let view_dir = -rd;
            let ndotv = max(dot(n, view_dir), 0.0);

            // Multiple layers of fractional noise control the thickness of an
            // imaginary thin-film layer; FFT shimmer animates the oxide film.
            let interference_t = ndotv + sin(length(p) * 5.0 + time * entropy) * 0.2
                               + fftShimmer * 0.15;
            let albedo = getBismuthColor(interference_t, dispersion);

            // ── 3-point lighting rig (three distinct temperatures) ──────
            // KEY: warm forge light, upper right
            let key_pos = vec3<f32>(2.0, 4.0, -3.0);
            let key_l = normalize(key_pos - p);
            let key_dif = max(dot(n, key_l), 0.0);
            let key_col = vec3<f32>(1.25, 0.85, 0.55);

            // FILL: cool chrono-blue, lower left, soft (half-wrapped diffuse)
            let fill_pos = vec3<f32>(-3.0, -1.5, -2.0);
            let fill_l = normalize(fill_pos - p);
            let fill_dif = clamp((dot(n, fill_l) + 0.5) / 1.5, 0.0, 1.0);
            let fill_col = vec3<f32>(0.35, 0.55, 1.10);

            // RIM: hot magenta backlight behind the dendrite → Fresnel rim
            let rim_col = vec3<f32>(1.35, 0.45, 0.95);
            let fresnel = pow(1.0 - ndotv, 3.0);

            // HDR specular from the key light (bloom-ready, exceeds 1.0)
            let spec = pow(max(dot(reflect(-key_l, n), view_dir), 0.0), 32.0) * 2.2;

            // Audio-Reactive Synapses (glowing nodes) — HDR emissive pulse
            let synapse_glow = (0.5 + 0.5 * sin(p.z * 10.0 - time * 5.0)) * (bass * 2.0 + mids);
            let glow_color = vec3<f32>(1.0, 0.5, 0.2) * synapse_glow;

            col = albedo * (key_col * key_dif + fill_col * fill_dif * 0.6)
                + rim_col * fresnel * (0.9 + treble * 0.6)
                + vec3<f32>(1.0) * spec
                + glow_color;

            // Volumetric fog: deep-violet chrono haze, tinted teal by the
            // accumulated near-miss glow (depth cue + atmosphere).
            let fogTint = mix(vec3<f32>(0.05, 0.0, 0.1), vec3<f32>(0.02, 0.10, 0.12), clamp(glowAccum, 0.0, 1.0));
            col = mix(col, fogTint, 1.0 - exp(-0.1 * d0));
            break;
        }

        if (d0 > MAX_DIST) {
            // Background / Deep-void chronosphere
            let bg_uv = rot(time * 0.05) * uv;
            col = vec3<f32>(0.02, 0.01, 0.05) * (1.0 - length(bg_uv));
            break;
        }
        d0 += d;
    }

    // Atmospheric near-miss aura visible even off-surface (bounded HDR)
    col += vec3<f32>(0.35, 0.75, 0.85) * glowAccum * 0.35;

    // ACES filmic rolloff; exposure breathes gently with the mids
    col = acesToneMap(col * (1.15 + mids * 0.25));

    // Vibrance: bounded saturation lift keyed on treble
    let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    col = clamp(mix(vec3<f32>(luma), col, 1.0 + treble * 0.18), vec3<f32>(0.0), vec3<f32>(1.0));

    // Semantic alpha: solid on hits, the void breathes with its aura
    let hitF = select(0.0, 1.0, hit);
    let alpha = clamp(0.82 + hitF * 0.18 + glowAccum * 0.05, 0.0, 1.0);

    // Real generated depth: near-is-one relief from raymarch travel distance
    let depthOut = select(0.0, 1.0 - clamp(d0 / 12.0, 0.0, 1.0), hit);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
