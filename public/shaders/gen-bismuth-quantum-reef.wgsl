// ═══════════════════════════════════════════════════════════════════
//  Bismuth Quantum Reef
//  Category: generative
//  Features: raymarching, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: hopper stair-steps on crystal facets (§12.2E); per-crystal / per-step oxide zoning (§12.2E fold-as-material); Beer–Lambert interior SSS (§12.2F)
//  A packing: raw (normal.xyz, depth) in dataTextureA as before; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Constants & Utilities
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;
const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Pseudo-random and noise functions
fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// SDF primitives
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

// Domain-repeated cell frame, shared by map() and the shading pass so the
// per-crystal hash and facet octant are available as a material (Idea 2).
struct Cell {
    p: vec3<f32>,
    r: vec3<f32>,
}

fn cellFrame(p_in: vec3<f32>) -> Cell {
    var p = p_in;
    let t = u.config.x;
    let crystal_density = u.zoom_params.y; // 0.5 - 2.0

    // Mouse distortion (Gravity Well)
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = u.zoom_config.yz;
        // Target point in front of the camera (camera z = t * 2, so the well rides with it)
        let target_pt = vec3<f32>((mouse_uv.x - 0.5) * 10.0, -(mouse_uv.y - 0.5) * 10.0, 5.0 + t * 2.0);
        let dist_to_mouse = length(p - target_pt);
        if (dist_to_mouse < 4.0) {
            let pull = smoothstep(4.0, 0.0, dist_to_mouse) * 2.0;
            p = mix(p, target_pt, pull * 0.3);
        }
    }

    // Domain repetition based on density
    let spacing = 4.0 / crystal_density;
    let id = floor(p / spacing);
    p = fract(p / spacing) * spacing - spacing * 0.5;

    // Variation per cell
    let r = hash33(id);

    // Rotate crystals slightly based on their ID and time
    var pxy = p.xy * rot2D(t * 0.2 + r.z * 6.28);
    p = vec3<f32>(pxy, p.z);

    var pxz = p.xz * rot2D(t * 0.3 + r.y * 6.28);
    p = vec3<f32>(pxz.x, p.y, pxz.y);
    return Cell(p, r);
}

// Map function (Domain repetition + SDF evaluation)
fn map(p_in: vec3<f32>) -> f32 {
    let t = u.config.x;

    // Params
    let quantum_fluctuation = u.zoom_params.x; // 0.0 - 1.0

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let audio_pulse = mix(0.0, bass * 0.5 + mids * 0.2, 0.5);

    let cell = cellFrame(p_in);
    let p = cell.p;
    let r = cell.r;

    // Base crystal SDF (intersection of box and octahedron)
    let s = 1.0 + audio_pulse * 0.5 + r.x * 0.5;
    let d1 = sdBox(p, vec3<f32>(s * 0.7));
    let d2 = sdOctahedron(p, s * 1.2);
    var d = max(d1, d2); // Intersection

    // ── Idea 1: hopper stair-steps (§12.2E). Bismuth grows as hoppers: nested
    // terraces on every facet. The octahedral coordinate |x|+|y|+|z| is turned
    // into a continuous stair profile (flat tread, steep riser) and carved only
    // where the octahedron facet is the active surface.
    let hop = (abs(p.x) + abs(p.y) + abs(p.z)) * 2.2 / s;
    let hopFr = fract(hop);
    let stair = smoothstep(0.62, 0.95, hopFr) - hopFr;
    let facetOn = smoothstep(-0.05, 0.05, d2 - d1);
    d += 0.045 * stair * facetOn;

    // Noise displacement (quantum fluctuation)
    if (quantum_fluctuation > 0.0) {
        let noise_freq = 2.0;
        let noise_amp = 0.2 * quantum_fluctuation;
        let noise_val = sin(p_in.x * noise_freq + t) * sin(p_in.y * noise_freq + t * 1.1) * sin(p_in.z * noise_freq + t * 0.9);
        d += noise_val * noise_amp;
    }

    return d;
}

// Raymarching loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var dO: f32 = 0.0;
    var steps_taken: f32 = 0.0;
    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS;
        steps_taken += 1.0;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }
    return vec2<f32>(dO, steps_taken);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

// Iridescent Color Palette
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn palette(t: f32) -> vec3<f32> {
    // Cosine based palette for Bismuth colors
    // a = 0.5, b = 0.5, c = 1.0, d = vec3(0.0, 0.33, 0.67)
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv = (fragCoord - 0.5 * resolution) / resolution.y;
    let t = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, t * 2.0); // Move forward over time

    // Look-at matrix
    let lookAtTarget = ro + vec3<f32>(0.0, 0.0, 1.0);
    let forward = normalize(lookAtTarget - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    let rd = normalize(forward + uv.x * right + uv.y * up);

    // Raymarching
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let steps = rm.y;

    // Background color
    var col = vec3<f32>(0.01, 0.02, 0.05);
    var depth = 1.0;
    var out_n = vec3<f32>(0.0);
    var glow_t = 0.0;
    var fres_a = 0.0;

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = calcNormal(p);
        out_n = n;

        let iridescence_shift = u.zoom_params.z;
        let sss_glow = u.zoom_params.w;

        // Shading
        let viewDir = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);
        fres_a = fresnel;

        // ── Idea 2: per-crystal / per-facet / per-step oxide zoning (§12.2E). Each crystal
        // carries its own hue epoch, each of its 8 facet octants and each hopper step
        // adds an offset, so the field is zoned instead of one smooth rainbow.
        let cell = cellFrame(p);
        let octant = f32(u32(cell.p.x > 0.0) + 2u * u32(cell.p.y > 0.0) + 4u * u32(cell.p.z > 0.0));
        let stepIdx = floor((abs(cell.p.x) + abs(cell.p.y) + abs(cell.p.z)) * 2.2 / (1.0 + cell.r.x * 0.5));
        let zoning = cell.r.x * 0.37 + octant * 0.071 + stepIdx * 0.045;

        // Base color based on position and normal
        let color_t = fract(p.z * 0.1 + p.x * 0.05 + p.y * 0.05 + fresnel * 2.0 + iridescence_shift + t * 0.1 + zoning);
        var base_col = palette(color_t);

        // Fake SSS
        let sss_sample_dist = 0.1;
        let sss_val = map(p + viewDir * sss_sample_dist);
        let sss_factor = smoothstep(0.0, sss_sample_dist, sss_val);
        base_col += vec3<f32>(0.0, 0.8, 1.0) * sss_glow * (1.0 - sss_factor) * 0.5;

        // ── Idea 3: Beer–Lambert interior SSS (§12.2F). Probe the crystal body behind
        // the surface along -n; thin shells (edges, step lips) transmit exp(-σ·thickness)
        // of the cyan glow, thick bodies stay dark.
        var thin = 0.0;
        var wsum = 0.0;
        for (var k = 1; k <= 3; k = k + 1) {
            let sd = 0.12 * f32(k);
            let inside = clamp(sd + map(p - n * sd), 0.0, sd) / sd; // 0 = solid behind, 1 = already outside
            thin += inside / f32(k);
            wsum += 1.0 / f32(k);
        }
        let thickness = 1.0 - thin / wsum;
        let transmit = exp(-3.0 * thickness);
        glow_t = transmit;
        base_col += vec3<f32>(0.1, 0.9, 1.0) * sss_glow * transmit * 0.6;

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let amb = 0.1 + 0.1 * n.y;

        // Specular
        let refl = reflect(-lightDir, n);
        let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

        col = base_col * (diff + amb) + vec3<f32>(1.0) * spec * fresnel;

        // Ambient occlusion from steps
        let ao = 1.0 - clamp(steps / f32(MAX_STEPS), 0.0, 1.0);
        col *= ao * 1.5;

        // Fog
        let fog = exp(-d * 0.05);
        col = mix(vec3<f32>(0.01, 0.02, 0.05), col, fog);

        depth = d / MAX_DIST;
    }

    // Post-processing (vignette)
    col *= 1.0 - 0.5 * dot(uv, uv);

    // display ACES; alpha = coverage (hit) with edge fresnel and interior glow, background 0.9
    col = acesToneMap(max(col, vec3<f32>(0.0)));
    let hitA = clamp(0.82 + 0.12 * fres_a + 0.06 * glow_t, 0.0, 1.0);
    let finalColor = vec4<f32>(col, select(0.9, hitA, depth < 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Write to other required textures
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(out_n, depth));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
