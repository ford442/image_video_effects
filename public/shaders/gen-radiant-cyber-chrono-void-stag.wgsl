// ----------------------------------------------------------------
// Radiant Cyber-Chrono Void-Stag
// Category: generative
// ----------------------------------------------------------------

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

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// 3D Noise (simplex-like)
fn hash(p: vec3<f32>) -> vec3<f32> {
    var p2 = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                       dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                       dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(p2) * 43758.5453123) * 2.0 - vec3<f32>(1.0);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Antler L-System like branching
fn sdAntlerBranch(p: vec3<f32>, depth: f32, complexity: f32) -> f32 {
    var d = 1e10;
    var current_p = p;
    var scale = 1.0;
    for(var i = 0; i < 4; i++) {
        if (f32(i) > complexity) { break; }
        let l = 0.5 * scale;
        let r = 0.05 * scale;
        d = min(d, sdCapsule(current_p, vec3<f32>(0.0), vec3<f32>(0.0, l, 0.0), r));
        current_p.y -= l;
        current_p.x = abs(current_p.x) - 0.2 * scale;
        current_p.xy = rot(0.5) * current_p.xy;
        current_p.yz = rot(0.3) * current_p.yz;
        scale *= 0.7;
    }
    return d;
}

fn map(p: vec3<f32>, time: f32, scale: f32, complexity: f32, pulse: f32) -> vec2<f32> {
    var p_scaled = p / scale;

    // Body (Ellipsoid + Capsules)
    var body_d = sdEllipsoid(p_scaled - vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.5, 0.6, 1.2));

    // Neck and Head
    let neck_d = sdCapsule(p_scaled, vec3<f32>(0.0, 0.3, 0.8), vec3<f32>(0.0, 1.2, 1.5), 0.2);
    let head_d = sdEllipsoid(p_scaled - vec3<f32>(0.0, 1.3, 1.6), vec3<f32>(0.15, 0.2, 0.3));
    body_d = smin(body_d, smin(neck_d, head_d, 0.2), 0.3);

    // Legs (simplified bounds)
    var legs_d = 1e10;
    let leg_offsets = array<vec3<f32>, 4>(
        vec3<f32>( 0.3, -0.2,  0.8),
        vec3<f32>(-0.3, -0.2,  0.8),
        vec3<f32>( 0.3, -0.2, -0.8),
        vec3<f32>(-0.3, -0.2, -0.8)
    );
    for(var i=0; i<4; i++) {
        let cycle = time * 2.0 + f32(i) * PI / 2.0;
        let p_leg = p_scaled - leg_offsets[i] - vec3<f32>(0.0, sin(cycle)*0.2, cos(cycle)*0.2);
        let upper_leg = sdCapsule(p_leg, vec3<f32>(0.0), vec3<f32>(0.0, -0.6, 0.0), 0.15);
        let lower_leg = sdCapsule(p_leg, vec3<f32>(0.0, -0.6, 0.0), vec3<f32>(0.0, -1.2, 0.1*sin(cycle)), 0.1);
        legs_d = smin(legs_d, smin(upper_leg, lower_leg, 0.1), 0.2);
    }
    body_d = smin(body_d, legs_d, 0.2);

    // Antlers
    var antler_p = p_scaled - vec3<f32>(0.0, 1.5, 1.6);
    antler_p.x = abs(antler_p.x) - 0.1;
    antler_p.xy = rot(-0.3) * antler_p.xy;
    let antler_d = sdAntlerBranch(antler_p, 4.0, complexity);

    // Heart Core
    let heart_p = p_scaled - vec3<f32>(0.0, 0.0, 0.5);
    let heart_pulse = 1.0 + 0.2 * sin(time * 5.0) * pulse;
    let heart_d = sdEllipsoid(heart_p, vec3<f32>(0.2, 0.2, 0.2) * heart_pulse);

    var d = min(body_d, antler_d);
    d = min(d, heart_d);

    var mat_id = 0.0; // Body
    if (antler_d < body_d && antler_d < heart_d) { mat_id = 1.0; } // Antlers
    if (heart_d < body_d && heart_d < antler_d) { mat_id = 2.0; } // Heart

    return vec2<f32>(d * scale, mat_id);
}

fn calcNormal(p: vec3<f32>, time: f32, scale: f32, complexity: f32, pulse: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, scale, complexity, pulse).x;
    let nx = map(p + e.xyy, time, scale, complexity, pulse).x - d;
    let ny = map(p + e.yxy, time, scale, complexity, pulse).x - d;
    let nz = map(p + e.yyx, time, scale, complexity, pulse).x - d;
    return normalize(vec3<f32>(nx, ny, nz));
}

fn gyroid(p: vec3<f32>) -> f32 {
    return dot(sin(p), cos(p.zxy));
}

fn fbm_volumetric(p: vec3<f32>, time: f32) -> f32 {
    var q = p;
    var d = 0.0;
    var w = 0.5;
    for(var i=0; i<4; i++) {
        d += w * (gyroid(q + time * 0.1) * 0.5 + 0.5);
        q *= 2.0;
        w *= 0.5;
    }
    return d;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio = u.config.y; // Or pulse intensity mapping

    // Parameters
    let stagScale = u.zoom_params.x;
    let antlerComplexity = u.zoom_params.y;
    let nebulaDensity = u.zoom_params.z;
    let corePulse = u.zoom_params.w + audio;

    // Mouse Interaction (Orbit viewing matrix)
    var m = u.zoom_config.yz;
    if (length(m) < 0.01) { m = vec2<f32>(0.0); }

    var ro = vec3<f32>(0.0, 1.0, -4.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse orbit
    let mx = m.x * PI * 2.0;
    let my = (m.y - 0.5) * PI;

    ro.yz = rot(my) * ro.yz;
    rd.yz = rot(my) * rd.yz;
    ro.xz = rot(mx) * ro.xz;
    rd.xz = rot(mx) * rd.xz;

    // Raymarching Variables
    var t = 0.0;
    var mat_id = -1.0;
    var p = ro;

    for(var i=0; i<100; i++) {
        p = ro + rd * t;
        let d = map(p, time, stagScale, antlerComplexity, corePulse);
        if (d.x < 0.001) {
            mat_id = d.y;
            break;
        }
        t += d.x * 0.8;
        if (t > 20.0) { break; }
    }

    var col = vec3<f32>(0.0);

    // Background Volumetric Nebula
    var nebula = 0.0;
    var bg_t = 0.0;
    for(var i=0; i<30; i++) {
        let bg_p = ro + rd * bg_t;
        let den = fbm_volumetric(bg_p * 0.5, time);
        nebula += max(0.0, den - 0.5) * nebulaDensity * 0.1;
        bg_t += 0.5;
    }
    let nebulaColor = vec3<f32>(0.1, 0.5, 0.8) * nebula;
    col += nebulaColor;

    if (mat_id >= 0.0) {
        let n = calcNormal(p, time, stagScale, antlerComplexity, corePulse);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let r_vec = reflect(-l, n);
        let spec = pow(max(dot(view, r_vec), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, view), 0.0), 4.0);

        if (mat_id == 0.0) {
            // Body: Metallic Exoskeleton
            let baseColor = vec3<f32>(0.2, 0.2, 0.25);
            col = baseColor * diff + vec3<f32>(0.5, 0.8, 1.0) * spec + vec3<f32>(0.1, 0.3, 0.5) * fresnel;
        } else if (mat_id == 1.0) {
            // Antlers: Refractive Crystal
            let refract_rd = refract(rd, n, 0.9);
            // Fake refraction by slightly offsetting nebula lookups
            let refr_color = vec3<f32>(0.2, 0.9, 0.8) * (1.0 + audio * 0.5);
            col = refr_color * diff * 0.5 + refr_color * fresnel * 2.0;
        } else if (mat_id == 2.0) {
            // Heart Core
            col = vec3<f32>(1.0, 0.2, 0.8) * corePulse * 2.0;
        }

        // Hoof Aether Trails
        if (p.y < -1.0) {
            let trail = smoothstep(-1.0, -2.0, p.y) * sin(p.z * 10.0 - time * 5.0) * 0.5 + 0.5;
            col += vec3<f32>(0.0, 1.0, 0.8) * trail * 2.0 * max(0.0, 1.0 - length(p.xz - vec2<f32>(0.3, 0.8))); // simplistic trail bounds
        }
    }

    // Interactive Ripples (Mouse Clicks)
    for (var i = 0u; i < 50u; i = i + 1u) {
        let ripple = u.ripples[i];
        if (ripple.w > 0.0) {
            let ripple_pos = vec2<f32>(ripple.x, ripple.y) * res;
            let d_ripple = distance(vec2<f32>(global_id.xy), ripple_pos) / res.y;
            let ripple_time = time - ripple.z;
            let wave = sin(d_ripple * 40.0 - ripple_time * 10.0) * exp(-d_ripple * 5.0 - ripple_time * 2.0);
            col += vec3<f32>(0.2, 1.0, 0.5) * max(0.0, wave) * ripple.w * 0.5;
        }
    }

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}
