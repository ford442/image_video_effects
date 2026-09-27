// ═══════════════════════════════════════════════════════════════════
//  Quantum-Entangled Ferrofluid Engine
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven, quantum-interference
//  Complexity: Very High
//  Scientific Math: Wavefunction ψ(x,t), Probability Density |ψ|², Quantum Measurement Collapse
//  Chunks From: original gen-quantum-entangled-ferrofluid-engine
//  Created: 2026-05-31
//  Upgraded: 2026-09-27
//  Ideas: Rosensweig spike lattice; entangled-pair |psi|^2 bead filaments; |psi|^2 nodal contours on the metal
//  A packing: ACES display RGBA
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Magnetic Strength, y=Fluid Viscosity, z=Quantum Glow, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: acesToneMap (canonical ACES) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453) * 2.0 - vec3<f32>(1.0);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        val += amp * noise3(pos);
        pos *= 2.0;
        amp *= 0.5;
    }
    return val;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ═══ Quantum Wavefunction: ψ(x,t) = A·sin(kx−ωt) + i·cos(kx−ωt) ═══
fn wavefunction(p: vec3<f32>, t: f32, k: f32, w: f32) -> f32 {
    let phaseX = k * p.x - w * t;
    let phaseY = k * p.y - w * t;
    let psiReal = sin(phaseX) * cos(phaseY);
    let psiImag = cos(phaseX) * sin(phaseY);
    // Probability density |ψ|² = ψ* · ψ (real-valued, 0 to 1)
    return psiReal * psiReal + psiImag * psiImag;
}

// ═══ Double-slit interference pattern ═══
fn interferencePattern(p: vec2<f32>, t: f32, slitSep: f32, wavelength: f32) -> f32 {
    let d1 = length(p - vec2<f32>(-slitSep * 0.5, 0.0));
    let d2 = length(p - vec2<f32>( slitSep * 0.5, 0.0));
    let pathDiff = d2 - d1;
    let phase = 6.283185307 * pathDiff / wavelength - t * 2.0;
    return 0.5 + 0.5 * cos(phase);
}

// Global variables to store glow (cyan = centre lines, bead = pair filaments)
var<private> global_glow: f32 = 0.0;
var<private> global_bead: f32 = 0.0;

// Inverse of acesToneMap (per channel) so C history can re-enter the linear mix
fn acesInverse(y: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    let yy = clamp(y, vec3<f32>(0.0), vec3<f32>(0.999));
    let qa = a - c * yy;
    let qb = b - d * yy;
    let disc = max(qb * qb + 4.0 * qa * e * yy, vec3<f32>(0.0));
    return max((-qb + sqrt(disc)) / (2.0 * qa), vec3<f32>(0.0));
}

// Satellite orbit (same formulas the original loop used)
fn satPos(fi: f32, t: f32) -> vec3<f32> {
    return vec3<f32>(
        sin(t * 0.5 + fi * 1.5) * 2.5,
        cos(t * 0.4 + fi * 2.1) * 2.5,
        sin(t * 0.6 + fi * 0.8) * 2.5
    );
}

// [IDEA 2] entangled-pair filament: segment a-b with a standing |psi|^2 bead wave
fn pairFilament(pos: vec3<f32>, a: vec3<f32>, b: vec3<f32>, t: f32, phase: f32) {
    let ba = b - a;
    let pa = pos - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    let dist = length(pa - ba * h);
    let w = max(0.12 - dist, 0.0) / 0.12;
    if (w > 0.0) {
        let node = sin(h * 3.14159265 * 5.0);
        let bead = node * node * node * node;              // antinode beads
        let pulse = 0.5 + 0.5 * cos(t * 2.5 + phase);       // antiphase between pairs
        global_bead += w * bead * pulse * 0.12;
        global_glow += w * 0.03;
    }
}

// [IDEA 1] Rosensweig lattice: icosahedral-axis cosine sum -> cones on the shell
fn rosensweigLattice(dirIn: vec3<f32>, t: f32) -> f32 {
    let dir = rotY(t * 0.12) * dirIn;
    let s0 = 0.5257311;   // 1/sqrt(1+phi^2)
    let s1 = 0.8506508;   // phi/sqrt(1+phi^2)
    let k = 7.0;
    var sum = cos(k * dot(dir, vec3<f32>(0.0,  s0,  s1)));
    sum += cos(k * dot(dir, vec3<f32>(0.0, -s0,  s1)));
    sum += cos(k * dot(dir, vec3<f32>( s0,  s1, 0.0)));
    sum += cos(k * dot(dir, vec3<f32>(-s0,  s1, 0.0)));
    sum += cos(k * dot(dir, vec3<f32>( s1, 0.0,  s0)));
    sum += cos(k * dot(dir, vec3<f32>( s1, 0.0, -s0)));
    let s = sum / 6.0;
    return pow(max(s - 0.2, 0.0) / 0.8, 1.6);
}

fn map(p: vec3<f32>) -> f32 {
    let t = u.config.x;

    let mag_strength = u.zoom_params.x;
    let viscosity = u.zoom_params.y;
    let audio_react = u.zoom_params.w;

    // Audio reactivity via plasmaBuffer
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Low frequency audio (real plasmaBuffer; 0.1 floor keeps the silent look)
    let audio_lf = 0.1 + bass * 0.6 + mids * 0.3;

    // Mouse Interaction (measurement disturbance)
    let aspect = u.config.z / u.config.w;
    let mx = (u.zoom_config.y * 2.0 - 1.0) * aspect;
    let my = u.zoom_config.z * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mx * 3.0, my * 3.0, 0.0);

    // Measurement disturbance: mouse proximity collapses superposition
    let dist_to_mouse = length(p - mouse_pos);
    let collapse_factor = exp(-dist_to_mouse * 0.5) * mag_strength;
    let dir_to_mouse = normalize(mouse_pos - p);

    var pos = p;
    if (dist_to_mouse > 0.001) {
        pos += dir_to_mouse * collapse_factor * 0.5;
    }

    // Quantum probability density drives ferrofluid spike amplitude
    let quantum_prob = wavefunction(pos, t + bass * 2.0, 2.0 + mids, 1.5 + treble);
    let prob_amp = quantum_prob * (1.0 + bass * audio_react);

    // Central sphere
    var d = length(pos) - 1.5;

    // Satellite droplets (quantum entangled)
    for(var i = 0; i < 4; i++) {
        let fi = f32(i);
        let sat_pos = satPos(fi, t);
        let d_sat = length(pos - sat_pos) - 0.3;
        d = smin(d, d_sat, viscosity * 1.5);

        // Entanglement connection (glow)
        let sat_dir = normalize(sat_pos);
        let line_dist = length(cross(pos, sat_dir));
        if (line_dist < 0.2) {
            global_glow += (0.2 - line_dist) * exp(-length(pos)*0.5);
        }
    }

    // [IDEA 2] entangled pairs 0<->1 and 2<->3, antiphase bead pulse
    pairFilament(pos, satPos(0.0, t), satPos(1.0, t), t, 0.0);
    pairFilament(pos, satPos(2.0, t), satPos(3.0, t), t, 3.14159265);

    // Spikes (Ferrofluid effect driven by quantum probability density |ψ|²)
    let n_freq = 3.0 + mag_strength * 2.0;
    let n_amp = 0.3 + audio_lf * audio_react * 0.8 + prob_amp * 0.5;

    // Add audio ripples mapping
    // (click fronts: age = time - startTime, active up to rippleCount, uv mapped like the mouse)
    var audio_disp = 0.0;
    for(var i = 0; i < 5; i++) {
        if (f32(i) >= u.config.y) { break; }
        let rp = u.ripples[i];
        let age = max(t - rp.z, 0.0);
        let rp_pos = vec2<f32>((rp.x * 2.0 - 1.0) * aspect * 3.0, (rp.y * 2.0 - 1.0) * 3.0);
        let d_rp = length(pos.xy - rp_pos);
        audio_disp += sin(d_rp * 10.0 - age * 5.0) * 0.5 * exp(-d_rp * 2.0) * exp(-age * 1.5);
    }

    let disp = fbm(pos * n_freq + vec3<f32>(t * 0.5)) * n_amp + audio_disp;

    // Sharpen spikes modulated by quantum collapse probability
    let spike = pow(abs(disp), 1.5 + bass * 0.5) * sign(disp);

    d += spike;

    // [IDEA 1] Rosensweig cones: field must exceed a critical value (smoothstep on
    // Magnetic Strength), taller on the side facing the mouse magnet.
    let rlen = length(pos);
    if (rlen < 3.4 && rlen > 0.001) {
        let dir = pos / rlen;
        let magdir = normalize(vec3<f32>(mx, my, 1.5));
        let pole = 0.55 + 0.45 * dot(dir, magdir);
        let field = smoothstep(0.2, 1.2, mag_strength);
        let shell = exp(-max(rlen - 1.5, 0.0) * 3.0);
        d -= rosensweigLattice(dir, t) * 0.22 * field * pole * shell;
    }

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.005, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let tex_size = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= tex_size.x || f32(id.y) >= tex_size.y) {
        return;
    }

    let uv = vec2<f32>(f32(id.x), f32(id.y)) / tex_size * 2.0 - 1.0;
    let aspect = tex_size.x / tex_size.y;
    let pt = vec2<f32>(uv.x * aspect, uv.y);

    // Audio
    let bass = plasmaBuffer[0].x;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let rd = normalize(vec3<f32>(pt, -2.0));

    // Raymarching
    var t_dist = 0.0;
    var d = 0.0;
    var p = ro;

    global_glow = 0.0;
    global_bead = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t_dist;
        d = map(p);
        if (d < 0.001 || t_dist > 15.0) {
            break;
        }
        t_dist += d * 0.7;
    }

    // Snapshot glow now: calcNormal()/thickness map() calls below would keep accumulating it
    let march_glow = global_glow;
    let march_bead = global_bead;

    var col = vec3<f32>(0.05, 0.02, 0.08);

    if (d < 0.005) {
        let n = calcNormal(p);
        let v = -rd;
        let l1 = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let l2 = normalize(vec3<f32>(-1.0, -1.0, 0.5));

        // PBR Material (Iridescent Black/Purple Metallic)
        let base_col = vec3<f32>(0.1, 0.05, 0.15);

        let diff1 = max(dot(n, l1), 0.0);
        let diff2 = max(dot(n, l2), 0.0);

        let h1 = normalize(l1 + v);
        let spec1 = pow(max(dot(n, h1), 0.0), 64.0);

        let h2 = normalize(l2 + v);
        let spec2 = pow(max(dot(n, h2), 0.0), 32.0);

        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 4.0);

        // Chromatic aberration reflection map (simulated)
        let ref_dir = reflect(rd, n);
        let ref_r = fbm(ref_dir * 4.0);
        let ref_g = fbm(ref_dir * 4.1);
        let ref_b = fbm(ref_dir * 4.2);
        let env_ref = vec3<f32>(ref_r, ref_g, ref_b) * 0.5 + 0.5;

        col = base_col * (diff1 * 0.8 + diff2 * 0.3) + vec3<f32>(1.0) * spec1 + vec3<f32>(0.5, 0.2, 0.8) * spec2;
        col += env_ref * fresnel * 2.0;

        // Magnetic subsurface scattering (fake)
        let thickness = map(p - n * 0.1);
        col += vec3<f32>(0.2, 0.0, 0.5) * exp(-abs(thickness) * 10.0);

        // [IDEA 3] |psi|^2 iso-contours (same wave that drives the spikes) traced on the metal
        let mids_s = plasmaBuffer[0].y;
        let treble_s = plasmaBuffer[0].z;
        let psi = wavefunction(p, u.config.x + bass * 2.0, 2.0 + mids_s, 1.5 + treble_s);
        let contour = 1.0 - smoothstep(0.0, 0.05, abs(psi - 0.5));
        col += vec3<f32>(0.1, 0.7, 1.0) * contour * (0.35 + fresnel) * u.zoom_params.z * 0.25;
    }

    // Quantum interference pattern overlay in background
    let t = u.config.x;
    let interference = interferencePattern(pt, t, 0.4 + bass * 0.2, 0.15);
    col += vec3<f32>(0.0, 0.15, 0.25) * interference * 0.15;

    // Add Quantum Entanglement Glow
    let glow_intensity = u.zoom_params.z;
    col += vec3<f32>(0.0, 0.8, 1.0) * march_glow * glow_intensity * 0.05;
    col += vec3<f32>(1.0, 0.2, 0.8) * march_bead * glow_intensity * 0.05;   // [IDEA 2] bead tint

    // Vignette
    col *= 1.0 - length(pt) * 0.3;

    // ═══ Chromatic Aberration ═══
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // ═══ Temporal Feedback ═══
    // C holds ACES display RGB (x1.1 exposure): decode back to the linear pre-ACES domain first
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    col = mix(acesInverse(prev.rgb) / 1.1 * 0.96, col, 0.25);

    // ═══ ACES Tone Map + Semantic Alpha ═══
    col = acesToneMap(col * 1.1);
    let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
