// ----------------------------------------------------------------
// Ethereal Quantum-Medusa
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
    config: vec4<f32>, // x: Time, y: Audio/Click, z: ResX, w: ResY
    zoom_config: vec4<f32>, // x: ZoomTime, y: MouseX, z: MouseY, w: Gen
    zoom_params: vec4<f32>, // Sliders mapping
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var p1 = p;
    let t = u.config.x * u.zoom_params.x;

    // Mouse repulsion
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let m_dist = length(p1 - mouse_pos);
    p1 += normalize(p1 - mouse_pos) * (1.0 / (m_dist * m_dist + 1.0)) * u.zoom_params.w;

    // Core Bell
    var p_bell = p1;
    p_bell.y += sin(t + length(p_bell.xz)) * 0.2;
    let bell = length(p_bell * vec3<f32>(1.0, 2.0, 1.0)) - 1.0;

    // Tentacles (Domain Repetition)
    var p_tent = p1;
    let angle = atan2(p_tent.z, p_tent.x);
    let num_tentacles = 8.0;
    let a = (angle + 3.14159) / (6.28318 / num_tentacles);
    let idx = floor(a);
    p_tent.xy = rot2D(t * 0.5 + p_tent.y * u.zoom_params.y) * p_tent.xy;
    let tentacles = length(p_tent.xz) - 0.1 * (1.0 - p_tent.y * 0.1);

    let d = smin(bell, tentacles, 0.5);
    return vec2<f32>(d, 1.0);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var dO = 0.0;
    var mat = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS.x;
        mat = dS.y;
        if(dO > MAX_DIST || abs(dS.x) < SURF_DIST) { break; }
    }
    return vec2<f32>(dO, mat);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let rm = raymarch(ro, rd);
    let d = rm.x;

    var col = vec3<f32>(0.02, 0.01, 0.05); // Void

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = getNormal(p);
        let viewDir = -rd;
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        let glow = clamp(u.config.y * u.zoom_params.z, 0.0, 1.0);
        col = mix(vec3<f32>(0.1, 0.5, 0.8), vec3<f32>(0.8, 0.2, 0.5), fresnel);
        col += vec3<f32>(0.2, 0.9, 0.8) * glow * (1.0 - fresnel);
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}