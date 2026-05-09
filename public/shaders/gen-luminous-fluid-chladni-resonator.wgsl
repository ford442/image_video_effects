// ----------------------------------------------------------------
// Luminous-Fluid Chladni-Resonator
// Category: generative
// ----------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=FacetCount, y=BevelWidth, z=Unused, w=Unused
    ripples: array<vec4<f32>, 50>,
};

fn chladni(uv: vec2<f32>, n: f32, m: f32, t: f32) -> f32 {
    let pi = 3.14159265;
    let term1 = sin(n * pi * uv.x) * sin(m * pi * uv.y);
    let term2 = sin(m * pi * uv.x) * sin(n * pi * uv.y);
    return cos(t) * term1 + sin(t) * term2;
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var curr_p = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(curr_p);
        curr_p = rot * curr_p * vec2<f32>(2.0) + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));
    if (coord.x >= res.x || coord.y >= res.y) { return; }

    let uv = coord / res;
    let t = u.config.x * 0.5;
    let audio = u.config.y;

    let param_n = u.zoom_params.x;
    let param_m = u.zoom_params.y;
    let param_fluid = u.zoom_params.z;
    let param_glow = u.zoom_params.w;

    // Fluid distortion
    let dist = vec2<f32>(fbm(uv * vec2<f32>(5.0) + vec2<f32>(t)), fbm(uv * vec2<f32>(5.0) - vec2<f32>(t)));
    let uv_dist = uv + (dist - vec2<f32>(0.5)) * vec2<f32>(param_fluid * 0.1 * (1.0 + audio * 0.5));

    // Audio modulated modes
    let n = param_n + audio * 2.0 * sin(t);
    let m = param_m + audio * 2.0 * cos(t);

    // Chladni value
    let c_val = chladni(uv_dist * vec2<f32>(2.0) - vec2<f32>(1.0), n, m, t * 2.0);

    // Mouse dampening
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z) / res;
    let d_mouse = distance(uv, mouse_uv);
    let damp = smoothstep(0.0, 0.2, d_mouse);

    let final_val = abs(c_val) * damp;

    // Map to color (nodes are where final_val ~ 0)
    let intensity = smoothstep(0.1, 0.0, final_val) * param_glow * (1.0 + audio);

    // Plasma color
    let p_idx = u32(clamp(intensity * 255.0, 0.0, 255.0));
    let col = plasmaBuffer[p_idx % 256u].rgb * intensity;

    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}