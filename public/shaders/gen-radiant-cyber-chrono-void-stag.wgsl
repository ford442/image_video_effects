// ----------------------------------------------------------------
// Radiant Cyber-Chrono Void-Stag
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Stag Scale, y=Antler Complexity, z=Nebula Density, w=Core Pulse Intensity
    ripples: array<vec4<f32>, 50>,
};

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

// ----------------------------------------------------------------
// Parameters (for UI sliders)
// ----------------------------------------------------------------
// Name (default, min, max, step)
// Stag Scale (1.0, 0.5, 2.0, 0.1)
// Antler Complexity (3.0, 1.0, 5.0, 0.1)
// Nebula Density (0.5, 0.1, 1.0, 0.05)
// Core Pulse Intensity (1.0, 0.0, 5.0, 0.1)

const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;
const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    return mix(mix(mix(dot(hash33(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash33(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), f2.x),
                   mix(dot(hash33(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash33(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
               mix(mix(dot(hash33(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash33(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), f2.x),
                   mix(dot(hash33(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash33(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y), f2.z);
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var v = 0.0;
    var a = 0.5;
    for (var i = 0; i < 5; i++) {
        v += a * noise3(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

struct MapResult {
    d: f32,
    mat: i32,  // 0=bg, 1=body, 2=antlers, 3=core, 4=hoof_trails
    glow: vec3<f32>,
}

fn map(pos_in: vec3<f32>) -> MapResult {
    var res = MapResult(MAX_DIST, 0, vec3<f32>(0.0));
    var p = pos_in;
    let time = u.config.x;
    let audio = u.config.y;

    // Scale from params
    let scale = u.zoom_params.x;
    p /= scale;

    // Global transform via mouse
    let mx = (u.zoom_config.y / u.config.z - 0.5) * 6.0;
    let my = (u.zoom_config.z / u.config.w - 0.5) * 6.0;
    let p_xz_tmp = rot(-mx) * p.xz;
p.x = p_xz_tmp.x;
p.z = p_xz_tmp.y;
    let p_yz_tmp = rot(-my) * p.yz;
p.y = p_yz_tmp.x;
p.z = p_yz_tmp.y;

    // Add leaping motion
    p.y += sin(time * 2.0) * 0.5;
    p.z += cos(time * 2.0) * 0.2;

    let anim_rot_x = sin(time * 2.0) * 0.1;
    let anim_yz_tmp = rot(anim_rot_x) * p.yz;
p.y = anim_yz_tmp.x;
p.z = anim_yz_tmp.y;

    // --- Body (Cyber-Stag Exoskeleton) ---
    var body_d = MAX_DIST;

    // Torso
    let torso_r = vec3<f32>(0.6, 0.7, 1.5);
    var p_torso = p - vec3<f32>(0.0, 0.0, 0.0);
    let torso_dist = sdEllipsoid(p_torso, torso_r);
    body_d = smin(body_d, torso_dist, 0.3);

    // Neck
    let neck_p0 = vec3<f32>(0.0, 0.3, 1.2);
    let neck_p1 = vec3<f32>(0.0, 1.2, 1.8);
    let neck_dist = sdCapsule(p, neck_p0, neck_p1, 0.3);
    body_d = smin(body_d, neck_dist, 0.2);

    // Head
    var p_head = p - vec3<f32>(0.0, 1.4, 2.0);
    let phead_yz_tmp = rot(-0.3) * p_head.yz;
p_head.y = phead_yz_tmp.x;
p_head.z = phead_yz_tmp.y;
    let head_dist = sdEllipsoid(p_head, vec3<f32>(0.25, 0.25, 0.5));
    body_d = smin(body_d, head_dist, 0.1);

    // Legs (simplified leaping posture)
    let leg_r = 0.15;
    // Front legs
    let fl_p0 = vec3<f32>(0.4, -0.2, 1.0);
    let fl_p1 = vec3<f32>(0.3, -1.5, 1.5 + sin(time*2.0)*0.5);
    let fl_dist = sdCapsule(abs(p) - vec3<f32>(0.4, 0.0, 0.0), fl_p0 - vec3<f32>(0.4, 0.0, 0.0), fl_p1 - vec3<f32>(0.4, 0.0, 0.0), leg_r);
    body_d = smin(body_d, fl_dist, 0.2);

    // Back legs
    let bl_p0 = vec3<f32>(0.4, -0.2, -1.0);
    let bl_p1 = vec3<f32>(0.3, -1.5, -1.8 - sin(time*2.0)*0.5);
    let bl_dist = sdCapsule(abs(p) - vec3<f32>(0.4, 0.0, 0.0), bl_p0 - vec3<f32>(0.4, 0.0, 0.0), bl_p1 - vec3<f32>(0.4, 0.0, 0.0), leg_r);
    body_d = smin(body_d, bl_dist, 0.2);

    // Add biomechanical noise displacement to body
    let body_noise = noise3(p * 5.0 + time) * 0.05;
    body_d += body_noise;

    if (body_d < res.d) {
        res.d = body_d;
        res.mat = 1;
    }

    // --- Antlers (Crystal-Tension) ---
    var p_antler = p - vec3<f32>(0.0, 1.6, 1.8); // Base of antlers
    p_antler.x = abs(p_antler.x) - 0.2; // Symmetry
    let p_antler_yz_tmp = rot(0.2) * p_antler.yz;
p_antler.y = p_antler_yz_tmp.x;
p_antler.z = p_antler_yz_tmp.y;
    let p_antler_xy_tmp = rot(-0.3) * p_antler.xy;
p_antler.x = p_antler_xy_tmp.x;
p_antler.y = p_antler_xy_tmp.y;

    var antler_d = MAX_DIST;
    let complexity = i32(u.zoom_params.y);
    var branch_p = p_antler;
    var branch_r = 0.08;
    var branch_len = 0.6;

    // Evaluate main antler structure using multi-domain twist
    for (var i = 0; i < 4; i++) {
        if (i > complexity) { break; }
        let segment_d = sdCapsule(branch_p, vec3<f32>(0.0), vec3<f32>(0.0, branch_len, 0.0), branch_r);
        antler_d = smin(antler_d, segment_d, 0.05);

        branch_p.y -= branch_len;
        let branch_xy_tmp = rot(0.4 + sin(time)*0.1) * branch_p.xy;
branch_p.x = branch_xy_tmp.x;
branch_p.y = branch_xy_tmp.y;
        let branch_yz_tmp = rot(0.2) * branch_p.yz;
branch_p.y = branch_yz_tmp.x;
branch_p.z = branch_yz_tmp.y;

        branch_r *= 0.7;
        branch_len *= 0.8;
    }
    // Crystal distortion
    let crystal_disp = sin(p_antler.x * 20.0) * sin(p_antler.y * 20.0) * sin(p_antler.z * 20.0) * 0.02;
    antler_d += crystal_disp;

    if (antler_d < res.d) {
        res.d = antler_d;
        res.mat = 2;
    }

    // --- Acoustic Resonance Core (Heart) ---
    var p_core = p - vec3<f32>(0.0, 0.2, 0.5);
    let pulse = u.zoom_params.w * (1.0 + audio * 2.0 + sin(time * 10.0) * 0.2);
    p_core /= (1.0 + pulse * 0.1);
    var core_d = sdEllipsoid(p_core, vec3<f32>(0.2, 0.25, 0.3));
    let core_noise = fbm(p_core * 10.0 - time * 2.0) * 0.05;
    core_d += core_noise;
    core_d *= (1.0 + pulse * 0.1);

    if (core_d < res.d) {
        res.d = core_d;
        res.mat = 3;
        res.glow = vec3<f32>(0.0, 0.8, 1.0) * pulse * 2.0 * max(0.0, 0.1 - core_d);
    }

    // --- Hoof Aether Trails ---
    // Distance field for trails coming off hooves
    var trail_d = MAX_DIST;
    let trail_p0 = fl_p1 - vec3<f32>(0.4, 0.0, 0.0);
    let trail_p1 = bl_p1 - vec3<f32>(0.4, 0.0, 0.0);

    // Check trails symmetrically
    var p_trail = p;
    p_trail.x = abs(p_trail.x);

    let trail_len = 3.0;
    // Front trails
    var dist_to_fl = sdCapsule(p_trail, trail_p0, trail_p0 - vec3<f32>(0.0, 0.0, trail_len), 0.1);
    // Back trails
    var dist_to_bl = sdCapsule(p_trail, trail_p1, trail_p1 - vec3<f32>(0.0, 0.0, trail_len), 0.1);

    trail_d = smin(dist_to_fl, dist_to_bl, 0.2);

    // Add flow noise
    let flow_noise = noise3(p_trail * 3.0 - vec3<f32>(0.0, 0.0, time * 5.0)) * 0.1;
    trail_d += flow_noise;
    // Fade trail over distance
    let trail_fade = clamp((-p_trail.z + trail_p0.z) / trail_len, 0.0, 1.0);
    trail_d += trail_fade * 0.2; // Expand radius over distance roughly

    if (trail_d < res.d) {
        res.d = trail_d;
        res.mat = 4;
    }

    res.d *= scale; // Scale back the distance
    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    ));
}

fn rayMarch(ro: vec3<f32>, rd: vec3<f32>) -> MapResult {
    var dO = 0.0;
    var res = MapResult(MAX_DIST, 0, vec3<f32>(0.0));
    var total_glow = vec3<f32>(0.0);

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let map_res = map(p);
        total_glow += map_res.glow;

        if (abs(map_res.d) < SURF_DIST) {
            res = map_res;
            res.d = dO;
            res.glow = total_glow;
            return res;
        }
        if (dO > MAX_DIST) {
            break;
        }
        dO += map_res.d;
    }
    res.d = dO;
    res.glow = total_glow;
    return res;
}

// Volumetric Nebula Background
fn getNebula(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var density = 0.0;
    var col = vec3<f32>(0.0);
    var t = 0.0;
    let step_size = 0.5;
    let nebula_density_factor = u.zoom_params.z;

    for (var i = 0; i < 20; i++) {
        let p = ro + rd * t;
        let d = fbm(p * 0.5 + u.config.x * 0.2);
        if (d > 0.4) {
            let local_density = (d - 0.4) * nebula_density_factor;
            density += local_density;
            let star_glow = pow(noise3(p * 10.0), 10.0) * 5.0; // Stardust
            col += mix(vec3<f32>(0.1, 0.0, 0.2), vec3<f32>(0.8, 0.2, 0.6), d) * local_density + star_glow * vec3<f32>(1.0, 0.9, 0.5) * local_density;
        }
        t += step_size;
        if (density > 1.0) { break; }
    }
    return col;
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resX = u.config.z;
    let resY = u.config.w;

    if (f32(id.x) >= resX || f32(id.y) >= resY) {
        return;
    }

    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * vec2<f32>(resX, resY)) / resY;

    var ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    let map_res = rayMarch(ro, rd);
    var col = vec3<f32>(0.0);

    if (map_res.d < MAX_DIST) {
        let p = ro + rd * map_res.d;
        let n = calcNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);

        if (map_res.mat == 1) { // Body
            let baseColor = vec3<f32>(0.05, 0.05, 0.08); // Dark metallic
            col = baseColor * diff + vec3<f32>(0.8, 0.9, 1.0) * spec + vec3<f32>(0.2, 0.1, 0.3) * fresnel;
        } else if (map_res.mat == 2) { // Antlers (Crystal)
            // Faux Refraction
            let refr_rd = refract(rd, n, 0.8);
            let refr_col = getNebula(p, refr_rd);
            let baseColor = vec3<f32>(0.8, 0.9, 1.0); // Icy blue/white
            col = mix(refr_col, baseColor, 0.3) + spec * 2.0 + fresnel * vec3<f32>(0.5, 0.8, 1.0);

            // Audio reactive glow based on interaction/ripples
            var glow_intensity = u.config.y; // audio
            // Add click interaction
            for (var i = 0u; i < 10u; i++) {
                let ripple = u.ripples[i];
                if (ripple.w > 0.0) {
                   let r_uv = (ripple.xy - 0.5 * vec2<f32>(resX, resY)) / resY;
                   let r_rd = normalize(vec3<f32>(r_uv.x, r_uv.y, 1.0));
                   // rough collision
                   let dist_to_ripple = length(cross(r_rd, p - ro));
                   if (dist_to_ripple < 1.0) {
                       glow_intensity += ripple.z * 5.0 * (1.0 - dist_to_ripple);
                   }
                }
            }
            col += vec3<f32>(0.0, 0.8, 1.0) * glow_intensity * 0.5;

        } else if (map_res.mat == 3) { // Core
            col = vec3<f32>(0.0, 0.8, 1.0) * 2.0; // Neon Cyan
        } else if (map_res.mat == 4) { // Trails
            col = vec3<f32>(1.0, 0.0, 0.5) * 1.5; // Neon Magenta/Gold
            col *= (1.0 - fresnel); // Soften edges
        }
    } else {
        col = getNebula(ro, rd);
    }

    // Add accumulated glow from raymarching
    col += map_res.glow * 0.05;

    // Tone mapping
    col = col / (1.0 + col);
    // Gamma correction
    col = pow(col, vec3<f32>(1.0/2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
