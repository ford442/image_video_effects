// ----------------------------------------------------------------
// Celestial Prism-Orchid
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
// ---------------------------------------------------

// Structs
struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Bloom Complexity, y=Refractive Index, z=Core Intensity, w=Cosmic Wind Speed
    ripples: array<vec4<f32>, 50>,
};

// Utilities
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    return mix(
        mix(mix(hash31(vec3<f32>(n + 0.0)), hash31(vec3<f32>(n + 1.0)), u.x),
            mix(hash31(vec3<f32>(n + 157.0)), hash31(vec3<f32>(n + 158.0)), u.x), u.y),
        mix(mix(hash31(vec3<f32>(n + 113.0)), hash31(vec3<f32>(n + 114.0)), u.x),
            mix(hash31(vec3<f32>(n + 270.0)), hash31(vec3<f32>(n + 271.0)), u.x), u.y), u.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3(pp);
        pp *= 2.0;
        w *= 0.5;
    }
    return f;
}

// Custom mod function
fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// Primitives
fn sdCappedCone(p: vec3<f32>, h: f32, r1: f32, r2: f32) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(r2, h);
    let k2 = vec2<f32>(r2 - r1, 2.0 * h);
    let ca = vec2<f32>(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    let s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Global state
var<private> g_time: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_audio: f32;

// Map function with KIFS and organic distortion
fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;

    // Parameters from UI sliders
    let bloomComplexity = max(0.1, u.zoom_params.x); // x: Bloom Complexity
    let windSpeed = u.zoom_params.w;                // w: Cosmic Wind Speed

    // Mouse Interaction (Gravity Well)
    // The mouse acts as a localized gravity well, bending the petals slightly toward the cursor
    let mouseDist = length(pos.xy - g_mouse * 5.0);
    var bendFactor = 0.0;
    if (mouseDist < 5.0) {
        let pull = 1.0 - smoothstep(0.0, 5.0, mouseDist);
        bendFactor = pull * 0.5;
        let theta = pull * 1.5;
        let temp_xy = rot(theta) * pos.xy;
        pos.x = temp_xy.x;
        pos.y = temp_xy.y;
        pos.x -= g_mouse.x * pull * 1.5;
        pos.y -= g_mouse.y * pull * 1.5;
        pos.z -= pull * 1.5;
    }

    // Cosmic Wind Distortion
    // Domain-warped FBM noise creates organic swaying motion
    let windTime = g_time * windSpeed * 0.5;
    let fbm_warp = vec3<f32>(
        fbm(pos + vec3<f32>(windTime, 0.0, 0.0)),
        fbm(pos + vec3<f32>(0.0, windTime, 0.0)),
        fbm(pos + vec3<f32>(0.0, 0.0, windTime))
    ) * 2.0 - vec3<f32>(1.0);

    // Apply cosmic wind
    pos += fbm_warp * 0.3;

    // Audio-Reactive Blooming
    // The orchid's petals flare outward driven by audio frequencies (g_audio)
    let bloom = g_audio * 0.5;
    let scale = 1.0 + bloom;
    pos /= scale;

    // Refractive Petal KIFS
    // Procedurally generates endless overlapping crystalline petals
    var q = pos;
    var d_petal = 1000.0;

    // Starlight Core
    let d_core = length(pos) - 0.5;

    var s = 1.0;
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);

        // Kaleidoscopic folds
        q = abs(q) - vec3<f32>(0.5, 0.2, 0.3) * (bloomComplexity * 0.2 + 0.8);

        let t_rot_xz = rot(0.5 + g_time * 0.1 + bendFactor);
        let q_xz = t_rot_xz * q.xz;
        q.x = q_xz.x;
        q.z = q_xz.y;

        let t_rot_xy = rot(0.3 + bloom * 0.2);
        let q_xy = t_rot_xy * q.xy;
        q.x = q_xy.x;
        q.y = q_xy.y;

        q *= 1.5;
        s *= 1.5;

        // Capped Cone Petals
        let r1 = 0.01;
        let r2 = 0.1;
        let h = 0.5;
        let c_dist = sdCappedCone(q, h, r1, r2) / s;
        d_petal = min(d_petal, c_dist);

        // Capsule veins
        let v_dist = sdCapsule(q, vec3<f32>(0.0, -h, 0.0), vec3<f32>(0.0, h, 0.0), 0.02) / s;
        d_petal = min(d_petal, v_dist);
    }

    d_petal *= scale;
    let d_core_scaled = d_core * scale;

    // Material ID: 0 = Core, 1 = Petals
    var mat_id = 1.0;
    var final_d = d_petal;

    if (d_core_scaled < d_petal) {
        final_d = d_core_scaled;
        mat_id = 0.0;
    }

    // Subsurface scattering margin
    return vec2<f32>(final_d * 0.6, mat_id);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    // Finite difference approach
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Raymarching loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec4<f32> {
    var t = 0.0;
    var mat_id = -1.0;
    var core_glow = 0.0;
    var min_dist = 1000.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;

        min_dist = min(min_dist, d);

        if (res.y == 0.0) {
            core_glow += 0.05 / (0.01 + abs(d));
        }

        if (d < 0.001) {
            mat_id = res.y;
            break;
        }

        t += d;
        if (t > 25.0) {
            break;
        }
    }

    return vec4<f32>(t, mat_id, core_glow, min_dist);
}

// Main compute shader
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    g_time = u.config.x;
    g_audio = u.config.y * 0.1;

    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    g_mouse = vec2<f32>(mX, mY);

    // Setup camera
    var ro = vec3<f32>(0.0, 0.0, -8.0 + g_time * 0.2);
    // Orbit camera slightly
    ro.x += sin(g_time * 0.1) * 2.0;
    ro.y += cos(g_time * 0.15) * 1.5;

    let ta = vec3<f32>(0.0, 0.0, g_time * 0.2);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarch the scene
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat_id = res.y;
    let core_glow = res.z;
    let min_dist = res.w;

    // Background stars
    var starCol = vec3<f32>(0.0);
    let star_uv = uv + g_mouse * 0.05;
    for (var i = 1; i <= 3; i++) {
        let fi = f32(i);
        let s = hash31(vec3<f32>(floor(star_uv * 150.0 / fi), fi, 0.0));
        if (s > 0.99) { starCol += vec3<f32>(s) * (1.0 - fi * 0.2); }
    }

    var col = starCol * exp(-t * 0.05);

    let coreIntensity = max(0.0, u.zoom_params.z);   // z: Core Intensity
    let refractiveIndex = max(1.0, u.zoom_params.y); // y: Refractive Index

    if (mat_id >= 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        if (mat_id == 0.0) {
            // Core material
            col = vec3<f32>(1.0, 0.8, 0.4) * 2.0 * coreIntensity;
        } else if (mat_id == 1.0) {
            // Petal material - Chromatic Dispersion & Thin Film

            // Fresnel / thin film interference
            let ndotv = clamp(dot(n, v), 0.0, 1.0);
            let fresnel = pow(1.0 - ndotv, 3.0);

            // Iridescent colors (cyan, magenta, gold)
            let iridPhase = ndotv * 3.14159 * 2.0;
            let iridescence = 0.5 + 0.5 * cos(iridPhase + vec3<f32>(0.0, 2.0, 4.0));

            // Chromatic Dispersion Simulation (Thick Glass Approximation)
            let r_idx_r = refractiveIndex;
            let r_idx_g = refractiveIndex * 1.05;
            let r_idx_b = refractiveIndex * 1.1;

            // Fake internal reflections and dispersion
            let refl_r = reflect(rd, n * 0.9);
            let refl_g = reflect(rd, n * 1.0);
            let refl_b = reflect(rd, n * 1.1);

            // Add lighting based on reflections
            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let spec_r = pow(max(dot(refl_r, light_dir), 0.0), 16.0);
            let spec_g = pow(max(dot(refl_g, light_dir), 0.0), 16.0);
            let spec_b = pow(max(dot(refl_b, light_dir), 0.0), 16.0);

            let dispersion = vec3<f32>(spec_r, spec_g, spec_b);

            col = iridescence * fresnel + dispersion * 1.5;

            // Blend in some core illumination based on distance
            let dist_to_core = length(p);
            let core_illum = vec3<f32>(1.0, 0.6, 0.2) * (1.0 / (1.0 + dist_to_core * dist_to_core)) * coreIntensity;
            col += core_illum * 0.5;
        }
    }

    // Add glowing core based on audio (u.config.y)
    col += vec3<f32>(0.9, 0.4, 0.8) * core_glow * coreIntensity * 0.05 * (1.0 + g_audio * 2.0);

    // Outer glow for unhit rays that got close
    if (mat_id < 0.0) {
        col += vec3<f32>(0.2, 0.5, 1.0) * (0.01 / (0.001 + min_dist)) * (1.0 + g_audio);
    }

    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
