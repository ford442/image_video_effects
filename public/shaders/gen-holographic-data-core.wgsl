// ═══════════════════════════════════════════════════════════════════
//  Holographic Data Core
//  Category: generative
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-06
//  Ideas: logic bus photon energy packets; hexagonal quantum containment cage; depth parallax moiré fringe interference
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// SDF Primitives
// ═══════════════════════════════════════════════════════════════

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Volume hologram diffraction
fn volumeDiffraction(viewDir: vec3<f32>, wavelength: f32, cellPos: vec3<f32>) -> f32 {
    let gratingDir = normalize(cellPos + vec3<f32>(0.0, 1.0, 0.0));
    let cosTheta = dot(viewDir, gratingDir);
    let braggOffset = abs(cosTheta - wavelength * 0.5);
    return exp(-braggOffset * braggOffset * 50.0);
}

// Volumetric interference spectrum
fn volumetricInterference(p: vec3<f32>, viewDir: vec3<f32>, time: f32) -> vec3<f32> {
    let opticalPath = 0.42 + sin(p.x * 2.0 + p.y * 1.5 + p.z * 0.5 + time * 0.3) * 0.08;
    
    let volR = volumeDiffraction(viewDir, LAMBDA_R, p);
    let volG = volumeDiffraction(viewDir, LAMBDA_G, p);
    let volB = volumeDiffraction(viewDir, LAMBDA_B, p);
    
    let intR = thinFilmInterference(opticalPath, LAMBDA_R, 1.0) * volR;
    let intG = thinFilmInterference(opticalPath, LAMBDA_G, 1.0) * volG;
    let intB = thinFilmInterference(opticalPath, LAMBDA_B, 1.0) * volB;
    
    return vec3<f32>(intR, intG, intB);
}

// 60Hz flicker
fn projectionFlicker(time: f32) -> f32 {
    return 0.9 + 0.1 * sin(time * 377.0);
}

// Holographic scanlines for generative
fn holographicScanlines(uv: vec2<f32>, time: f32) -> f32 {
    let scanline = sin(uv.y * 800.0 + time * 15.0) * 0.5 + 0.5;
    return 0.9 + scanline * 0.1;
}

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════
// Map Function
// ═══════════════════════════════════════════════════════════════

struct MapResult {
    d: f32,
    mat_id: f32,
};

fn opU(d1: MapResult, d2: MapResult) -> MapResult {
    if (d1.d < d2.d) { return d1; }
    return d2;
}

fn map(p: vec3<f32>) -> MapResult {
    var res = MapResult(1000.0, 0.0);

    let node_density = u.zoom_params.x;
    let spacing = 4.0 / max(node_density, 0.1);

    // Domain repetition
    let c = vec3<f32>(spacing);
    let q = (p + 0.5 * c) % c - 0.5 * c;

    // Cell ID for variation
    let cell_id = floor((p + 0.5 * c) / c);

    // Base Node (Box)
    let box_d = sdBox(q, vec3<f32>(0.6));

    // Inner Floating Core
    let inner_d = sdBox(q, vec3<f32>(0.3));

    // Active Data Pulse logic
    let time = u.config.x;
    let pulse_rate = u.zoom_params.z;
    let pulse_val = sin(cell_id.x * 12.3 + cell_id.y * 45.6 + cell_id.z * 78.9 + time * pulse_rate * 5.0);

    var node_res = MapResult(max(box_d, -sdBox(q, vec3<f32>(0.4))), 1.0);
    if (pulse_val > 0.8) {
        node_res.mat_id = 2.0;
    }

    node_res = opU(node_res, MapResult(inner_d, 2.0));
    res = opU(res, node_res);

    // Circuits (Cylinders along 3 axes)
    let cyl_radius = 0.05;
    let cx = sdCylinder(vec3<f32>(q.y, q.x, q.z), vec2<f32>(cyl_radius, spacing * 0.5));
    let cy = sdCylinder(q, vec2<f32>(cyl_radius, spacing * 0.5));
    let cz = sdCylinder(vec3<f32>(q.x, q.z, q.y), vec2<f32>(cyl_radius, spacing * 0.5));

    let circuit_d = min(cx, min(cy, cz));
    var circuit_res = MapResult(circuit_d, 3.0);
    if (pulse_val > 0.6 && pulse_val < 0.8) {
        circuit_res.mat_id = 2.0;
    }

    res = opU(res, circuit_res);
    return res;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    ));
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let pixel = vec2<i32>(global_id.xy);

    let time = u.config.x;
    let glitch_intensity = u.zoom_params.w;
    let travel_speed = u.zoom_params.y;
    let pulse_rate = u.zoom_params.z;

    // Audio reactivity — bass swells node glow, treble drives projection flicker
    let audioBands = plasmaBuffer[0].xyz;
    let bass = audioBands.x;
    let mids = audioBands.y;
    let treble = audioBands.z;

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Smooth scan packets replace frame-hash jumps with continuous motion.
    let glitchBand = pow(0.5 + 0.5 * sin(uv.y * 110.0 - time * (7.0 + travel_speed * 3.0)), 18.0);
    uv.x += sin(uv.y * 37.0 + time * 3.0) * 0.055 * glitch_intensity * glitchBand;

    let packetPhase = fract(uv.y * (4.0 + u.zoom_params.x * 2.0) - time * (0.35 + travel_speed * 0.08));
    let midPacket = pow(1.0 - abs(packetPhase * 2.0 - 1.0), 10.0) * mids;
    uv += vec2<f32>(sin(time * 2.2 + uv.y * 19.0), cos(time * 1.7 + uv.x * 13.0)) * midPacket * 0.025;

    // Camera setup
    let cam_z = time * travel_speed * 2.0;

    // Mouse interaction for look around
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouse_ang_x = (mouse.x - 0.5) * 3.14;
    let mouse_ang_y = (mouse.y - 0.5) * 3.14;

    let ro = vec3<f32>(0.0, 0.0, cam_z);

    // Gentle wobble
    let look_at = ro + vec3<f32>(
        sin(time * 0.5) * 0.5 + sin(mouse_ang_x) * (2.0 + mouseDown),
        cos(time * 0.3) * 0.5 - sin(mouse_ang_y) * (2.0 + mouseDown),
        1.0
    );

    let fw = normalize(look_at - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fw));
    let up = cross(fw, right);

    let rd = normalize(fw + uv.x * right + uv.y * up);

    // Raymarching
    var t = 0.0;
    let max_steps = 80;
    let max_dist = 40.0;

    var col = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);
    
    // ═══════════════════════════════════════════════════════════════
    // Volumetric Interference Raymarching
    // ═══════════════════════════════════════════════════════════════

    for (var i = 0; i < max_steps; i = i + 1) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.d;

        var interference = vec3<f32>(0.0);
        let nearField = d < 2.0;
        if (nearField) {
            interference = volumetricInterference(p, -rd, time);
        }

        // Volumetric Glow Accumulation with interference
        if (d > 0.0 && nearField) {
            let g_dist = max(d, 0.001);
            let glowBoost = 1.0 + bass * 0.5;
            if (res.mat_id == 1.0) {
                glow += vec3<f32>(0.0, 0.5, 1.0) * (0.01 / g_dist) * (1.0 + interference.b) * glowBoost;
            } else if (res.mat_id == 2.0) {
                glow += vec3<f32>(1.0, 0.2, 0.5) * (0.02 / g_dist) * (1.0 + interference.r) * glowBoost;
            } else if (res.mat_id == 3.0) {
                // ─── Native Idea 1: Logic bus photon energy packets ───
                let packetSpeed = time * (4.0 + travel_speed * 2.0) * pulse_rate;
                let photonZ = pow(max(0.5 + 0.5 * sin(p.z * 3.0 - packetSpeed), 0.0), 16.0);
                let photonX = pow(max(0.5 + 0.5 * sin(p.x * 3.0 + packetSpeed * 0.8), 0.0), 16.0);
                let photonPulse = (photonZ + photonX) * (1.2 + bass * 1.5);
                glow += (vec3<f32>(0.0, 0.8, 0.8) + vec3<f32>(0.3, 1.0, 0.6) * photonPulse) * (0.006 / g_dist) * (1.0 + interference.g) * glowBoost;
            }
        }

        if (d < 0.01) {
            let n = getNormal(p);
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let intColor = interference * 2.0;

            let spacing = 4.0 / max(u.zoom_params.x, 0.1);
            let c_node = vec3<f32>(spacing);
            let q_cell = (p + 0.5 * c_node) % c_node - 0.5 * c_node;

            // ─── Native Idea 2: Hexagonal quantum containment lattice cage ───
            let hexDist = max(abs(q_cell.x) * 0.866025 + abs(q_cell.y) * 0.5, abs(q_cell.y)) - 0.68;
            let cageWire = smoothstep(0.04, 0.005, abs(hexDist)) * step(abs(q_cell.z), 0.62);
            let cageGlow = vec3<f32>(0.1, 0.85, 1.0) * cageWire * (0.7 + mids * 0.5);

            if (res.mat_id == 1.0) {
                col += vec3<f32>(0.1, 0.5, 0.8) * fresnel * (1.0 + intColor.b) + cageGlow;
            } else if (res.mat_id == 2.0) {
                col += vec3<f32>(1.0, 0.5, 0.2) * (1.0 + fresnel) * (1.0 + intColor.r) + cageGlow * 0.5;
            } else if (res.mat_id == 3.0) {
                col += vec3<f32>(0.2, 0.8, 1.0) * 0.5 * fresnel * (1.0 + intColor.g);
            }
            break;
        }

        if (t > max_dist) {
            break;
        }
        t += d * 0.7;
    }

    // Add glow with interference
    col += glow * 0.15;
    col += vec3<f32>(0.12, 0.72, 1.15) * midPacket * (0.3 + u.zoom_params.z * 0.35);

    // ─── Native Idea 3: Depth parallax moiré fringe interference ───
    let moirePhase = (uv.x * 240.0 + t * 3.5) * (uv.y * 240.0 - t * 2.8) * 0.002;
    let moirePattern = pow(0.5 + 0.5 * sin(moirePhase * 3.14159), 6.0) * (0.12 + treble * 0.18);
    col += vec3<f32>(0.1, 0.75, 1.0) * moirePattern * clamp(1.0 - t / max_dist, 0.0, 1.0);

    // Depth fade (fog)
    let fog = 1.0 - exp(-t * t * 0.002);
    col = mix(col, vec3<f32>(0.0, 0.02, 0.05), fog);

    // Chromatic aberration / scanline post-process
    if (glitch_intensity > 0.0) {
        let scanline = sin(uv.y * 800.0) * 0.04 * glitch_intensity;
        col -= vec3<f32>(scanline);
        let dist_center = length(uv);
        let ca_shift = dist_center * 0.05 * glitch_intensity;
        col.r *= 1.0 + ca_shift;
        col.b *= 1.0 - ca_shift;
    }
    
    // Alpha Calculation for Volumetric Hologram
    let base_alpha = 0.06;
    let interference_intensity = (col.r + col.g + col.b) / 3.0;
    var alpha = base_alpha + min(interference_intensity * 0.4, 0.35);
    
    let glow_intensity = length(glow);
    alpha += glow_intensity * 0.02;
    alpha *= (1.0 - fog * 0.5);
    alpha *= holographicScanlines(vec2<f32>(global_id.xy) / resolution, time);
    alpha *= projectionFlicker(time) * (1.0 - treble * 0.1);
    
    let glitchAlpha = 1.0 - glitch_intensity * 0.12 * glitchBand;
    alpha *= glitchAlpha;
    
    let depth_factor = 1.0 - smoothstep(10.0, 40.0, t);
    alpha *= 0.7 + depth_factor * 0.3;
    
    let ghost_col = col * 0.5;
    col = mix(col, ghost_col, PEPPER_GHOST_REFLECTION);
    
    let speckle = hash21(uv * 80.0 + vec2<f32>(sin(time * 0.7), cos(time * 0.6)) * 2.0);
    alpha *= 0.92 + speckle * 0.16;

    // Held-pointer beam and click-launched data rings.
    let uv01 = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let pointerDelta = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let pointerBeam = exp(-abs(pointerDelta.x) * 35.0) * exp(-length(pointerDelta) * 2.5) * mouseDown;
    col += vec3<f32>(0.15, 0.85, 1.4) * pointerBeam * (0.5 + bass);
    alpha += pointerBeam * 0.18;

    var clickGlow = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let d = length((uv01 - ripple.xy) * vec2<f32>(aspect, 1.0));
        let ring = exp(-abs(d - age * 0.38) * 80.0) * exp(-age * 1.3);
        clickGlow += vec3<f32>(0.25, 0.8, 1.0) * ring * (1.0 + treble);
    }
    col += clickGlow;
    alpha += length(clickGlow) * 0.12;
    
    alpha = min(alpha, 0.5);

    let previous = textureLoad(dataTextureC, pixel, 0);
    let display = clamp(mix(previous.rgb * 0.93, col, 0.32 + mouseDown * 0.12), vec3<f32>(0.0), vec3<f32>(8.0));
    let semanticAlpha = clamp(max(alpha, previous.a * 0.9), 0.0, 0.65);
    let outRGB = acesToneMap(display);

    textureStore(dataTextureA, pixel, vec4<f32>(outRGB, semanticAlpha));
    textureStore(writeTexture, pixel, vec4<f32>(outRGB, semanticAlpha));

    // Ray distance is generated scene depth
    let depth = clamp(t / max_dist, 0.0, 1.0);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
