// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Void-Kitsune
// Category: generative
// ----------------------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tail Dispersion, y=Rift Density, z=Rune Intensity, w=Glass Refraction
    ripples: array<vec4<f32>, 50>,
};

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

// ----------------------------------------------------------------
// Helper functions and Math utilities
// ----------------------------------------------------------------

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

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

// 3D cellular noise (simplified)
fn cellular(p: vec3<f32>) -> f32 {
    let fp = floor(p);
    let fv = fract(p);
    var d = 1.0;
    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            for (var k = -1; k <= 1; k++) {
                let cell = vec3<f32>(f32(i), f32(j), f32(k));
                let offset = hash3(fp + cell);
                let diff = cell + offset - fv;
                d = min(d, length(diff));
            }
        }
    }
    return d;
}

// Map function returning vec2(distance, material_id)
// Material IDs: 1 = Body, 2 = Tails, 3 = Rift, 4 = Dust
fn map(p: vec3<f32>, time: f32, audio: f32, mpos: vec2<f32>) -> vec2<f32> {
    let tail_dispersion = u.zoom_params.x;
    let rift_density = u.zoom_params.y;

    // Apply mouse bending
    var pt = p;
    pt.x -= mpos.x * 2.0 * smoothstep(10.0, 0.0, abs(pt.z));
    pt.y -= mpos.y * 2.0 * smoothstep(10.0, 0.0, abs(pt.z));

    // 1. Central Body
    let body_pos = pt - vec3<f32>(0.0, 0.0, 5.0);
    var d_body = length(body_pos) - 1.5; // Base sphere
    // Add cellular perturbation
    d_body += 0.2 * cellular(body_pos * 2.0 + vec3<f32>(time));

    // 2. Tails
    var d_tails = 100.0;
    for (var i = 0; i < 9; i++) {
        let fi = f32(i);
        let phase = fi * PI * 2.0 / 9.0;

        var tp = pt;
        // Move to tail origin (behind body)
        tp.z -= 6.0;

        // Spread tails outward
        let spread = rot(phase);
        let rotated_xy = spread * tp.xy;
        tp = vec3<f32>(rotated_xy.x, rotated_xy.y, tp.z);

        // Offset outward from center
        tp.x -= 0.5 * tail_dispersion;

        // Sine wave wiggling
        let wave = sin(tp.z * 1.5 - time * 3.0 + phase) * 0.5 * (1.0 + audio * 0.5);
        tp.x += wave;

        // Distance to cylinder along z
        let d_cyl = length(tp.xy) - 0.2 - tp.z * 0.05; // Tapering

        // Only consider the tail region (z > 0)
        let z_bounds = max(-tp.z, tp.z - 15.0);
        let tail_dist = max(d_cyl, z_bounds);

        d_tails = smin(d_tails, tail_dist, 0.3);
    }

    // Smooth min between body and tails
    var d_kitsune = smin(d_body, d_tails, 0.5);
    var mat_id = select(2.0, 1.0, d_body < d_tails);

    // 3. Volumetric Rift (Tubular SDF)
    var rp = pt;
    let rrot = rot(rp.z * 0.1);
    let rotated_rp_xy = rrot * rp.xy;
    rp = vec3<f32>(rotated_rp_xy.x, rotated_rp_xy.y, rp.z);
    let d_rift = -(length(rp.xy) - 8.0) + sin(rp.z * 2.0) * 0.5; // Hollow cylinder inner surface

    // 4. Gravity Dust
    let cell_size = 2.0;
    let local_p = fract(pt / cell_size) - 0.5;
    let cell_id = floor(pt / cell_size);
    let h = hash3(cell_id);
    let dust_pos = local_p + (h - vec3<f32>(0.5)) * 0.8;
    let d_dust = length(dust_pos) - 0.05 * h.x;

    // Combine
    var d_final = d_kitsune;

    if (d_dust < d_final) {
        d_final = d_dust;
        mat_id = 4.0;
    }

    if (d_rift < d_final) {
        d_final = d_rift;
        mat_id = 3.0;
    }

    return vec2<f32>(d_final, mat_id);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, mpos: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio, mpos).x - map(p - e.xyy, time, audio, mpos).x,
        map(p + e.yxy, time, audio, mpos).x - map(p - e.yxy, time, audio, mpos).x,
        map(p + e.yyx, time, audio, mpos).x - map(p - e.yyx, time, audio, mpos).x
    ));
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));

    if (coord.x >= dim.x || coord.y >= dim.y) {
        return;
    }

    let uv = (coord - 0.5 * dim) / dim.y;

    let time = u.config.x;
    let audio = u.config.y;
    let click_shockwave = fract(u.config.y * 0.1); // Assuming some click mapping

    // Mouse coords mapping
    var mpos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) / dim * 2.0 - vec2<f32>(1.0);
    if (length(mpos) > 1.5) { mpos = vec2<f32>(0.0); } // Reset if no mouse input

    let rune_intensity = u.zoom_params.z;
    let glass_refraction = u.zoom_params.w;
    let rift_density_param = u.zoom_params.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, 0.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var p = ro;

    // Density accumulator for volumetrics
    var density = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let res = map(p, time, audio, mpos);
        d = res.x;
        m = res.y;

        if (d < 0.01) {
            break;
        }

        // Volumetric accumulation for rift
        if (m == 3.0) {
            density += 0.05 * rift_density_param / (1.0 + d*d);
        }

        t += d * 0.5; // conservative step
        if (t > 30.0) {
            break;
        }
    }

    var col = vec3<f32>(0.0);

    if (t < 30.0 && m != 3.0) {
        // Surface hit
        let n = calcNormal(p, time, audio, mpos);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let fre = pow(1.0 - max(dot(n, view), 0.0), 3.0);

        if (m == 1.0) {
            // Kitsune Body (Cyber-glass armor + runes)
            let rune_pattern = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);
            var rune_col = vec3<f32>(0.0);
            if (rune_pattern > 0.5) {
                // Shift UV to Gold on bass
                let rune_hue = vec3<f32>(0.8, 0.1, 1.0) * (1.0 - audio) + vec3<f32>(1.0, 0.8, 0.2) * audio;
                rune_col = rune_hue * rune_intensity * audio * 2.0;
            }

            // Faux refraction sampling background
            let refr_dir = refract(rd, n, 0.9);
            // Simulated fake bg color based on refraction dir
            let bg_col = vec3<f32>(0.1, 0.0, 0.2) + 0.5 * sin(refr_dir.xyz * 5.0 + vec3<f32>(time));

            col = mix(bg_col * glass_refraction, vec3<f32>(1.0), fre) + diff * 0.2 + rune_col;

        } else if (m == 2.0) {
            // Tails (Liquid neon)
            let tail_glow = vec3<f32>(0.1, 0.8, 1.0) * (0.5 + audio);
            col = tail_glow * (diff + fre);

        } else if (m == 4.0) {
            // Dust
            col = vec3<f32>(1.0, 0.5, 0.8) * 3.0; // Emissive pink
        }
    }

    // Add Volumetric Rift glow
    let rift_col = vec3<f32>(0.8, 0.2, 0.6) * density;
    col += rift_col;

    // Ambient / Fog
    col = mix(col, vec3<f32>(0.02, 0.01, 0.05), smoothstep(10.0, 30.0, t));

    // Tone mapping
    col = col / (vec3<f32>(1.0) + col);

    let tex_coord = coord / dim;
    let prev_frame = textureSampleLevel(dataTextureC, u_sampler, tex_coord, 0.0);
    col = mix(col, prev_frame.xyz, 0.08 * glass_refraction);

    let final_alpha = clamp(1.0 - density * 0.1, 0.2, 1.0);
    let final_depth = clamp(t / 30.0, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, final_alpha));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(final_depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(col, final_alpha));
}
