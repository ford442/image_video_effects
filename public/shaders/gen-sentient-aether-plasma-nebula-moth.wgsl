// ----------------------------------------------------------------
// Sentient Aether-Plasma Nebula-Moth
// Category: generative
// ----------------------------------------------------------------
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

fn sdCappedCone(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, ra: f32, rb: f32) -> f32 {
    let rba = rb - ra;
    let baba = dot(b - a, b - a);
    let papa = dot(p - a, p - a);
    let paba = dot(p - a, b - a) / baba;
    let x = sqrt(papa - paba * paba * baba);
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
    return s * sqrt(cbx * cbx + cby * cby * baba);
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
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

fn map(p_in: vec3<f32>) -> f32 {
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let audio = plasmaBuffer[0].x;

    // Parameters
    let flutter_freq = u.zoom_params.x;
    let storm_intensity = u.zoom_params.y;
    let plasma_glow = u.zoom_params.z;
    let rift_dist = u.zoom_params.w;

    var p = p_in;
    // Mouse interaction - slightly offset the world
    p = p - vec3<f32>(mouse.x * 2.0 - 1.0, -(mouse.y * 2.0 - 1.0), 0.0);

    // Base animation
    let t = time * flutter_freq;

    // Thorax / Body
    var body = sdEllipsoid(p, vec3<f32>(0.3, 0.2 + audio * 0.1, 1.0));

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
    let flap_angle = sin(t * 15.0) * 0.8 * (1.0 + audio);
    let flap_rot = rot2d(flap_angle);
    var wp_xy = vec2<f32>(wp.x, wp.y);
    let tmp3 = flap_rot * wp_xy;
    wp.x = tmp3.x;
    wp.y = tmp3.y;

    // Wing shape - using a thin ellipsoid with noise distortion
    let wing_base = sdEllipsoid(wp - vec3<f32>(1.2, 0.0, 0.0), vec3<f32>(1.5, 0.02, 1.0));

    // Add fbm distortion for the plasma wing effect
    let distortion = fbm(wp * 3.0 - vec3<f32>(0.0, 0.0, time * 2.0)) * 0.2 * plasma_glow;
    let wing = wing_base + distortion;

    // Time Rift Distortion (modifies the space around the moth)
    let rift = sin(p.x * 2.0 + t) * sin(p.y * 2.0 - t) * sin(p.z * 2.0) * rift_dist;

    let final_body = body + rift;
    let final_wing = wing + rift;

    g_body_dist = final_body;
    g_wing_dist = final_wing;

    // Accumulate glow
    g_glow = g_glow + 0.01 / (0.01 + abs(final_wing)) * plasma_glow;
    g_glow = g_glow + 0.02 / (0.01 + abs(final_body)) * (audio * 2.0);

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
    let audio = plasmaBuffer[0].x;

    // Background particle storm
    let storm_intensity = u.zoom_params.y;
    var storm = 0.0;
    var sp = ro;
    var st = 0.0;
    for(var j = 0; j < 15; j++) {
        sp = ro + rd * st;
        let sv = fbm(sp * 2.0 + vec3<f32>(0.0, 0.0, time * 3.0));
        storm = storm + (sv * sv) * 0.05 * storm_intensity;
        st = st + 1.0;
    }
    col = col + vec3<f32>(0.1, 0.2, 0.3) * storm * (1.0 + audio);

    if (hit) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let ao = clamp(map(p + n * 0.1) * 10.0, 0.0, 1.0);

        var matCol = vec3<f32>(0.0);
        if (g_body_dist < g_wing_dist) {
            // Thorax / body
            matCol = vec3<f32>(0.1, 0.8, 0.9); // Bioluminescent cyan
            let sub = max(0.0, map(p + l * 0.2)) * 2.0; // fake subsurface
            matCol = matCol * (diff + 0.2 + sub * audio);
        } else {
            // Wings
            matCol = vec3<f32>(0.6, 0.2, 0.9); // Quantum purple
            matCol = matCol * (diff + 0.5); // more emissive
        }

        col = matCol * ao;
    }

    // Add volumetric glow
    let glowCol = vec3<f32>(0.2, 0.9, 0.7) * (g_glow * 0.02); // Auroral greens
    col = col + glowCol;

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
