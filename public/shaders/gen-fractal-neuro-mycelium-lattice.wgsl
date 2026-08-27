// ----------------------------------------------------------------
// Fractal Neuro-Mycelium Lattice
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Branch Density, .y = Flow Speed, .z = Glow Intensity, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
const MAX_STEPS = 100;
const MAX_DIST = 30.0;
const SURF_DIST = 0.01;
const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Voronoi edges for the lattice network
fn voronoi_edges(x: vec3<f32>, flow: f32) -> f32 {
    let p = floor(x);
    let f = fract(x);

    var mb = vec3<f32>(0.0);
    var res = vec3<f32>(8.0);
    var center = vec3<f32>(0.0);

    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            for (var k = -1; k <= 1; k++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash33(p + b) + sin(flow + hash33(p + b)*10.0)*0.2;
                let d = dot(r, r);

                if (d < res.x) {
                    res.z = res.y;
                    res.y = res.x;
                    res.x = d;
                    mb = b;
                    center = r;
                } else if (d < res.y) {
                    res.z = res.y;
                    res.y = d;
                } else if (d < res.z) {
                    res.z = d;
                }
            }
        }
    }

    var edge_dist = 8.0;
    for (var i = -2; i <= 2; i++) {
        for (var j = -2; j <= 2; j++) {
            for (var k = -2; k <= 2; k++) {
                let b = mb + vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash33(p + b) + sin(flow + hash33(p + b)*10.0)*0.2;
                if (dot(r - center, r - center) > 0.00001) {
                    let d = dot(center + r, normalize(r - center));
                    edge_dist = min(edge_dist, d);
                }
            }
        }
    }

    return edge_dist;
}

// --- SDF & NOISE ---
fn map(p: vec3<f32>, audio: f32) -> vec2<f32> {
    let density = max(u.zoom_params.x, 0.1);
    let flow_speed = u.zoom_params.y;
    let t = u.config.x * flow_speed;

    var pos = p;

    // Mouse warp
    let mouse_pos = (u.zoom_config.yz - 0.5) * 2.0;
    let m_dist = length(pos.xy - mouse_pos * 5.0);
    let pull = smoothstep(3.0, 0.0, m_dist);
    pos.x -= mouse_pos.x * pull * 2.0;
    pos.y -= mouse_pos.y * pull * 2.0;

    pos *= density;

    let d_edges = voronoi_edges(pos, t);

    // Smooth the edges to form mycelial tubes
    // Base tube radius modulated by audio and flow
    let base_radius = 0.05 / density;
    let pulse = sin(p.z * 5.0 - t * 10.0) * 0.5 + 0.5;
    let radius = base_radius + pulse * 0.02 * audio * u.zoom_params.w;

    let lattice = abs(d_edges) - radius;

    // Add some larger structural nodes at voronoi centers
    let nodes = length(fract(pos + 0.5) - 0.5) - radius * 3.0;

    let d = smin(lattice / density, nodes / density, 0.2 / density);

    // Material ID: distance, density accumulation factor
    return vec2<f32>(d, d_edges);
}

// --- RAYMARCHING & SHADING ---
fn get_normal(p: vec3<f32>, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, audio).x - map(p - e.xyy, audio).x,
        map(p + e.yxy, audio).x - map(p - e.yxy, audio).x,
        map(p + e.yyx, audio).x - map(p - e.yyx, audio).x
    );
    return normalize(n);
}

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x) + 0.5, f32(id.y) + 0.5);
    let base_uv = fragCoord / resolution;
    let uv = (fragCoord - 0.5 * resolution) / resolution.y;

    // Sample audio
    let audio_low = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.1, 0.5), 0.0).r;
    let audio_mid = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.5, 0.5), 0.0).r;
    let audio = (audio_low + audio_mid) * 0.5;

    // Camera setup
    let time = u.config.x * u.zoom_params.y;
    var ro = vec3<f32>(0.0, 0.0, -time * 2.0);
    var ta = vec3<f32>(0.0, 0.0, ro.z - 1.0);

    let mouse = (u.zoom_config.yz - 0.5) * 2.0;
    ro.x += mouse.x * 2.0;
    ro.y -= mouse.y * 2.0;

    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    var dO = 0.0;
    var dS = 0.0;
    var accum = 0.0;
    var p = ro;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let map_res = map(p, audio);
        dS = map_res.x;

        // Volumetric accumulation near edges
        accum += smoothstep(0.1, 0.0, map_res.y) * 0.05;

        if (dS < SURF_DIST) {
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
        dO += dS;
    }

    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        let n = get_normal(p, audio);
        let light = normalize(vec3<f32>(1.0, 2.0, -1.0));

        // Diffuse
        let dif = max(dot(n, light), 0.0);

        // Fake SSS by stepping into surface
        let sss_dist = 0.1;
        let sss_sample = map(p - n * sss_dist, audio).x;
        let sss = smoothstep(-sss_dist, 0.0, sss_sample);

        // Glow / Emission
        let pulse = sin(p.z * 5.0 - u.config.x * 10.0) * 0.5 + 0.5;
        let emit = pulse * audio * u.zoom_params.w * u.zoom_params.z;

        let base_col = vec3<f32>(0.1, 0.3, 0.8) * sss + vec3<f32>(0.8, 0.9, 1.0) * dif * 0.2;
        let glow_col = vec3<f32>(0.0, 1.0, 0.8) * emit;

        col = base_col + glow_col;

        // Depth fog
        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), smoothstep(0.0, MAX_DIST, dO));
    }

    // Add volumetric accumulation for organic glow
    col += vec3<f32>(0.1, 0.4, 0.9) * accum * u.zoom_params.z * 0.5;

    // Tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
