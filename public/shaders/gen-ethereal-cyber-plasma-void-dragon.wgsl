struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
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

// PRNG
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// 3D Noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n = p.x + p.y * 157.0 + 113.0 * p.z;
    let res = mix(
        mix(mix(fract(sin(n + 0.0) * 43758.5453123),
                fract(sin(n + 1.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 157.0) * 43758.5453123),
                fract(sin(n + 158.0) * 43758.5453123), u.x), u.y),
        mix(mix(fract(sin(n + 113.0) * 43758.5453123),
                fract(sin(n + 114.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 270.0) * 43758.5453123),
                fract(sin(n + 271.0) * 43758.5453123), u.x), u.y), u.z);
    return res;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var current_p = p;
    var a = 0.5;
    for (var i = 0; i < 4; i = i + 1) {
        f = f + a * noise(current_p);
        current_p = current_p * 2.0;
        a = a * 0.5;
    }
    return f;
}

// Rotations
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1., 0., 0., 0., c, -s, 0., s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0., s, 0., 1., 0., -s, 0., c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0., s, c, 0., 0., 0., 1.);
}
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDFs
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
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

// Environment mapping
fn map(p: vec3<f32>, time: f32, audio: f32, mouseTarget: vec3<f32>, params: vec4<f32>) -> vec2<f32> {
    let plasma_int = params.x;
    let dragon_speed = params.y;
    let segment_den = params.z;

    // Base time adjusted by speed
    let t = time * dragon_speed;

    // Dragon path / spine
    var d = 1000.0;
    var mat = 0.0; // 0 = void, 1 = dragon body

    let segments = i32(segment_den);

    // Mouse attraction point
    var dragon_head = mouseTarget;
    // Add some wandering to head
    dragon_head = dragon_head + vec3<f32>(sin(t*0.5), cos(t*0.3), sin(t*0.7)) * 2.0;

    var prev_pos = dragon_head;

    // Segment logic
    for (var i = 0; i < 20; i = i + 1) { // Fixed loop count to satisfy WGSL, use fixed max
        if (f32(i) >= segment_den) { continue; }

        let fi = f32(i);
        let t_offset = fi * 0.15;

        // Generate undulation
        let undulation = vec3<f32>(
            sin(t * 2.0 - t_offset) * 1.5,
            cos(t * 1.5 - t_offset) * 1.0,
            sin(t * 1.2 - t_offset) * 1.0
        );

        var cur_pos = prev_pos + vec3<f32>(0.0, 0.0, 1.2) + undulation * (0.2 + fi*0.02);
        // Add noise
        cur_pos = cur_pos + (hash33(vec3<f32>(fi, time*0.1, 0.0)) - 0.5) * 0.5 * audio;

        let r = 0.8 - fi * 0.03 + sin(fi*0.5 + t*3.0)*0.1;

        let seg_d = sdCapsule(p, prev_pos, cur_pos, max(r, 0.1));

        // Add scale displacement
        let scale_disp = (noise(p * 5.0 + time) * 2.0 - 1.0) * 0.05 * (1.0 + audio * 2.0);
        let final_seg_d = seg_d + scale_disp;

        d = smin(d, final_seg_d, 0.8);

        prev_pos = cur_pos;
    }

    mat = 1.0;

    // Add some void/nebula floating crystals
    let crystal_p = p;
    let grid = floor(crystal_p / 10.0);
    let cell_p = fract(crystal_p / 10.0) * 10.0 - 5.0;

    // Only in some cells
    if (hash12(grid.xy + grid.z) > 0.7) {
        let cr_d = length(cell_p) - 0.5 - audio;
        if (cr_d < d) {
            d = cr_d;
            mat = 2.0; // Crystal
        }
    }

    return vec2<f32>(d, mat);
}

// Calc normal
fn calcNormal(p: vec3<f32>, time: f32, audio: f32, mouseTarget: vec3<f32>, params: vec4<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, mouseTarget, params).x - map(p - e.xyy, time, audio, mouseTarget, params).x,
        map(p + e.yxy, time, audio, mouseTarget, params).x - map(p - e.yxy, time, audio, mouseTarget, params).x,
        map(p + e.yyx, time, audio, mouseTarget, params).x - map(p - e.yyx, time, audio, mouseTarget, params).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    if (global_id.x >= dim.x || global_id.y >= dim.y) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * vec2<f32>(dim.xy)) / f32(dim.y);

    let time = u.config.x;
    let audio = u.config.y;

    // Sliders
    let params = u.zoom_params;
    // x = Plasma Intensity (default 1.5)
    // y = Dragon Undulation Speed (default 1.0)
    // z = Body Segment Density (default 20.0)
    // w = Nebula Density (default 0.8)

    let mouse = vec2<f32>(u.zoom_config.y - 0.5, u.zoom_config.z - 0.5);
    let mouseTarget = vec3<f32>(mouse.x * 10.0, mouse.y * 10.0, -5.0);

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -15.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Rotate camera slightly over time
    let cam_rot = rot(time * 0.1);
    rd = vec3<f32>(cam_rot * rd.xy, rd.z);

    // Raymarching
    var p = ro;
    var total_dist = 0.0;
    var mat = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 100; i = i + 1) {
        let res = map(p, time, audio, mouseTarget, params);
        let d = res.x;
        mat = res.y;

        if (d < 0.01) {
            break;
        }
        if (total_dist > 50.0) {
            break;
        }

        // Accumulate glow near the surface
        if (mat == 1.0) { // Dragon body glow
            glow = glow + 0.05 / (1.0 + d * d * 10.0) * params.x;
        } else if (mat == 2.0) { // Crystal glow
            glow = glow + 0.1 / (1.0 + d * d * 5.0) * audio;
        }

        p = p + rd * d;
        total_dist = total_dist + d;
    }

    var final_col = vec3<f32>(0.0);

    // Background Nebula (Volumetric FBM)
    let neb_dir = rd;
    let neb = fbm(neb_dir * 3.0 + time * 0.2 + mouseTarget * 0.05) * params.w;
    let neb_col = mix(vec3<f32>(0.05, 0.0, 0.1), vec3<f32>(0.2, 0.4, 0.6), neb);
    col = neb_col * (1.0 + audio);

    if (total_dist < 50.0) {
        // We hit something
        let n = calcNormal(p, time, audio, mouseTarget, params);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        // Diffuse
        let diff = max(dot(n, l), 0.0);
        // Specular
        let r_vec = reflect(rd, n);
        let spec = pow(max(dot(r_vec, l), 0.0), 32.0);

        // Fresnel / Iridescence
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let irid_col = 0.5 + 0.5 * cos(time + p.y * 2.0 + vec3<f32>(0.0, 2.0, 4.0));

        if (mat == 1.0) { // Dragon
            // Base metallic color
            let base_col = vec3<f32>(0.1, 0.15, 0.2);
            col = base_col * diff + spec * irid_col + fresnel * irid_col * 2.0;

            // Subsurface / Plasma glow mapping
            let inner_glow = vec3<f32>(0.0, 0.8, 1.0) * glow * (1.0 + audio * 1.5);
            col = col + inner_glow;

        } else if (mat == 2.0) { // Crystal
            col = vec3<f32>(0.8, 0.2, 1.0) * diff + spec + fresnel * vec3<f32>(1.0, 0.5, 0.8);
            col = col + vec3<f32>(1.0, 0.0, 0.5) * glow;
        }
    }

    // Add volumetric nebula fog
    col = mix(col, neb_col, smoothstep(10.0, 50.0, total_dist));

    // Tone mapping
    col = col / (1.0 + col);

    // Vignette
    let vig = 1.0 - length(uv) * 0.8;
    col = col * vig;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_col, 1.0));
}
