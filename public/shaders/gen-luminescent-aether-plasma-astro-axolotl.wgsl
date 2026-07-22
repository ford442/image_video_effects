// ----------------------------------------------------------------
// Luminescent Aether-Plasma Astro-Axolotl
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
    zoom_params: vec4<f32>,  // x=Gill Expansion, y=Current Warp, z=Nebula Density, w=Bioluminescence
    ripples: array<vec4<f32>, 50>,
};

// Math / Utility functions
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// 3D Simplex noise approximation
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    return fract(sin(dot(q, vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_pow = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)), hash(p + vec3<f32>(1.0, 0.0, 0.0)), f_pow.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)), hash(p + vec3<f32>(1.0, 1.0, 0.0)), f_pow.x), f_pow.y),
               mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)), hash(p + vec3<f32>(1.0, 0.0, 1.0)), f_pow.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)), hash(p + vec3<f32>(1.0, 1.0, 1.0)), f_pow.x), f_pow.y), f_pow.z);
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Gravity manipulation from mouse cursor (Current Warp)
    let mouse = u.zoom_config.yz; // Normalized mouse
    let mouse_world = vec3<f32>(mouse.x * 4.0 - 2.0, mouse.y * -4.0 + 2.0, 0.0);

    let dist = length(p.xy - mouse_world.xy);
    let warp_factor = u.zoom_params.y / (1.0 + dist * dist * 3.0);
    p -= vec3<f32>(mouse_world.xy, 0.0) * warp_factor;

    // Slowly translate Axolotl along the Z axis (swimming forward)
    let swim_time = u.config.x * 0.5;

    // Axolotl Body (Stretched sphere)
    var p_body = p;
    // Wiggle body
    p_body.x += sin(p_body.y * 2.0 - swim_time * 3.0) * 0.1;
    let d_body = length(p_body * vec3<f32>(1.0, 0.3, 1.0)) - 0.4;
    var res = vec2<f32>(d_body, 1.0); // ID 1 = Body

    // Axolotl Tail
    var p_tail = p;
    p_tail.y += 0.5; // Offset tail position
    p_tail.x += sin(p_tail.y * 3.0 - swim_time * 5.0) * 0.15; // Faster wiggle
    let d_tail = length(p_tail * vec3<f32>(2.0, 1.0, 3.0)) - 0.1;

    res.x = smin(res.x, d_tail, 0.2); // Blend tail with body

    // External Gills (Fractal trees)
    var p_gills = p;
    p_gills.y -= 0.3; // Position near head
    p_gills.x = abs(p_gills.x) - 0.4; // Symmetry for left/right gills

    // Audio reaction (bass) for gill expansion and rotation
    let audio_react = plasmaBuffer[0].x;
    let gill_expansion = u.zoom_params.x * (1.0 + audio_react * 0.5);

    var d_gills = 100.0;
    var scale = 1.0;
    var p_f = p_gills;

    // Fractal iterations for gills
    for(var i = 0; i < 3; i++) {
        p_f.xy = p_f.xy * rot2D(0.5 + sin(swim_time + f32(i)) * 0.2 * gill_expansion);
        p_f.xz = p_f.xz * rot2D(0.3 * gill_expansion);
        p_f.y -= 0.15 * scale;

        let cylinder = max(length(p_f.xz) - 0.02 * scale, abs(p_f.y) - 0.15 * scale);
        d_gills = min(d_gills, cylinder);

        // Branching
        p_f = abs(p_f);
        p_f.x -= 0.05 * scale;
        scale *= 0.7;
    }

    // Combine Gills with Body
    if (d_gills < res.x) {
        res = vec2<f32>(d_gills, 2.0); // ID 2 = Gills
    } else {
        res.x = smin(res.x, d_gills, 0.1);
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var d0 = 0.0;
    var id = 0.0;
    for(var i = 0; i < 80; i++) {
        let p = ro + rd * d0;
        let dS = map(p);
        d0 += dS.x;
        id = dS.y;
        if(dS.x < 0.001 || d0 > 10.0) { break; }
    }
    return vec2<f32>(d0, id);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dimensions.xy)) / f32(dimensions.y);

    let t = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Background / Nebula
    var col = vec3<f32>(0.0);
    let nebula_density = u.zoom_params.z;

    // Fluid dynamic noise background
    var n_val = 0.0;
    var n_pos = ro + rd * 5.0;
    n_pos.z += t * 0.2; // Translate noise slowly
    for(var i = 0.0; i < 4.0; i += 1.0) {
        n_val += noise(n_pos * pow(2.0, i)) * pow(0.5, i);
    }

    let abyssal_blue = vec3<f32>(0.05, 0.1, 0.2);
    let quantum_purple = vec3<f32>(0.2, 0.0, 0.3);
    let bg_color = mix(abyssal_blue, quantum_purple, n_val) * nebula_density;
    col += bg_color;

    // Raymarching Axolotl
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let m_id = rm.y;

    if (d < 10.0) {
        let p = ro + rd * d;
        let n = calcNormal(p);

        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        let base_col = vec3<f32>(0.8, 0.2, 0.6); // Pinkish axolotl base

        if (m_id == 1.0) {
            // Body: subsurface scattering and refraction
            let sss = max(0.0, dot(rd, -lightDir));
            col = base_col * diff + vec3<f32>(0.1, 0.5, 0.8) * fresnel + vec3<f32>(0.5, 0.1, 0.4) * sss * 0.5;
            col = mix(col, bg_color, 0.3); // Pick up ambient nebula light
        } else if (m_id == 2.0) {
            // Gills: Bioluminescence synced to audio
            let biolum = u.zoom_params.w;
            let audio_react = plasmaBuffer[0].x; // Bass
            let glow_color = vec3<f32>(0.0, 1.0, 0.8); // Cyan/Gold
            let emission = glow_color * (1.0 + audio_react * biolum);
            col = base_col * 0.5 + emission + vec3<f32>(1.0) * fresnel;
        }
    }

    // Output
    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}
