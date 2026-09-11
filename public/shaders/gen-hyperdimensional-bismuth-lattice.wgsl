// ----------------------------------------------------------------
// Hyperdimensional Bismuth Lattice
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

struct Uniforms {
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Complexity, .y = Iridescence, .z = Twist, .w = Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 50.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Fractal folding space
fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    // Mouse twist
    let twist = clamp(u.zoom_params.z, 0.0, 1.0);

    // Audio Reactivity for twist
    let bass = extraBuffer[0];
    let bassSmooth = extraBuffer[133];
    let audioMod = 1.0 + (bassSmooth * 0.5);

    if (twist > 0.0) {
        let mouse = u.zoom_config.yz;
        // Simplified twist for structure outline
        let r = length(pos.xy - (mouse * 2.0 - 1.0) * 5.0);
        let a = twist * audioMod * exp(-r * 0.5);
        let rt = rot(a);
        let xy = vec2<f32>(pos.x * rt[0][0] + pos.y * rt[1][0], pos.x * rt[0][1] + pos.y * rt[1][1]);
        pos.x = xy.x;
        pos.y = xy.y;
    }

    // Audio reactivity for scale
    let pulse = 1.0 + (bass * 0.1);

    // Fractal iterations
    let complexity = clamp(u.zoom_params.x, 0.0, 1.0);
    let iters = 4.0 + (complexity * 4.0);
    var scale = 1.0;

    // Bismuth-like folding
    for (var i = 0; i < 8; i++) {
        if (f32(i) > iters) { break; }
        pos = abs(pos) - vec3<f32>(0.5 * pulse);

        let ry = rot(PI / 4.0);
        let xz = vec2<f32>(pos.x * ry[0][0] + pos.z * ry[1][0], pos.x * ry[0][1] + pos.z * ry[1][1]);
        pos.x = xz.x;
        pos.z = xz.y;

        let rz = rot(PI / 4.0);
        let xy2 = vec2<f32>(pos.x * rz[0][0] + pos.y * rz[1][0], pos.x * rz[0][1] + pos.y * rz[1][1]);
        pos.x = xy2.x;
        pos.y = xy2.y;

        pos = pos * 2.0;
        scale = scale * 2.0;
    }

    return sdBox(pos, vec3<f32>(0.5)) / scale;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

// Branchless cosine palette for thin-film interference
fn palette(t: f32, iridescence: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + vec3<f32>(iridescence);
    return a + b * cos(2.0 * PI * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let speed = clamp(u.zoom_params.w, 0.0, 1.0);
    let t = u.config.x * (0.5 + speed * 1.5);

    // Normalized pixel coordinates (from -1 to 1)
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    // Ray origin and direction
    let ro = vec3<f32>(0.0, 0.0, -3.0 + t);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Raymarching
    var d0 = 0.0;
    var p = ro;
    var i = 0;
    for (i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * d0;
        let dS = map(p);
        d0 += dS;
        if (dS < SURF_DIST || d0 > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    if (d0 < MAX_DIST) {
        let n = calcNormal(p);
        let v = -rd; // View direction
        let ndotv = max(dot(n, v), 0.0);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let ndotl = max(dot(n, lightDir), 0.0);
        let h = normalize(lightDir + v);
        let spec = pow(max(dot(n, h), 0.0), 32.0);

        // Iridescent coloring
        let iridescence = clamp(u.zoom_params.y, 0.0, 1.0);
        // Base color based on normal, view, and depth
        let phase = ndotv * 2.0 + length(p) * 0.1;
        let albedo = palette(phase, iridescence);

        // Simple Ambient Occlusion
        let aoStep = 0.1;
        let ao = clamp(map(p + n * aoStep) / aoStep, 0.0, 1.0);

        col = albedo * (ndotl * 0.8 + 0.2) * ao + vec3<f32>(spec) * 0.5;

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), 1.0 - exp(-0.02 * d0 * d0));
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
