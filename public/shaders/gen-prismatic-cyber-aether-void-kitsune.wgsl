// ----------------------------------------------------------------
// Prismatic Cyber-Aether Void-Kitsune
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tail Dispersion, y=Current Warp, z=Storm Density, w=Rune Glow
    ripples: array<vec4<f32>, 50>,
};

const PI = 3.14159265359;

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Simplex Noise for volumetric environment
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

fn simplex_noise3d(p: vec3<f32>) -> f32 {
    let i = floor(p + dot(p, vec3<f32>(1.0 / 3.0)));
    let x0 = p - i + dot(i, vec3<f32>(1.0 / 6.0));
    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);
    let x1 = x0 - i1 + vec3<f32>(1.0 / 6.0);
    let x2 = x0 - i2 + vec3<f32>(1.0 / 3.0);
    let x3 = x0 - 1.0 + vec3<f32>(0.5);
    let i_hash = vec4<f32>(0.0);
    var n = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    n = n * n * n * n;
    let d0 = dot(hash3(i), x0);
    let d1 = dot(hash3(i + i1), x1);
    let d2 = dot(hash3(i + i2), x2);
    let d3 = dot(hash3(i + 1.0), x3);
    return 27.5 * dot(n, vec4<f32>(d0, d1, d2, d3));
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = p;
    for(var i = 0; i < 4; i++) {
        f += amp * simplex_noise3d(freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn smooth_min(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Distance, Material ID, Glow Intensity
fn map(p: vec3<f32>) -> vec3<f32> {
    var p_warp = p;
    // Mouse current warp
    let mouse = u.zoom_config.yz; // [-1, 1] normalized space
    let dist = length(p_warp.xy - vec2<f32>(mouse.x * 3.0, -mouse.y * 3.0));
    let warp_factor = u.zoom_params.y / (1.0 + dist * dist * 5.0); // u.zoom_params.y is Current Warp
    p_warp -= vec3<f32>(mouse.x * 2.0, -mouse.y * 2.0, 0.0) * warp_factor;

    let t = u.config.x;
    let bass = plasmaBuffer[0].x;
    let tail_disp = u.zoom_params.x; // Tail Dispersion

    // 1. Cybernetic Kitsune Body (Mechanical/Crystalline Armor)
    var p_body = p_warp;
    // Slight breathing/floating motion
    p_body.y += sin(t * 1.5) * 0.1;

    // Core body (capsule)
    var d_body = sdCapsule(p_body, vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, -0.2, -1.0), 0.3);
    // Head
    let p_head = p_body - vec3<f32>(0.0, 0.4, 1.5);
    var d_head = sdCapsule(p_head, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 0.4), 0.25);
    // Snout
    d_head = smooth_min(d_head, sdCapsule(p_head, vec3<f32>(0.0, 0.0, 0.4), vec3<f32>(0.0, -0.1, 0.8), 0.1), 0.1);
    // Ears
    let p_ear_l = p_head - vec3<f32>(0.15, 0.2, 0.0);
    var d_ear_l = sdCapsule(p_ear_l, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.2, 0.4, -0.1), 0.05);
    let p_ear_r = p_head - vec3<f32>(-0.15, 0.2, 0.0);
    var d_ear_r = sdCapsule(p_ear_r, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(-0.2, 0.4, -0.1), 0.05);
    d_head = smooth_min(d_head, d_ear_l, 0.05);
    d_head = smooth_min(d_head, d_ear_r, 0.05);

    d_body = smooth_min(d_body, d_head, 0.2);

    // Cyber-armor plates (boxes booleaned out or added)
    let p_armor = p_body;
    let d_armor = sdBox(p_armor, vec3<f32>(0.35, 0.35, 0.8)) - 0.05;
    d_body = max(d_body, -sdBox(p_armor - vec3<f32>(0.0, 0.0, -0.2), vec3<f32>(0.4, 0.02, 1.0))); // Cuts
    d_body = smooth_min(d_body, sdBox(p_armor - vec3<f32>(0.0, 0.2, 0.0), vec3<f32>(0.2, 0.2, 0.5)), 0.1); // Back ridge

    // Rune Glow (Runes on body)
    let rune_noise = simplex_noise3d(p_body * 10.0 + vec3<f32>(0.0, 0.0, -t * 2.0));
    var rune_glow = 0.0;
    if (d_body < 0.1 && rune_noise > 0.6) {
        rune_glow = (rune_noise - 0.6) * 2.5 * u.zoom_params.w * (1.0 + bass * 2.0); // Rune Glow param
    }

    // 2. Nine Volumetric Aether Tails
    var d_tails = 100.0;
    var tail_glow = 0.0;
    let tail_origin = vec3<f32>(0.0, -0.1, -1.0);

    for (var i = 0; i < 9; i++) {
        let angle = f32(i) / 9.0 * PI * 2.0 + sin(t * 0.5) * 0.2;
        let s = sin(angle);
        let c = cos(angle);

        // Spread tails out backwards and outwards
        let dir = vec3<f32>(s * tail_disp, sin(t + f32(i)) * 0.5 * tail_disp, -1.5 - cos(angle)*0.2 * tail_disp);
        let dir_norm = normalize(dir);

        var p_tail = p_warp - tail_origin;
        // Project p_tail onto the tail direction
        let h = clamp(dot(p_tail, dir_norm), 0.0, length(dir) * 2.0);

        // Wavy motion based on audio and time
        let wave = sin(h * 2.0 - t * 3.0 + f32(i)) * 0.2 * (1.0 + bass);
        p_tail -= dir_norm * h + vec3<f32>(wave * c, wave, wave * s);

        // Tapering tail radius
        let r = 0.15 * smoothstep(0.0, 1.0, h) * smoothstep(length(dir) * 2.0, 1.0, h) * (1.0 + simplex_noise3d(p_tail * 5.0 + t) * 0.3);

        let d_t = length(p_tail) - r;
        d_tails = smooth_min(d_tails, d_t, 0.3);

        if (d_t < 0.5) {
            tail_glow += 0.05 / (0.01 + d_t * d_t) * (0.5 + bass * 1.5);
        }
    }

    // Combine
    var d_final = d_body;
    var mat_id = 1.0; // 1 = Body, 2 = Tails

    if (d_tails < d_body) {
        d_final = d_tails;
        mat_id = 2.0;
    }

    // Add floor/environment? No, floating in void.

    return vec3<f32>(d_final, mat_id, max(rune_glow, tail_glow));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;

    let t = u.config.x;
    let bass = plasmaBuffer[0].x;

    // Camera setup
    var ro = vec3<f32>(0.0, 1.0, 4.0);
    ro.x = sin(t * 0.2) * 2.0;
    ro.z = cos(t * 0.2) * 4.0;
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.2 * ww);

    // Raymarching
    var p = ro;
    var t_dist = 0.0;
    var res_map: vec3<f32>;
    var hit = false;
    var total_glow = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t_dist;
        res_map = map(p);
        total_glow += res_map.z; // Accumulate glow from runes/tails
        if (res_map.x < 0.001) {
            hit = true;
            break;
        }
        if (t_dist > 15.0) {
            break;
        }
        t_dist += res_map.x * 0.8;
    }

    var col = vec3<f32>(0.0);
    let storm_density = u.zoom_params.z;

    if (hit) {
        let n = calcNormal(p);
        let v = -rd;
        let l = normalize(vec3<f32>(1.0, 2.0, 3.0));
        let h_vec = normalize(v + l);

        let dif = max(dot(n, l), 0.0);
        let amb = 0.1 + 0.9 * max(0.0, dot(n, vec3<f32>(0.0, 1.0, 0.0)));
        let spec = pow(max(dot(n, h_vec), 0.0), 32.0);
        let fre = pow(clamp(1.0 - dot(n, v), 0.0, 1.0), 3.0);

        if (res_map.y == 1.0) {
            // Body - Prismatic / Crystalline Armor
            let base_col = vec3<f32>(0.1, 0.1, 0.15); // Dark cybernetic
            col = base_col * (dif + amb) + spec * 0.5;

            // Refraction/Subsurface approximation (Prismatic)
            let refr = fbm(p * 2.0 + t);
            let prism_col = vec3<f32>(
                0.5 + 0.5 * sin(refr * 10.0 + 0.0),
                0.5 + 0.5 * sin(refr * 10.0 + 2.0),
                0.5 + 0.5 * sin(refr * 10.0 + 4.0)
            );
            col += prism_col * fre * 0.5;

            // Runes
            col += vec3<f32>(0.0, 0.8, 1.0) * res_map.z; // Cyan glow

        } else {
            // Tails - Aether Plasma
            let tail_uv = length(p.xy);
            let plasma_col = mix(
                vec3<f32>(1.0, 0.2, 0.8), // Magenta
                vec3<f32>(1.0, 0.5, 0.0), // Orange
                sin(p.z * 2.0 - t * 4.0) * 0.5 + 0.5
            );
            col = plasma_col * (0.5 + amb * 0.5) + spec * 0.2;
            col += plasma_col * res_map.z * 0.2; // Self illumination
        }
    } else {
        // Quantum-Storm Void Environment (Volumetric)
        var vol_col = vec3<f32>(0.0);
        var vol_t = 0.0;
        for (var i = 0; i < 40; i++) {
            let p_vol = ro + rd * vol_t;
            let density = fbm(p_vol * 1.5 - vec3<f32>(0.0, 0.0, t * 1.0));
            if (density > 0.4) {
                let d = (density - 0.4) * storm_density * (1.0 + bass);
                vol_col += vec3<f32>(0.2, 0.0, 0.4) * d * 0.1; // Dark matter purple
            }
            vol_t += 0.3;
        }
        col = vol_col;
    }

    // Add accumulated glow bloom
    let bloom_col = mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(0.0, 1.0, 1.0), sin(t)*0.5+0.5);
    col += bloom_col * total_glow * 0.01;

    // Vignette
    col *= 1.0 - 0.5 * length(uv);

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma

    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}
