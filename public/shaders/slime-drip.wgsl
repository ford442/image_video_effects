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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Speed, y=Viscosity, z=Amount, w=Tint
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(vec2<f32>(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(0.5, 0.0))), f - vec2<f32>(0.0, 0.0)),
                   dot(vec2<f32>(hash12(i + vec2<f32>(1.0, 0.0)), hash12(i + vec2<f32>(1.5, 0.0))), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(vec2<f32>(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(0.5, 1.0))), f - vec2<f32>(0.0, 1.0)),
                   dot(vec2<f32>(hash12(i + vec2<f32>(1.0, 1.0)), hash12(i + vec2<f32>(1.5, 1.0))), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let speed = u.zoom_params.x * 2.0;
    let viscosity = u.zoom_params.y; // Controls scale of noise
    let amount = u.zoom_params.z;
    let tint_str = u.zoom_params.w;

    // Drip Logic
    // Vertical flow based on X and Time
    let noise_scale = mix(5.0, 20.0, viscosity);
    let flow = noise(vec2<f32>(uv.x * noise_scale, time * speed * 0.2));

    // Threshold flow to create "drips"
    let drip = smoothstep(0.4, 0.7, flow);

    // Distortion
    let y_offset = drip * 0.1 * amount;

    var sample_uv = uv + vec2<f32>(0.0, -y_offset);

    // Mouse Wipe
    let mouse_dist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    let wipe = smoothstep(0.2, 0.0, mouse_dist); // 1 at mouse, 0 away
    // Reduce distortion near mouse
    sample_uv = mix(sample_uv, uv, wipe);

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

    // Green Tint where dripping
    let tint_color = vec4<f32>(0.2, 1.0, 0.2, 1.0); // Slime Green
    // Strength of tint depends on drip amount and NOT wiped
    let tint_mask = drip * amount * (1.0 - wipe);

    color = mix(color, tint_color * color, tint_mask * tint_str);

    // Add specular highlight to slime
    if (tint_mask > 0.1) {
        color += vec4<f32>(0.2, 0.2, 0.2, 0.0) * tint_mask;
    }

    textureStore(writeTexture, global_id.xy, color);
}
