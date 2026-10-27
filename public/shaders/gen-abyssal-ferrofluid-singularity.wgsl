// ═══════════════════════════════════════════════════════════════════
//  Abyssal Ferrofluid Singularity
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-26
//  Ideas: step-count AO (§12.2E); SDF curvature wear (§12.2E)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- MATH / NOISE HELPERS ---
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn gyroid(p: vec3<f32>, scale: f32) -> f32 {
    let q = p * scale;
    return abs(dot(sin(q), cos(q.zxy)) / scale);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// --- SDF ---
fn getDist(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Magnetic Mouse Warp
    if (u.zoom_config.w > 0.5) {
        // Map mouse uv to -1 to 1 space
        let mouse_pos = (u.zoom_config.yz * 2.0) - 1.0;
        let p_warp = vec3<f32>(mouse_pos.x * 3.0, -mouse_pos.y * 3.0, 0.0);
        let dist_to_mouse = length(p - p_warp);
        if (dist_to_mouse < 2.0) {
            p = mix(p, p_warp, 1.0 - smoothstep(0.0, 2.0, dist_to_mouse));
        }
    }

    // Base Sphere
    let dSphere = length(p) - 1.5;

    // Audio Reactivity (bass drives displacement scale)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let dyn_scale = u.zoom_params.x + bass * 2.0;

    // Gyroid Displacement
    let dGyroid = gyroid(p + vec3<f32>(0.0, u.config.x * u.zoom_params.y, 0.0), dyn_scale);

    // Breathing time displacement
    let breath = sin(u.config.x) * 0.1;

    // Combine
    return smin(dSphere, dGyroid - breath, 0.5) * 0.5; // Scale down for precision
}

// --- NORMALS ---
fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 1: step-count AO (§12.2E) ────────────────────────────────
fn aoFive(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i: i32 = 1; i <= 5; i = i + 1) {
        let h = 0.015 + 0.12 * f32(i) / 5.0;
        occ += (h - getDist(p + n * h)) * sca;
        sca *= 0.5;
    }
    return clamp(1.0 - 2.4 * occ, 0.0, 1.0);
}

// ── Idea 2: SDF curvature (§12.2E) ────────────────────────────────
fn curvature(p: vec3<f32>) -> f32 {
    let e = 0.02;
    let d = getDist(p);
    let s = getDist(p + vec3<f32>(e, 0.0, 0.0)) + getDist(p - vec3<f32>(e, 0.0, 0.0))
          + getDist(p + vec3<f32>(0.0, e, 0.0)) + getDist(p - vec3<f32>(0.0, e, 0.0))
          + getDist(p + vec3<f32>(0.0, 0.0, e)) + getDist(p - vec3<f32>(0.0, 0.0, e));
    return (s - 6.0 * d) / max(e * e, 1e-5);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = getDist(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        getDist(p - e.xyy),
        getDist(p - e.yxy),
        getDist(p - e.yyx)
    );
    return normalize(n);
}

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let uv = vec2<f32>(id.xy) / vec2<f32>(dims);

    // Map to -1, 1 space correcting aspect ratio
    var p_uv = uv * 2.0 - 1.0;
    p_uv.x *= f32(dims.x) / f32(dims.y);

    // Camera setup
    let ro = vec3<f32>(sin(u.config.x * 0.2) * 4.0, sin(u.config.x * 0.1) * 2.0, cos(u.config.x * 0.2) * 4.0);
    let cam_target = vec3<f32>(0.0);

    let cd = normalize(cam_target - ro);
    let cr = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), cd));
    let cu = normalize(cross(cd, cr));

    let rd = normalize(cr * p_uv.x + cu * p_uv.y + cd * 1.5);

    // Raymarching
    var dO = 0.0;
    var dS = 0.0;
    var hit = false;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        dS = getDist(p);
        dO += dS;
        if(dS < SURF_DIST) {
            hit = true;
            break;
        }
        if(dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * dO;
        let n = getNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let reflectDir = reflect(-lightDir, n);
        let viewDir = normalize(ro - p);
        let spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0); // Simple specular

        // Fresnel / Iridescence
        let fresnel = 1.0 - max(dot(n, viewDir), 0.0);
        let iriCol = vec3<f32>(0.0, 1.0, 1.0) * pow(fresnel, 3.0) + vec3<f32>(1.0, 0.0, 1.0) * pow(fresnel, 5.0);

        // Core glow (inverse distance from center)
        let distCenter = length(p);
        let glow = smoothstep(1.5, 0.5, distCenter) * vec3<f32>(0.2, 0.0, 0.5) * clamp(plasmaBuffer[0].z, 0.0, 1.0); // Treble drives core glow

        let ao = aoFive(p, n);
        let kappa = curvature(p);
        let tipLight = smoothstep(0.25, 1.4, kappa);
        let crease = smoothstep(0.05, 0.85, -kappa);
        col = vec3<f32>(diff * 0.1) * ao
            + vec3<f32>(spec) * (0.35 + 0.65 * tipLight)
            + mix(vec3<f32>(0.0), iriCol, u.zoom_params.z)
            + glow * u.zoom_params.w * ao;
        col *= 1.0 - crease * 0.45;
        let cover = clamp(0.55 + fresnel * 0.4 + tipLight * 0.1, 0.0, 1.0);
        col = acesFilm(max(col, vec3<f32>(0.0)));
        let final_col = vec4<f32>(col, cover);
        textureStore(writeTexture, id.xy, final_col);
        textureStore(writeDepthTexture, id.xy, vec4<f32>(clamp(dO / MAX_DIST, 0.0, 1.0), 0.0, 0.0, 0.0));
        textureStore(dataTextureA, id.xy, final_col);
        return;
    }

    col = vec3<f32>(0.01, 0.01, 0.02) * (1.0 - length(p_uv));
    let bg = acesFilm(max(col, vec3<f32>(0.0)));
    let bgAlpha = clamp(0.18 + (1.0 - length(p_uv)) * 0.12, 0.0, 1.0);
    let missed = vec4<f32>(bg, bgAlpha);
    textureStore(writeTexture, id.xy, missed);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(clamp(dO / MAX_DIST, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, missed);
}