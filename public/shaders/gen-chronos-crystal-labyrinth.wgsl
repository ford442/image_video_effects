// ═══════════════════════════════════════════════════════════════════
//  Chronos Crystal Labyrinth
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: refractive time-fault seams; hour-line facet caustics; growth-zoning bands; corridor near-miss glow
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Dispersion, .y = Gravity Strength, .z = Fractal Fold, .w = Glow Intensity

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Distance functions
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Map the world
fn map(p: vec3<f32>) -> vec2<f32> {
    var q = p;

    // Domain repetition / folding
    q = abs(q) - u.zoom_params.z;
    q = abs(q) - u.zoom_params.z * 0.5;

    // Core geometry
    let d = sdOctahedron(q, 1.0);

    let audio = plasmaBuffer[0].xyz;
    let displacement = audio.x * 0.08 * sin(p.x * 10.0 + u.config.x) *
        cos(p.y * 10.0 + u.config.x);

    // Idea 1: diagonal time-fault planes pass through the repeated crystal cells.
    let fault_phase = abs(fract(dot(p, vec3<f32>(0.17, 0.11, -0.13)) - u.config.x * 0.035) - 0.5);
    let fault_seam = 1.0 - smoothstep(0.025, 0.09, fault_phase);
    let fault_offset = fault_seam * 0.018 * sin(p.z * 4.0 - u.config.x * (0.7 + audio.y * 0.15));

    return vec2<f32>(d + displacement + fault_offset, fault_seam);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Raymarching loop
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = vec2<f32>(coords) / resolution;
    let base_uv = uv;
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Mouse Interaction: Gravity well
    let mouse_uv = u.zoom_config.yz;
    var mouse_clip = mouse_uv * 2.0 - 1.0;
    mouse_clip.x *= resolution.x / resolution.y;

    var distortion = 0.0;
    if (u.zoom_config.w > 0.0) {
        distortion = u.zoom_params.y / (1.0 + pow(length(uv - mouse_clip), 2.0));
    }

    // Setup camera and rays
    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * 0.5);
    let ta = vec3<f32>(0.0, 0.0, u.config.x * 0.5);

    let cw = normalize(ta - ro);
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let cu = normalize(cross(cw, up));
    let cv = normalize(cross(cu, cw));

    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Apply distortion to ray direction
    rd = normalize(rd + (uv.x * cu + uv.y * cv) * distortion);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var fault_seam = 0.0;
    var corridor = 0.0;
    for(var i = 0; i < 100; i = i + 1) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        fault_seam = res.y;
        if(d < 0.001 || t > 20.0) { break; }
        // Idea 4 — corridor near-miss glow: rays grazing crystal walls collect leaked light
        corridor += exp(-abs(d) * 30.0) * 0.012 / (1.0 + t * 0.15);
        t += d * 0.5; // Step size
    }
    corridor = min(corridor, 1.5);

    var col = vec3<f32>(0.0);
    var alpha = 0.04;
    let hit = t < 20.0;
    let audio = plasmaBuffer[0].xyz;

    if(hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Refraction / Chromatic dispersion approximation
        let disp = u.zoom_params.x * 0.1;
        let rR = reflect(rd, n); // Simple reflection for now
        let rG = reflect(rd, n + vec3<f32>(disp));
        let rB = reflect(rd, n - vec3<f32>(disp));

        // Simplified lighting / glow
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, l), 0.0);
        let glow = u.zoom_params.w * (1.0 / (1.0 + t*t*0.1));

        col = vec3<f32>(dif) * vec3<f32>(0.5, 0.7, 1.0) + vec3<f32>(glow * 0.5, glow * 0.2, glow * 0.8);

        // Add pseudo-dispersion colors based on normal
        col += vec3<f32>(abs(rR.x), abs(rG.y), abs(rB.z)) * 0.3;

        // Idea 1: the fault seam locally splits and brightens refracted facets.
        let fault_chroma = vec3<f32>(1.0, 0.22 + audio.y * 0.1, 0.7) * fault_seam;
        col += fault_chroma * (0.35 + disp * 0.4);

        // Idea 2: twelve narrow hour lines sweep across folded facets as caustics.
        let hour_phase = abs(fract(atan2(p.y, p.x) / TAU * 12.0 + p.z * 0.18 - u.config.x * 0.12) - 0.5);
        let hour_caustic = pow(1.0 - clamp(hour_phase * 7.0, 0.0, 1.0), 3.0);
        let caustic_color = mix(vec3<f32>(0.15, 0.55, 1.0), vec3<f32>(1.0, 0.65, 0.12), fault_seam);
        col += caustic_color * hour_caustic * (0.3 + glow * 0.15 + audio.z * 0.08);

        // Idea 3 — growth zoning: bands parallel to facet edges, like zoned quartz; Fractal Fold sets density
        var zq = abs(p) - u.zoom_params.z;
        zq = abs(abs(zq) - u.zoom_params.z * 0.5);
        let edgeDist = min(zq.x, min(zq.y, zq.z));
        let bandCount = 5.0 + u.zoom_params.z * 3.0;
        let zone = fract(edgeDist * bandCount - u.config.x * 0.02);
        let zoneLine = smoothstep(0.08, 0.0, abs(zone - 0.5) - 0.38);
        let zoneTint = mix(vec3<f32>(0.75, 0.6, 1.0), vec3<f32>(0.6, 0.95, 1.0), fract(floor(edgeDist * bandCount) * 0.37));
        col = col * (0.88 + 0.12 * zone) + zoneTint * zoneLine * (0.12 + disp * 0.15 + audio.y * 0.06);
        alpha = clamp(0.2 + dif * 0.45 + fault_seam * 0.2 + hour_caustic * 0.25 + glow * 0.08 + zoneLine * 0.05, 0.0, 1.0);
    } else {
        // Background
        col = vec3<f32>(0.05, 0.05, 0.1) * (1.0 - length(uv) * 0.5);
    }
    let corridor_col = mix(vec3<f32>(0.25, 0.5, 1.0), vec3<f32>(0.9, 0.5, 1.0), 0.5 + 0.5 * sin(t * 0.4 + u.config.x * 0.3));
    col += corridor_col * corridor * u.zoom_params.w * (0.6 + audio.x * 0.4);
    alpha = clamp(max(alpha, corridor * 0.35), 0.0, 1.0);

    col += vec3<f32>(audio.x * 0.08, audio.y * 0.04, audio.z * 0.1) *
        (0.35 + 0.65 * (1.0 - length(base_uv - vec2<f32>(0.5))));

    let display_rgb = acesToneMap(max(col, vec3<f32>(0.0)));
    let final_col = vec4<f32>(display_rgb, alpha);
    let source_depth = textureLoad(readDepthTexture, coords, 0).r;
    let depth = select(source_depth, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coords, final_col);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, final_col);
}
