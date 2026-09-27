// ═══════════════════════════════════════════════════════════════════
//  Sentient Aether-Plasma Nebula-Moth
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: thorax-rooted plasma venation; flap-reversal ion-scale wake
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

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.005;
const MAX_DIST: f32 = 40.0;

fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let rr = max(r, vec3<f32>(0.001));
    let k0 = length(p / rr);
    let k1 = max(length(p / (rr * rr)), 0.001);
    return k0 * (k0 - 1.0) / k1;
}

fn sdCappedCone(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, ra: f32, rb: f32) -> f32 {
    let rba = rb - ra;
    let baba = max(dot(b - a, b - a), 1e-6);
    let papa = dot(p - a, p - a);
    let paba = dot(p - a, b - a) / baba;
    let x = sqrt(max(papa - paba * paba * baba, 0.0));
    let cax = max(0.0, x - mix(ra, rb, paba));
    let cay = abs(paba - 0.5) - 0.5;
    let k = rba * rba + baba;
    let f = clamp((rba * (x - ra) + paba * baba) / k, 0.0, 1.0);
    let cbx = x - ra - f * rba;
    let cby = paba - f;
    let s = select(1.0, -1.0, cbx < 0.0 && cay < 0.0);
    if(paba < 0.0 || paba > 1.0) {
        return s * sqrt(min(cax * cax + cay * cay * baba, cbx * cbx + cby * cby * baba));
    }
    return s * sqrt(max(cbx * cbx + cby * cby * baba, 0.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Thorax-rooted plasma venation in wing-local space (origin at thorax, +x toward tip)
fn wingVeinDistance(wp: vec3<f32>) -> f32 {
    let local = wp - vec3<f32>(1.2, 0.0, 0.0);
    let span = clamp((local.x + 1.5) / 3.0, 0.0, 1.0);
    let primary = abs(local.z) - 0.02 * span;
    let branchA = abs(local.z - 0.35 * span * span) - 0.012;
    let branchB = abs(local.z + 0.28 * span * span) - 0.010;
    let vein = min(abs(primary), min(abs(branchA), abs(branchB)));
    return vein + abs(local.y) * 0.4;
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p2 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p2 = p2 + dot(p2, p2.yxz + 33.33);
    return fract((p2.xxy + p2.yxx) * p2.zyx);
}

fn noise31(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pp = p;
    for(var i = 0; i < 4; i++) {
        f = f + amp * noise31(pp);
        amp = amp * 0.5;
        pp = pp * 2.0;
    }
    return f;
}

// Global variables for material tracking
var<private> g_glow: f32 = 0.0;
var<private> g_wing_dist: f32 = 0.0;
var<private> g_body_dist: f32 = 0.0;
var<private> g_vein_dist: f32 = 1.0;

fn map(p_in: vec3<f32>) -> f32 {
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Parameters
    let flutter_freq = u.zoom_params.x;
    let plasma_glow = u.zoom_params.z;
    let rift_dist = u.zoom_params.w;

    var p = p_in;
    // Mouse interaction - slightly offset the world
    p = p - vec3<f32>(mouse.x * 2.0 - 1.0, -(mouse.y * 2.0 - 1.0), 0.0);

    // Base animation
    let t = time * flutter_freq;

    // Thorax / Body
    var body = sdEllipsoid(p, vec3<f32>(0.3, 0.2 + bass * 0.1, 1.0));

    // Antennae
    var ap = p;
    ap.x = abs(ap.x);
    let rot = rot2d(0.5 + sin(t) * 0.1);
    var ap_yz = vec2<f32>(ap.y, ap.z);
    let tmp1 = rot * ap_yz;
    ap.y = tmp1.x;
    ap.z = tmp1.y;
    var ap_xz = vec2<f32>(ap.x, ap.z);
    let tmp2 = rot2d(0.3) * ap_xz;
    ap.x = tmp2.x;
    ap.z = tmp2.y;
    let antenna = sdCappedCone(ap, vec3<f32>(0.2, 0.1, 0.8), vec3<f32>(0.5, 0.5, 1.8), 0.05, 0.01);
    body = smin(body, antenna, 0.1);

    // Wings
    var wp = p;
    wp.x = abs(wp.x);
    // Flapping motion
    let flap_angle = sin(t * 15.0) * 0.8 * (1.0 + bass);
    let flap_rot = rot2d(flap_angle);
    var wp_xy = vec2<f32>(wp.x, wp.y);
    let tmp3 = flap_rot * wp_xy;
    wp.x = tmp3.x;
    wp.y = tmp3.y;

    // Wing shape - using a thin ellipsoid with noise distortion
    let wing_base = sdEllipsoid(wp - vec3<f32>(1.2, 0.0, 0.0), vec3<f32>(1.5, 0.02, 1.0));

    // Add fbm distortion for the plasma wing effect
    let distortion = fbm(wp * 3.0 - vec3<f32>(0.0, 0.0, time * 2.0)) * 0.2 * plasma_glow;
    var wing = wing_base + distortion;

    // Thorax-rooted plasma venation: shallow ridges along the wing surface
    let vein = wingVeinDistance(wp);
    g_vein_dist = vein;
    wing = wing - exp(-vein * 28.0) * 0.018 * plasma_glow;

    // Time Rift Distortion (modifies the space around the moth)
    let rift = sin(p.x * 2.0 + t) * sin(p.y * 2.0 - t) * sin(p.z * 2.0) * rift_dist;

    let final_body = body + rift;
    let final_wing = wing + rift;

    g_body_dist = final_body;
    g_wing_dist = final_wing;

    // Accumulate glow
    g_glow = g_glow + 0.01 / (0.01 + abs(final_wing)) * plasma_glow;
    g_glow = g_glow + 0.02 / (0.01 + abs(final_body)) * (bass * 2.0);
    g_glow = g_glow + 0.008 / (0.008 + vein) * plasma_glow * (0.6 + mids);

    return min(final_body, final_wing);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);
    if (global_id.x >= dims.x || global_id.y >= dims.y) {
        return;
    }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, -6.0);
    // Mouse orbit
    let mouse = u.zoom_config.yz;
    let mx = (mouse.x * 2.0 - 1.0) * 3.14;
    let my = -(mouse.y * 2.0 - 1.0) * 1.5;

    var ro_yz = vec2<f32>(ro.y, ro.z);
    let tmp4 = rot2d(my) * ro_yz;
    ro.y = tmp4.x;
    ro.z = tmp4.y;
    var ro_xz = vec2<f32>(ro.x, ro.z);
    let tmp5 = rot2d(mx) * ro_xz;
    ro.x = tmp5.x;
    ro.z = tmp5.y;

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cp = vec3<f32>(0.0, 1.0, 0.0);
    let cu = normalize(cross(cw, cp));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t_dist = 0.0;
    var p = ro;
    var hit = false;

    g_glow = 0.0;
    g_vein_dist = 1.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t_dist;
        let d = map(p);
        if (d < SURF_DIST) {
            hit = true;
            break;
        }
        if (t_dist > MAX_DIST) {
            break;
        }
        t_dist = t_dist + d * 0.7; // slight under-relaxation for fbm
    }

    var col = vec3<f32>(0.0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Background particle storm
    let storm_intensity = u.zoom_params.y;
    let flutter_freq = u.zoom_params.x;
    var storm = 0.0;
    var wake = 0.0;
    var sp = ro;
    var st = 0.0;
    // Flap-reversal gate: ion-scale filaments at wing-tip extrema
    let flapPhase = time * flutter_freq * 15.0;
    let reversal = pow(clamp(abs(cos(flapPhase)), 0.0, 1.0), 8.0);
    let flapSign = sign(sin(flapPhase) + 1e-4);
    for(var j = 0; j < 15; j++) {
        sp = ro + rd * st;
        let sv = fbm(sp * 2.0 + vec3<f32>(0.0, 0.0, time * 3.0));
        storm = storm + (sv * sv) * 0.05 * storm_intensity;
        // Analytic wing-tip wake filaments (world-space, no extra SDF)
        let tipY = flapSign * 1.1;
        let tipL = vec3<f32>(-2.4, tipY, 0.15);
        let tipR = vec3<f32>( 2.4, tipY, 0.15);
        let trail = vec3<f32>(0.0, -flapSign * 0.4, -0.8);
        let uL = clamp(dot(sp - tipL, trail) / 1.2, 0.0, 1.0);
        let uR = clamp(dot(sp - tipR, trail) / 1.2, 0.0, 1.0);
        let dL = length(sp - (tipL + trail * uL));
        let dR = length(sp - (tipR + trail * uR));
        wake = wake + exp(-min(dL, dR) * 9.0) * reversal * storm_intensity * 0.08;
        st = st + 1.0;
    }
    col = col + vec3<f32>(0.1, 0.2, 0.3) * storm * (1.0 + bass);
    col = col + vec3<f32>(0.35, 0.85, 1.0) * wake * (0.7 + treble);

    if (hit) {
        let n = calcNormal(p);
        let ao = clamp(map(p + n * 0.1) * 10.0, 0.0, 1.0);
        let hitD = map(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);

        var matCol = vec3<f32>(0.0);
        if (g_body_dist < g_wing_dist) {
            // Thorax / body
            matCol = vec3<f32>(0.1, 0.8, 0.9); // Bioluminescent cyan
            let sub = max(0.0, map(p + l * 0.2)) * 2.0; // fake subsurface
            matCol = matCol * (diff + 0.2 + sub * bass);
        } else {
            // Wings
            matCol = vec3<f32>(0.6, 0.2, 0.9); // Quantum purple
            matCol = matCol * (diff + 0.5); // more emissive
            let veinMask = exp(-g_vein_dist * 22.0);
            matCol += vec3<f32>(0.25, 0.95, 0.85) * veinMask * u.zoom_params.z;
            matCol += vec3<f32>(0.55, 0.2, 0.95) * veinMask * mids * 0.4;
        }

        col = matCol * ao * (1.0 + clamp(-hitD, 0.0, 0.05) * 0.2);
    }

    // Add volumetric glow
    let glowCol = vec3<f32>(0.2, 0.9, 0.7) * (g_glow * 0.02); // Auroral greens
    col = col + glowCol;

    col = acesToneMap(col * 1.1);
    let hitAlpha = select(0.12, 0.55, hit);
    let alpha = clamp(hitAlpha + g_glow * 0.04 + storm * 0.2 + wake * 0.5, 0.08, 0.96);
    let depth = select(0.0, clamp(1.0 - t_dist / MAX_DIST, 0.0, 1.0), hit);
    let outCol = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
