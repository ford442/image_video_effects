// ----------------------------------------------------------------
// Aetherial Plasma Loom
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
  zoom_params: vec4<f32>,  // .x = Density, .y = Flow Speed, .z = Twist, .w = Core Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash13(p3: vec3<f32>) -> f32 {
    var p = fract(p3 * 0.1031);
    p += dot(p, p.yzx + vec3<f32>(33.33));
    return fract((p.x + p.y) * p.z);
}

// 3D noise (value noise)
fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let res = mix(
        mix(mix(hash13(p), hash13(p + vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(hash13(p + vec3<f32>(0.0, 1.0, 0.0)), hash13(p + vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
        mix(mix(hash13(p + vec3<f32>(0.0, 0.0, 1.0)), hash13(p + vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(hash13(p + vec3<f32>(0.0, 1.0, 1.0)), hash13(p + vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y), f2.z
    );
    return res;
}

fn fbm3(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += amp * noise3(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

fn rotZ(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;

    // Mouse Interaction
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 2.0, -(u.zoom_config.z - 0.5) * 2.0, 0.0);
    let d_mouse = length(pos.xy - mouse_pos.xy);

    // Twist
    let twist_amount = u.zoom_params.z;
    let angle = twist_amount / (d_mouse + 0.1);

    if (u.zoom_config.w > 0.0) {
        let rz = rotZ(angle);
        let xy = rz * pos.xy;
        pos = vec3<f32>(xy.x, xy.y, pos.z);
    }

    // FBM domain warping
    let flow = u.config.x * u.zoom_params.y;
    let fbm_val = fbm3(pos * 0.5 + vec3<f32>(0.0, 0.0, flow));

    // Create ribbons
    let d_ribbon = length(pos.xy) - 1.0 + fbm_val * twist_amount;

    // Return distance
    return abs(d_ribbon) - 0.1;
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = vec2<f32>(f32(id.x) / resolution.x, f32(id.y) / resolution.y);
    let aspect = resolution.x / resolution.y;
    let clip = (uv * 2.0 - vec2<f32>(1.0)) * vec2<f32>(aspect, 1.0);

    // Audio Reactivity
    let audio_val = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(uv.x, 0.5), 0.0).r;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(clip, 1.0));

    // Density integration loop
    var t = 0.0;
    var density = 0.0;
    let max_steps = 60;

    let density_param = u.zoom_params.x;

    for (var i = 0; i < max_steps; i++) {
        let p = ro + rd * t;
        let d = map(p);

        if (d < 0.1) {
            density += (0.1 - d) * density_param * (1.0 + audio_val * 0.5);
        }

        t += max(d * 0.5, 0.02);

        if (t > 10.0) {
            break;
        }
    }

    // Color mapping
    let core_bright = u.zoom_params.w;
    var final_color = vec3<f32>(0.0);

    if (density > 0.0) {
        let normalized_density = clamp(density * 0.1, 0.0, 1.0);
        let col = palette(normalized_density + u.config.x * 0.1);
        final_color = col * density * core_bright * 0.05;
    }

    // Subtle background
    final_color += vec3<f32>(0.05, 0.0, 0.1) * (1.0 - length(clip));

    textureStore(writeTexture, id.xy, vec4<f32>(final_color, 1.0));
}
