// ═══════════════════════════════════════════════════════════════
//  Holographic Data Core - Generative hologram with interference physics
//  Category: generative
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, volume diffraction, 60Hz flicker
//  Description: An infinite journey through a quantum lattice of glowing 
//               data nodes with volumetric interference effects
// ═══════════════════════════════════════════════════════════════

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

const N_AIR: f32 = 1.0;
const N_VOLUME: f32 = 1.45;  // Volume hologram refractive index
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// SDF Primitives
// ═══════════════════════════════════════════════════════════════

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    var q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    var d = abs(vec2<f32>(length(p.xz), p.y)) - c;
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
    // Volume gratings have angle-dependent efficiency
    let gratingDir = normalize(cellPos + vec3<f32>(0.0, 1.0, 0.0));
    let cosTheta = dot(viewDir, gratingDir);
    
    // Bragg condition approximation
    let braggOffset = abs(cosTheta - wavelength * 0.5);
    return exp(-braggOffset * braggOffset * 50.0);
}

// Volumetric interference spectrum
fn volumetricInterference(p: vec3<f32>, viewDir: vec3<f32>, time: f32) -> vec3<f32> {
    // Optical path varies through volume
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
    var q = (p + 0.5 * c) % c - 0.5 * c;

    // Cell ID for variation
    let cell_id = floor((p + 0.5 * c) / c);

    // Base Node (Box)
    let box_d = sdBox(q, vec3<f32>(0.6));

    // Inner Floating Core
    let inner_d = sdBox(q, vec3<f32>(0.3));

    // Active Data Pulse logic
    var time = u.config.x;
    let pulse_rate = u.zoom_params.z;
    let pulse_val = sin(cell_id.x * 12.3 + cell_id.y * 45.6 + cell_id.z * 78.9 + time * pulse_rate * 5.0);

    var node_res = MapResult(max(box_d, -sdBox(q, vec3<f32>(0.4))), 1.0);
    if (pulse_val > 0.8) {
        node_res.mat_id = 2.0;
    }

    node_res = opU(node_res, MapResult(inner_d, 2.0));
    res = opU(res, node_res);

    // Circuits
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

    var time = u.config.x;
    let glitch_intensity = u.zoom_params.w;
    let travel_speed = u.zoom_params.y;

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Holographic Glitch (chromatic aberration & scanlines base)
    let glitch_hash = hash21(vec2<f32>(floor(time * 20.0), uv.y));
    if (glitch_intensity > 0.0 && glitch_hash < glitch_intensity * 0.1) {
        uv.x += (hash21(uv + vec2<f32>(time)) - 0.5) * 0.1 * glitch_intensity;
    }

    // Camera setup
    let cam_z = time * travel_speed * 2.0;

    // Mouse interaction for look around
    var mouse = u.zoom_config.yz;
    let mouse_ang_x = (mouse.x - 0.5) * 3.14;
    let mouse_ang_y = (mouse.y - 0.5) * 3.14;

    let ro = vec3<f32>(0.0, 0.0, cam_z);

    // Gentle wobble
    let look_at = ro + vec3<f32>(
        sin(time * 0.5) * 0.5 + sin(mouse_ang_x)*2.0,
        cos(time * 0.3) * 0.5 - sin(mouse_ang_y)*2.0,
        1.0
    );

    let fw = normalize(look_at - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fw));
    let up = cross(fw, right);

    var rd = normalize(fw + uv.x * right + uv.y * up);

    // Raymarching
    var t = 0.0;
    let max_steps = 80;
    let max_dist = 40.0;

    var col = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);
    
    // ═══════════════════════════════════════════════════════════════
    // Volumetric Interference Raymarching
    // ═══════════════════════════════════════════════════════════════

    for (var i = 0; i < max_steps; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.d;

        // Calculate interference at this point
        let interference = volumetricInterference(p, -rd, time);

        // Volumetric Glow Accumulation with interference
        if (d > 0.0) {
            let g_dist = max(d, 0.001);
            if (res.mat_id == 1.0) {
                glow += vec3<f32>(0.0, 0.5, 1.0) * (0.01 / g_dist) * (1.0 + interference.b);
            } else if (res.mat_id == 2.0) {
                glow += vec3<f32>(1.0, 0.2, 0.5) * (0.02 / g_dist) * (1.0 + interference.r);
            } else if (res.mat_id == 3.0) {
                glow += vec3<f32>(0.0, 0.8, 0.8) * (0.005 / g_dist) * (1.0 + interference.g);
            }
        }

        if (d < 0.01) {
            let n = getNormal(p);

            // Basic rim lighting / fresnel for structure with interference
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            
            // Apply interference colors
            let intColor = interference * 2.0;

            if (res.mat_id == 1.0) {
                col += vec3<f32>(0.1, 0.5, 0.8) * fresnel * (1.0 + intColor.b);
            } else if (res.mat_id == 2.0) {
                col += vec3<f32>(1.0, 0.5, 0.2) * (1.0 + fresnel) * (1.0 + intColor.r);
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

    // Depth fade (fog)
    let fog = 1.0 - exp(-t * t * 0.002);
    col = mix(col, vec3<f32>(0.0, 0.02, 0.05), fog);

    // Chromatic aberration / scanline post-process
    if (glitch_intensity > 0.0) {
        let scanline = sin(uv.y * 800.0) * 0.04 * glitch_intensity;
        col -= vec3<f32>(scanline);

        // Simple radial chromatic aberration based on glitch
        let dist_center = length(uv);
        let ca_shift = dist_center * 0.05 * glitch_intensity;
        col.r *= 1.0 + ca_shift;
        col.b *= 1.0 - ca_shift;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation for Volumetric Hologram
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency (volume holograms are very transparent)
    let base_alpha = 0.06;
    
    // Calculate overall interference intensity
    let interference_intensity = (col.r + col.g + col.b) / 3.0;
    
    // Alpha boosted where volume emits light
    var alpha = base_alpha + min(interference_intensity * 0.4, 0.35);
    
    // Glow increases alpha
    let glow_intensity = length(glow);
    alpha += glow_intensity * 0.02;
    
    // Fog reduces alpha (distant objects more transparent)
    alpha *= (1.0 - fog * 0.5);
    
    // Scanline alpha modulation
    alpha *= holographicScanlines(vec2<f32>(global_id.xy) / resolution, time);
    
    // 60Hz flicker
    alpha *= projectionFlicker(time);
    
    // Glitch causes alpha instability
    let glitchAlpha = 1.0 - glitch_intensity * 0.15 * hash21(vec2<f32>(time, uv.y));
    alpha *= glitchAlpha;
    
    // Depth-based alpha (nodes at different depths have varying transparency)
    let depth_factor = 1.0 - smoothstep(10.0, 40.0, t);
    alpha *= 0.7 + depth_factor * 0.3;
    
    // Pepper's ghost effect (volume holograms have internal reflections)
    let ghost_col = col * 0.5;
    col = mix(col, ghost_col, PEPPER_GHOST_REFLECTION);
    
    // Volumetric speckle
    let speckle = hash21(uv * 80.0 + vec2<f32>(time * 2.0));
    alpha *= 0.92 + speckle * 0.16;
    
    // Cap alpha
    alpha = min(alpha, 0.5);

    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));

    // Pass through depth (mock)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(global_id.xy)/resolution, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
