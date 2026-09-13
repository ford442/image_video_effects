// ═══════════════════════════════════════════════════════════════════
//  Liquid-Metal Cymatic Resonator
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: real viscosity drag from C history; Chladni nodal crystallization; ferrofluid spikes under the pointer
//  A packing: ACES display RGBA (C read back via exact textureLoad as colour history)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Resonance, .y = Viscosity, .z = Iridescence, .w = Complexity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ----------------------------------------------------------------
// Helper functions
// ----------------------------------------------------------------

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

// ----------------------------------------------------------------
// Core Cymatic Algorithm
// ----------------------------------------------------------------

fn mapHeight(p: vec2<f32>, audio: f32, bass: f32) -> f32 {
    let resonance = u.zoom_params.x; // 1.0 to 5.0
    let complexity = u.zoom_params.w; // 1.0 to 10.0
    let t = u.config.x * 0.5;

    // Polar coordinates
    let r = length(p);
    let theta = atan2(p.y, p.x);

    var h = 0.0;

    // Mouse perturbation
    let mouse_uv = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);
    let aspect = u.config.z / u.config.w;
    let mouse_pos = (mouse_uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

    let dist_to_mouse = length(p - mouse_pos);
    let mouse_influence = exp(-dist_to_mouse * 5.0) * 0.5;

    let base_freq = resonance + audio * 5.0 + mouse_influence * 10.0;

    // Sum of wave functions (Fourier series)
    let iters = i32(complexity);
    for (var i = 1; i <= 10; i++) {
        if (i > iters) { break; }

        let fi = f32(i);
        let freq = base_freq * fi;
        let phase = t * (1.0 + fi * 0.2);

        // Standing waves in radial and angular directions
        let wave = sin(r * freq - phase) * cos(theta * fi + phase * 0.5);

        // Amplitude falls off for higher frequencies
        let amp = 1.0 / (fi * 1.5);
        h += wave * amp;
    }

    // Idea 3: ferrofluid Rosensweig spikes — the pointer is the magnet; a hexagonal
    // spike lattice rises out of the metal around it, taller on bass hits.
    let fp = (p - mouse_pos) * 18.0;
    let hexWave = (cos(fp.x) + cos(0.5 * fp.x + 0.866 * fp.y) + cos(-0.5 * fp.x + 0.866 * fp.y)) / 3.0;
    let spikes = pow(max(hexWave, 0.0), 3.0);
    h += spikes * exp(-dist_to_mouse * 6.0) * (0.25 + bass * 0.45);

    // Add central audio peak
    h += exp(-r * 3.0) * audio * 0.5;

    // Smooth the heightfield
    h = smax(h, -0.2, 0.1);

    return h * 0.2; // Scale down overall height
}

fn getNormal(p: vec3<f32>, audio: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.005, 0.0);
    let hx = mapHeight(p.xz + e.xy, audio, bass) - mapHeight(p.xz - e.xy, audio, bass);
    let hz = mapHeight(p.xz + e.yx, audio, bass) - mapHeight(p.xz - e.yx, audio, bass);
    return normalize(vec3<f32>(-hx, e.x * 2.0, -hz));
}

// ----------------------------------------------------------------
// Shading and Environment
// ----------------------------------------------------------------

// Simple procedural environment map
fn getEnvColor(dir: vec3<f32>) -> vec3<f32> {
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let t = clamp(dot(dir, up) * 0.5 + 0.5, 0.0, 1.0);

    let color_bottom = vec3<f32>(0.1, 0.1, 0.15); // Dark blueish
    let color_top = vec3<f32>(0.8, 0.9, 1.0);   // Bright sky

    // Add a fake "sun" reflection
    let sun_dir = normalize(vec3<f32>(1.0, 1.0, 1.0));
    let sun_spec = pow(max(dot(dir, sun_dir), 0.0), 32.0) * vec3<f32>(1.0, 0.9, 0.7);

    return mix(color_bottom, color_top, t) + sun_spec;
}

// Thin film iridescence approximation
fn iridescence(NdotV: f32, thickness: f32) -> vec3<f32> {
    // Phase shift based on viewing angle and thickness
    let phase = NdotV * 5.0 + thickness * 10.0;

    // Color channels get shifted sine waves
    let r = 0.5 + 0.5 * sin(phase);
    let g = 0.5 + 0.5 * sin(phase + 2.094); // + 120 deg
    let b = 0.5 + 0.5 * sin(phase + 4.188); // + 240 deg

    return vec3<f32>(r, g, b);
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);

    if (coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) {
        return;
    }

    // Normalize coordinates
    let uv = vec2<f32>(coord) / vec2<f32>(dims);
    let aspect = u.config.z / u.config.w;
    let p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

    // Audio from the FFT buffer (HEAD filtered-sampled dataTextureC.r here, which is colour history, not audio)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass * 0.3;

    // Camera setup
    let ro = vec3<f32>(0.0, 2.5, -2.5); // Fixed camera above and slightly back
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    let rd = normalize(p.x * cu + p.y * cv + 2.0 * cw);

    // Raymarching
    var t_dist = 0.0;
    var d = 0.0;
    let max_dist = 10.0;
    let max_steps = 100;

    var pos = ro;
    var hit = false;

    for (var i = 0; i < max_steps; i++) {
        pos = ro + rd * t_dist;

        // Signed distance to the heightfield plane
        let h = mapHeight(pos.xz, audio, bass);
        d = pos.y - h;

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t_dist > max_dist) {
            break;
        }

        // Move forward carefully since heightfield is a bound
        t_dist += d * 0.5;
    }

    var color = vec3<f32>(0.0);
    var fresnelMean = 0.0;
    var node = 0.0;
    var pool = 0.0;

    if (hit) {
        let n = getNormal(pos, audio, bass);
        let v = -rd; // View vector
        let NdotV = max(dot(n, v), 0.0);

        // Base metallic properties
        let f0 = vec3<f32>(0.8); // High base reflectivity for silver metal

        // Schlick approximation for Fresnel
        let fresnel = f0 + (1.0 - f0) * pow(1.0 - NdotV, 5.0);

        // Reflection vector
        let refl = reflect(rd, n);

        // Sample environment map
        let envColor = getEnvColor(refl);

        // Iridescence
        let irid_intensity = u.zoom_params.z; // 0.0 to 2.0
        // Use height and audio for thickness variation
        let hSurf = mapHeight(pos.xz, audio, bass);
        let thickness = hSurf * 2.0 + audio * 0.1 + mids * 0.15;
        let iridColor = iridescence(NdotV, thickness);

        // Combine base metal reflection with iridescence
        let reflectionColor = mix(envColor * fresnel, envColor * iridColor, irid_intensity * (1.0 - NdotV)); // Stronger at grazing angles

        color = reflectionColor;
        fresnelMean = (fresnel.x + fresnel.y + fresnel.z) / 3.0;

        // Idea 2: Chladni nodal crystallization — distance to the standing wave's zero
        // crossing (|h| / slope) marks the nodal lines; the metal crystallizes there into
        // thin cool filigree with a tighter specular, glinting with treble.
        let slope = length(n.xz) / max(n.y, 0.05);
        let nodeDist = abs(hSurf) / max(slope, 0.02);
        node = 1.0 - smoothstep(0.0, 0.012, nodeDist);
        let crystalSpec = pow(max(dot(refl, normalize(vec3<f32>(1.0, 1.0, 1.0))), 0.0), 96.0);
        let glintPhase = sin(dot(pos.xz, vec2<f32>(91.7, 57.3)) + u.config.x * 7.0) * 0.5 + 0.5;
        let crystal = vec3<f32>(0.85, 0.95, 1.1) * (0.35 + crystalSpec * 2.0 + glintPhase * treble * 0.8);
        color = mix(color, color * 0.6 + crystal, node * 0.7);

        // Viscosity (temporal accumulation / motion blur effect approximation)
        // Since we can't easily read back history cleanly here without a dedicated pass,
        // we'll simulate a visual "drag" by darkening based on steepness to look like deep pools
        let viscosity = u.zoom_params.y; // 0.0 to 1.0
        let pool_darkening = smoothstep(0.8, 1.0, n.y); // Flatter areas
        pool = pool_darkening * viscosity;
        color *= mix(1.0, 0.4, pool);

    } else {
        // Background
        color = getEnvColor(rd);
    }

    // Tone map, then gamma correction
    color = aces(color * 1.15);
    color = pow(color, vec3<f32>(1.0 / 2.2));

    // Idea 1: real viscosity drag — thicker metal settles slowly, so the display lags
    // behind the resonance through exact colour history (replaces the old "can't read history" note).
    let viscosityDrag = clamp(u.zoom_params.y, 0.0, 1.0) * 0.75;
    let previous = textureLoad(dataTextureC, coord, 0);
    color = mix(color, previous.rgb, viscosityDrag);

    let skyT = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    let alpha = select(0.25 + 0.35 * skyT,
                       clamp(0.7 + 0.2 * fresnelMean + node * 0.15 - pool * 0.1, 0.0, 1.0),
                       hit);
    let depth = select(1.0, clamp(t_dist / max_dist, 0.0, 0.995), hit);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
