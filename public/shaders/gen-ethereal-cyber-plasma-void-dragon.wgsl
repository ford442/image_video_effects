struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Plasma Intensity, y=Dragon Undulation Speed, z=Body Segment Density, w=Nebula Density
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Ethereal Cyber-Plasma Void-Dragon
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

const PI: f32 = 3.14159265359;

// --- Helper Math ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Pseudo-random noise for 3D
fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);

    // Smoothstep
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);

    let n = p.x + p.y * 157.0 + 113.0 * p.z;
    let res = mix(
        mix(mix(fract(sin(n + 0.0)*43758.5453), fract(sin(n + 1.0)*43758.5453), u.x),
            mix(fract(sin(n + 157.0)*43758.5453), fract(sin(n + 158.0)*43758.5453), u.x), u.y),
        mix(mix(fract(sin(n + 113.0)*43758.5453), fract(sin(n + 114.0)*43758.5453), u.x),
            mix(fract(sin(n + 270.0)*43758.5453), fract(sin(n + 271.0)*43758.5453), u.x), u.y), u.z);
    return res;
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var f = 0.0;
    var w = 0.5;
    for (var i = 0; i < 4; i++) {
        f += w * noise(p);
        p = p * 2.0;
        w = w * 0.5;
    }
    return f;
}

// Basic Sphere SDF
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Main SDF evaluation
fn map(p: vec3<f32>, time: f32, audio: f32) -> vec4<f32> {
    // Parameters
    let plasmaIntensity = u.config.z; // param 0: 1.5 default
    let undulationSpeed = u.zoom_config.x; // param 1: 1.0 default
    let segmentDensity = u.zoom_config.y; // param 2: 20.0 default
    let nebulaDensity = u.zoom_config.z; // param 3: 0.8 default

    // --- Mouse Target ---
    let pointer = u.zoom_params.xy;
    let aspect = vec2<f32>(1.0, 1.0);
    let m = (pointer * 2.0 - vec2<f32>(1.0));
    let targetPos = vec3<f32>(m.x * 10.0, -m.y * 10.0, -5.0);

    // --- Dragon Body ---
    var d = 1000.0;
    var glow = 0.0;

    let num_segments = 15;
    var current_pos = targetPos;

    let path_length = 20.0;
    var base_col = vec3<f32>(0.0);

    // Calculate global audio pulse
    let pulse = 1.0 + 0.3 * audio;

    for (var i = 0; i < num_segments; i++) {
        let t = f32(i) / f32(num_segments - 1); // 0 to 1

        let delay = t * 3.0;
        let undulate_time = time * undulationSpeed - delay;

        let offset = vec3<f32>(
            sin(undulate_time * 1.5) * 2.0 * t,
            cos(undulate_time * 1.2) * 1.5 * t,
            t * path_length
        );

        let warp = fbm(vec3<f32>(t * 5.0, time * 0.5, 0.0)) * 2.0 * t;

        let seg_pos = targetPos + offset + vec3<f32>(warp, warp * 0.5, 0.0);

        var r = mix(1.2, 0.2, t) * pulse;

        if (i % 2 == 0) {
            r += 0.2 * audio * sin(t * 20.0 - time * 5.0);
        }

        let seg_d = sdSphere(p - seg_pos, r);
        d = smin(d, seg_d, 0.8);

        let emit = exp(-seg_d * 2.0) * plasmaIntensity;
        glow += emit;

        let col = mix(
            vec3<f32>(0.0, 1.0, 1.0),
            vec3<f32>(1.0, 0.2, 0.8),
            t
        );

        if (seg_d < 0.1) {
            base_col = col;
        }
    }

    let neb = fbm(p * 0.2 + vec3<f32>(time * 0.1)) * nebulaDensity;
    let neb_d = p.z + 10.0 - neb * 5.0;

    if (neb_d < d) {
        return vec4<f32>(neb_d, vec3<f32>(0.1, 0.0, 0.2) * neb);
    }

    return vec4<f32>(d, base_col);
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio).x - map(p - e.xyy, time, audio).x,
        map(p + e.yxy, time, audio).x - map(p - e.yxy, time, audio).x,
        map(p + e.yyx, time, audio).x - map(p - e.yyx, time, audio).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = textureDimensions(writeTexture);
    if (global_id.x >= res.x || global_id.y >= res.y) {
        return;
    }

    let time = u.config.x;
    let audio = u.config.y;

    let uv = vec2<f32>(global_id.xy) / vec2<f32>(res);
    let p = uv * 2.0 - vec2<f32>(1.0);

    var uv_c = p;
    uv_c.x = uv_c.x * (f32(res.x) / f32(res.y));

    var ro = vec3<f32>(0.0, 0.0, -15.0);
    var rd = normalize(vec3<f32>(uv_c, 1.0));

    let s = sin(time * 0.2);
    let c = cos(time * 0.2);
    let rot_mat = mat2x2<f32>(c, -s, s, c);

    let ro_xz = rot_mat * vec2<f32>(0.0, -15.0);
    ro = vec3<f32>(ro_xz.x, 0.0, ro_xz.y);

    let look_mat = mat2x2<f32>(c, -s, s, c);
    let rd_xz = look_mat * rd.xz;
    rd = normalize(vec3<f32>(rd_xz.x, rd.y, rd_xz.y));

    var t = 0.0;
    var d = 0.0;
    var p_curr = ro;
    var col_data = vec3<f32>(0.0);
    var accum_glow = vec3<f32>(0.0);

    let plasmaIntensity = u.config.z;
    let nebulaDensity = u.zoom_config.z;

    for (var i = 0; i < 100; i++) {
        p_curr = ro + rd * t;
        let res_map = map(p_curr, time, audio);
        d = res_map.x;
        col_data = res_map.yzw;

        if (d > 0.01) {
            let glow_val = exp(-d * 0.5) * 0.05 * plasmaIntensity;
            accum_glow += col_data * glow_val;
        }

        if (d < 0.01 || t > 50.0) {
            break;
        }
        t += d;
    }

    var final_col = vec3<f32>(0.0);

    if (t < 50.0) {
        let n = getNormal(p_curr, time, audio);
        let l = normalize(vec3<f32>(5.0, 5.0, -5.0));
        let v = normalize(ro - p_curr);
        let h = normalize(l + v);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        let iridescence = 0.5 + 0.5 * cos(3.0 * fresnel + vec3<f32>(0.0, 2.0, 4.0));

        let subsurface = max(0.0, dot(n, -l)) * 0.5;

        final_col = col_data * (diff + 0.2) + spec * iridescence + subsurface * col_data * 2.0;
        final_col += iridescence * fresnel * 2.0;

        let fog = exp(-t * 0.05);
        final_col = mix(vec3<f32>(0.02, 0.0, 0.05), final_col, fog);
    } else {
        final_col = vec3<f32>(0.01, 0.0, 0.03);
    }

    final_col += accum_glow;

    let star_uv = (uv_c * 5.0 + vec2<f32>(time * 0.1));
    let stars = pow(noise(vec3<f32>(star_uv * 10.0, time)), 15.0) * 5.0;
    if (t > 49.0) {
        final_col += stars * vec3<f32>(0.5, 0.8, 1.0) * nebulaDensity * (1.0 + audio);
    }

    final_col = final_col * 0.6;
    final_col = (final_col * (2.51 * final_col + vec3<f32>(0.03))) / (final_col * (2.43 * final_col + vec3<f32>(0.59)) + vec3<f32>(0.14));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_col, 1.0));
}
