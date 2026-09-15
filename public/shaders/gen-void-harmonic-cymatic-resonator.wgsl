// ═══════════════════════════════════════════════════════════════════
//  Void Harmonic Cymatic Resonator
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: nodal Chladni membranes inside the resonator; continuous adjacent-mode splitting with moving degeneracy seams
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Frequency, .y = Amplitude, .z = Glow Intensity, .w = Complexity
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.005;

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp(
        (x * (a * x + b)) / (x * (c * x + d) + e),
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );
}

fn standingWave(p: vec3<f32>, freq: f32, phase: f32) -> f32 {
    let waveX = sin(p.x * freq + phase) * cos(p.y * freq * 0.5 - phase * 0.35);
    let waveY = sin(p.y * freq - phase * 0.7) * cos(p.z * freq * 0.5 + phase * 0.2);
    let waveZ = sin(p.z * freq + phase * 0.45) * cos(p.x * freq * 0.5 - phase * 0.3);
    return (waveX + waveY + waveZ) / 3.0;
}

// Idea 2 — continuous mode splitting. The saved Complexity control still bounds
// the harmonic loop, while its continuous value crossfades a neighboring
// eigenmode. Their slow energy exchange exposes moving degeneracy seams.
fn splitModes(p: vec3<f32>, freq: f32, complexity: f32, time: f32) -> vec3<f32> {
    let primary = standingWave(p, freq, time * 0.17);
    let adjacentFreq = freq * (1.0 + 0.42 / (complexity + 2.0));
    let adjacent = standingWave(p, adjacentFreq, -time * 0.13 + complexity * 0.19);
    let transition = smoothstep(0.0, 1.0, fract(complexity));
    let exchange = 0.5 + 0.5 * sin(time * (0.42 + complexity * 0.025));
    let modeMix = clamp(0.12 + transition * 0.34 + exchange * 0.18, 0.0, 0.64);
    let pressure = mix(primary, adjacent, modeMix);
    let seam = exp(-abs(primary - adjacent) * 18.0);
    return vec3<f32>(primary, pressure, seam);
}

// Returns distance, standing-wave pressure, degeneracy seam, and radius.
fn resonatorField(p_in: vec3<f32>, audio: vec3<f32>) -> vec4<f32> {
    var p = p_in;

    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse_uv.x * 2.0, -mouse_uv.y * 2.0, 0.0);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let mouse_delta = p - mouse_pos;
    let warp = held / (1.0 + dot(mouse_delta, mouse_delta));
    p = mix(p, mouse_pos, warp * 0.5);

    let t = u.config.x * 0.5;
    let r1 = rot(t * 0.2);
    let xz = r1 * p.xz;
    p = vec3<f32>(xz.x, p.y, xz.y);
    let r2 = rot(t * 0.3);
    let xy = r2 * p.xy;
    p = vec3<f32>(xy, p.z);

    let freq = u.zoom_params.x * (1.0 + audio.x * 0.45);
    let amp = u.zoom_params.y * (0.75 + audio.y * 0.25);
    let comp = clamp(u.zoom_params.w, 1.0, 10.0);
    let modes = splitModes(p, freq, comp, t);
    let base_shape = modes.y * amp;
    let d_sphere = length(p) - 3.0;

    var disp = 0.0;
    var f = 1.0;
    var a = 0.5;
    for (var i = 0; i < i32(comp) && i < 5; i = i + 1) {
        disp = disp + a * sin(dot(p, vec3<f32>(f)) + t);
        f = f * 2.0;
        a = a * 0.5;
    }

    let distance = smin(d_sphere, base_shape + disp * 0.5, 0.5);
    return vec4<f32>(distance, modes.y, modes.z, length(p));
}

fn getNormal(p: vec3<f32>, audio: vec3<f32>) -> vec3<f32> {
    let d = resonatorField(p, audio).x;
    let e = vec2<f32>(0.01, 0.0);
    let n = d - vec3<f32>(
        resonatorField(p - e.xyy, audio).x,
        resonatorField(p - e.yxy, audio).x,
        resonatorField(p - e.yyx, audio).x
    );
    return normalize(n + vec3<f32>(0.00001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(coord) - 0.5 * res) / max(res.y, 1.0);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let previous = textureLoad(dataTextureC, coord, 0);

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    var p = ro;
    var dO = 0.0;
    var surfaceGlow = 0.0;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        let field = resonatorField(p, audio);
        let dS = field.x;
        dO = dO + dS;
        p = ro + rd * dO;
        surfaceGlow = surfaceGlow + exp(-abs(dS) * 12.0) * 0.018;
        if (abs(dS) < SURF_DIST) {
            hit = true;
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
    }

    // Idea 1 — nodal membranes. Integrate zero crossings of the same combined
    // three-axis pressure field through the sphere, so the resonator reveals
    // thin luminous Chladni sheets rather than only a lit outer shell.
    var membraneGlow = 0.0;
    var seamGlow = 0.0;
    let amplitude = max(u.zoom_params.y, 0.2);
    let hitWeight = select(0.0, 1.0, hit);
    for (var j = 0; j < 24; j = j + 1) {
        let q = p + rd * (f32(j) * 0.24);
        let field = resonatorField(q, audio);
        let inside = 1.0 - smoothstep(2.7, 3.05, field.w);
        let nodal = exp(-abs(field.y) * 24.0 / amplitude);
        membraneGlow = membraneGlow + nodal * inside * 0.075 * hitWeight;
        seamGlow = seamGlow + field.z * inside * 0.045 * hitWeight;
    }

    let glow_intensity = u.zoom_params.z;
    var hdr = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p, audio);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ambient = 0.1;
        let base_col = 0.5 + 0.5 * cos(u.config.x + p.xyx + vec3<f32>(0.0, 2.0, 4.0));
        hdr = base_col * (diff + ambient);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        hdr = hdr + fresnel * vec3<f32>(0.0, 0.8, 1.2) * (0.35 + audio.y * 0.65);
    }

    let glow_col = vec3<f32>(0.1, 0.2, 0.8) * (0.25 + audio.x * 0.75)
                 + vec3<f32>(0.9, 0.1, 0.5) * (0.2 + audio.y * 0.8)
                 + vec3<f32>(0.1, 0.8, 0.9) * (0.2 + audio.z * 0.8);
    hdr = hdr + glow_col * surfaceGlow * 0.7 * glow_intensity;
    hdr = hdr + vec3<f32>(0.12, 0.75, 1.4) * membraneGlow * glow_intensity;
    hdr = hdr + vec3<f32>(1.25, 0.18, 0.85) * seamGlow * glow_intensity;
    let fog = 1.0 - exp(-0.02 * min(dO, MAX_DIST) * min(dO, MAX_DIST));
    hdr = mix(hdr, vec3<f32>(0.0, 0.0, 0.05), fog * 0.65);

    let mapped = acesToneMap(max(hdr, vec3<f32>(0.0)));
    let historyPresent = step(0.001, dot(abs(previous), vec4<f32>(1.0)));
    let displayRgb = mix(mapped, previous.rgb, historyPresent * 0.06);
    let hitCoverage = select(0.0, 0.42, hit);
    let alpha = clamp(
        hitCoverage + membraneGlow * 0.38 + seamGlow * 0.25 + surfaceGlow * 0.08,
        0.0,
        1.0
    );
    let finalColor = vec4<f32>(displayRgb, alpha);
    let depth = select(1.0, clamp(dO / MAX_DIST, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}