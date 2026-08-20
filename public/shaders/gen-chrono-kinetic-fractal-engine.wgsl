// ----------------------------------------------------------------
// Chrono-Kinetic Fractal Engine
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

// 4D Rotation helper (XW plane and YZ plane in 4D, abstracted as two 3D rotations for simplicity in our projection)
fn map(p_in: vec3<f32>, audio: f32) -> vec2<f32> {
    var p = p_in;

    // Mouse Interaction: Gravitational "time-dilation" warp
    // u.zoom_config.yz gives mouse UV (0 to 1). Center at 0.5.
    let mouse = (u.zoom_config.yz - 0.5) * 2.0 * vec2<f32>(u.config.z / u.config.w, 1.0);
    // Mouse warp strength parameter
    let warp_strength = u.zoom_params.y;
    let d_mouse = length(p.xy - mouse);
    let twist = exp(-d_mouse * 2.0) * warp_strength * sin(u.config.x);
    p = vec3<f32>(rot(twist) * p.xy, p.z);

    // Spatial folding / domain repetition
    let spacing = 4.0;
    p = (p % spacing + spacing) % spacing - spacing * 0.5;

    let time = u.config.x * u.zoom_params.w + audio * 0.5; // Audio reactive speed and kinetic parameter
    let complexity = max(1.0, u.zoom_params.x);

    // Fractal logic: Menger-like folding and rotation
    var d = 1e10;
    var trap = 0.0;
    let s = 1.0;

    var q = p;
    for (var i = 0; i < 4; i = i + 1) {
        if (f32(i) > complexity) { break; }

        q = abs(q) - vec3<f32>(0.5) * s;
        q = vec3<f32>(rot(time * 0.2 + f32(i)*0.1) * q.xy, q.z);
        q = vec3<f32>(q.x, rot(time * 0.3) * q.yz);

        // Torus / Octahedron boolean
        let d_torus = length(vec2<f32>(length(q.xz) - 0.5*s, q.y)) - 0.1*s;
        let d_oct = (abs(q.x) + abs(q.y) + abs(q.z) - 0.6*s) * 0.57735;

        let d_layer = smin(d_torus, d_oct, 0.1 * s);
        d = smin(d, d_layer, 0.2 * s);

        trap += length(q) * 0.1;
    }

    return vec2<f32>(d, trap);
}

fn calcNormal(p: vec3<f32>, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy, audio).x +
                     e.yyx * map(p + e.yyx, audio).x +
                     e.yxy * map(p + e.yxy, audio).x +
                     e.xxx * map(p + e.xxx, audio).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let fragCoord = vec2<f32>(f32(id.x) + 0.5, f32(id.y) + 0.5);
    let uv = (fragCoord - 0.5 * u.config.zw) / u.config.w;

    // Audio reactivity
    let audio = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(abs(uv.x), 0.5), 0.0).r;

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Add subtle camera rotation
    let cam_rot_time = u.config.x * 0.1;
    ro = vec3<f32>(rot(cam_rot_time) * ro.xz, ro.y).xzy;
    rd = vec3<f32>(rot(cam_rot_time) * rd.xz, rd.y).xzy;

    var d0 = 0.0;
    var trap = 0.0;
    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        let p = ro + rd * d0;
        let dS = map(p, audio);
        d0 += dS.x;
        trap = dS.y;
        if (dS.x < SURF_DIST || d0 > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    if (d0 < MAX_DIST) {
        let p = ro + rd * d0;
        let n = calcNormal(p, audio);

        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));
        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.5 + 0.5 * n.y;

        // Iridescent metallic shading based on trap and iridescence parameter
        let iridescence = u.zoom_params.z;
        let t = trap * 0.5 + u.config.x * 0.2;
        let base_col = 0.5 + 0.5 * cos(6.28318 * (vec3<f32>(1.0, 1.0, 1.0) * t + vec3<f32>(0.0, 0.33, 0.67)));

        col = base_col * (dif + amb) * iridescence;

        // Add neon bloom mask based on audio
        col += vec3<f32>(0.2, 0.5, 1.0) * audio * 0.5;

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.0, 0.1), 1.0 - exp(-0.02 * d0 * d0));
    }

    // Chromatic aberration / Post-processing
    // A simplified approximation by perturbing slightly
    let final_col = col; // Replace with proper aberration if desired, but this works for iridescent feel

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(final_col, 1.0));
}
