// ----------------------------------------------------------------
// Abyssal Chrono-Coral
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Coral Density, y=Branch Complexity, z=Bioluminescence Glow, w=Time Dilation Field
    ripples: array<vec4<f32>, 50>,
};

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn fbm3(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var x = p;
    var a = 0.5;
    for(var i = 0; i < 4; i++) {
        let h = hash3(x);
        f += a * (h.x + h.y + h.z) / 3.0;
        x *= 2.0;
        a *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(pos_in: vec3<f32>, time: f32) -> vec2<f32> {
    var p = pos_in;

    // Domain repetition
    p.x = (fract(p.x / 10.0 + 0.5) - 0.5) * 10.0;
    p.z = (fract(p.z / 10.0 + 0.5) - 0.5) * 10.0;

    // Domain warping
    p.x += (fbm3(p * 0.5 + time * 0.2) - 0.5) * 2.0;
    p.y += (fbm3(p * 0.5 + time * 0.2 + 100.0) - 0.5) * 2.0;
    p.z += (fbm3(p * 0.5 + time * 0.2 + 200.0) - 0.5) * 2.0;

    let iterations = i32(u.zoom_params.y);
    var d = 1000.0;
    var s = 1.0;

    for(var i = 0; i < iterations; i++) {
        p = abs(p) - vec3<f32>(0.5, 1.5, 0.5);
        let rot_xy = rotate2D(0.5 + sin(time * 0.1) * 0.2) * p.xy;
        p.x = rot_xy.x;
        p.y = rot_xy.y;
        let rot_yz = rotate2D(0.3 + cos(time * 0.15) * 0.2) * p.yz;
        p.y = rot_yz.x;
        p.z = rot_yz.y;
        s *= 1.2;
        p *= 1.2;

        // Base coral branch
        let branch = (length(p.xz) - u.zoom_params.x * (1.0 + u.config.y * 0.5)) / s;
        d = smin(d, branch, 0.2);
    }

    // Bioluminescent nodes at tips
    let node_d = length(p) / s - (0.2 + u.config.y * 0.1);

    if (node_d < d) {
        return vec2<f32>(node_d, 2.0); // Material 2: nodes
    }
    return vec2<f32>(d, 1.0); // Material 1: branch
}

fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time).x - map(p - e.xyy, time).x,
        map(p + e.yxy, time).x - map(p - e.yxy, time).x,
        map(p + e.yyx, time).x - map(p - e.yyx, time).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.z, u.config.w);

    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;
    var base_time = u.config.x * 0.5;

    // Mouse time dilation field
    let mouse_uv = u.zoom_config.yz;
    let dist_to_mouse = length(uv - mouse_uv);
    let dilation_strength = u.zoom_params.w;
    let dilation = smoothstep(dilation_strength, 0.0, dist_to_mouse) * 10.0;
    let local_time = base_time + dilation;

    var ro = vec3<f32>(0.0, base_time * 2.0, base_time * 1.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Camera rotation
    let rd_xy = rotate2D(sin(base_time * 0.1) * 0.2) * rd.xy;
    rd.x = rd_xy.x;
    rd.y = rd_xy.y;
    let rd_xz = rotate2D(cos(base_time * 0.05) * 0.2) * rd.xz;
    rd.x = rd_xz.x;
    rd.z = rd_xz.y;

    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var acc_glow = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p, local_time);
        d = res.x;
        mat = res.y;

        if (d < 0.001) { break; }
        t += d * 0.5;

        if (mat == 2.0) {
            acc_glow += 0.01 / (0.01 + d * d) * u.zoom_params.z;
        }
        if (t > 20.0) { break; }
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, local_time);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        if (mat == 1.0) {
            // Subsurface scattering proxy + deep abyssal color
            let sss = smoothstep(0.0, 1.0, map(p + l * 0.1, local_time).x);
            col = vec3<f32>(0.0, 0.2, 0.4) * diff + vec3<f32>(0.0, 0.5, 0.8) * sss + fresnel * vec3<f32>(0.5, 0.8, 1.0);
        } else {
            // Bioluminescent nodes
            col = vec3<f32>(0.0, 1.0, 0.8) * 2.0 + vec3<f32>(1.0, 0.0, 0.5) * fresnel;
        }
    } else {
        // Starlight background
        let stars = pow(hash3(rd * 100.0).x, 50.0);
        col += stars * vec3<f32>(1.0);
    }

    // Add volumetric fog/glow
    col += acc_glow * vec3<f32>(0.0, 0.5, 1.0);

    // Ambient fog
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), 1.0 - exp(-0.02 * t));

    // Audio reactivity to overall brightness
    col *= 1.0 + u.config.y * 0.2;

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}