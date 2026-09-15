// ═══════════════════════════════════════════════════════════════════
//  Aetherial Plasma Loom
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: alternating heddle lanes; plasma shuttle necking
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn map(p: vec3<f32>) -> vec3<f32> {
    var pos = p;

    // Mouse Interaction
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 2.0, (u.zoom_config.z - 0.5) * 2.0, 0.0);
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

    let strand_angle = atan2(pos.y, pos.x);

    // Idea 1: alternating heddle lanes lift neighboring warp strands over/under.
    let heddle = 0.5 + 0.5 * sin(strand_angle * 8.0 + pos.z * 1.7 - flow * 1.4);
    let heddle_offset = (heddle - 0.5) * 0.16 * (0.4 + twist_amount * 0.15);

    // Idea 2: a longitudinal shuttle pinches the ribbon and leaves bright knots.
    let shuttle_phase = 0.5 + 0.5 * cos(pos.z * 3.2 - flow * 2.8 + strand_angle);
    let shuttle = pow(shuttle_phase, 8.0);
    let neck = 1.0 - shuttle * 0.38;

    let d_ribbon = length(pos.xy) - 1.0 + fbm_val * twist_amount * 0.35 + heddle_offset;
    let thickness = (0.055 + 0.07 * heddle) * neck;
    return vec3<f32>(abs(d_ribbon) - thickness, heddle, shuttle);
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

    let audio = plasmaBuffer[0].xyz;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(clip, 1.0));

    // Density integration loop
    var t = 0.0;
    var density = 0.0;
    var heddle_light = 0.0;
    var shuttle_light = 0.0;
    var first_depth = 10.0;
    let max_steps = 60;

    let density_param = u.zoom_params.x;

    for (var i = 0; i < max_steps; i++) {
        let p = ro + rd * t;
        let sample = map(p);
        let d = sample.x;

        if (d < 0.1) {
            let contribution = (0.1 - d) * density_param * (1.0 + audio.x * 0.35);
            density += contribution;
            heddle_light += contribution * sample.y;
            shuttle_light += contribution * sample.z;
            first_depth = min(first_depth, t);
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
        let col = palette(normalized_density + u.config.x * 0.1 + audio.y * 0.04);
        let weave_color = mix(vec3<f32>(0.15, 0.35, 1.0), vec3<f32>(1.0, 0.18, 0.75),
            clamp(heddle_light / max(density, 0.001), 0.0, 1.0));
        let shuttle_knot = clamp(shuttle_light / max(density, 0.001), 0.0, 1.0);
        final_color = (col + weave_color * 0.45) * density * core_bright * 0.045;
        final_color += vec3<f32>(1.0, 0.78, 0.3) * shuttle_knot * core_bright *
            (0.15 + audio.z * 0.08);
    }

    // Subtle background
    final_color += vec3<f32>(0.05, 0.0, 0.1) * (1.0 - length(clip));

    let normalized_density = clamp(density * 0.1, 0.0, 1.0);
    let display = vec4<f32>(
        acesToneMap(max(final_color, vec3<f32>(0.0))),
        clamp(normalized_density * 0.8 + shuttle_light * 0.08, 0.0, 1.0)
    );
    let coord = vec2<i32>(id.xy);
    let source_depth = textureLoad(readDepthTexture, coord, 0).r;
    let has_volume = first_depth < 10.0;
    let depth = select(source_depth, clamp(1.0 - first_depth / 10.0, 0.0, 1.0), has_volume);
    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}
