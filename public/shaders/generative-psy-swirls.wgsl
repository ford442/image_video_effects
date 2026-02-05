// ═══════════════════════════════════════════════════════════════
// Psychedelic Rainbow Swirls - PASS 1 of 1
// Generative multi-layer swirling vortex fields with spectral rainbow
// color cycles, procedural flow noise, temporal rotation, and psychedelic
// distortion. Purely generative with subtle image tinting.
// ═══════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=swirlSpeed, y=layers, z=rainbowSpeed, w=twistInt
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value += amp * noise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// Polar swirl transform
fn swirl(uv: vec2<f32>, center: vec2<f32>, strength: f32, time: f32) -> vec2<f32> {
    let dir = uv - center;
    let dist = length(dir);
    let angle = atan2(dir.y, dir.x);
    let swirl_angle = strength * exp(-dist * 3.0) * sin(dist * 10.0 - time);
    return center + vec2(cos(angle + swirl_angle), sin(angle + swirl_angle)) * dist;
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let sector = floor(hsv.x * 6.0);
    let i = fract(hsv.x * 6.0);
    let f = mix(vec3(1.0, 0.666, 0.333), vec3(0.0, 0.333, 0.666), i);
    let p = f - vec3(0.666, 0.333, 0.0);
    let q = f - vec3(0.333, 0.0, 0.666);
    let t = f;
    let rgb = mix(mix(p, q, fract(sector + 0.0)), mix(q, t, fract(sector + 1.0)), step(0.5, fract(sector + 2.0)));
    return rgb * hsv.y * hsv.z;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let params = u.zoom_params; // x=swirlSpeed, y=layers, z=rainbowSpeed, w=twistInt
    let mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let twist = params.w * (1.0 - depth * 0.5); // Depth reduces twist

    // Multi-layer swirls
    var swirl_uv = uv;
    let layer_count = round(params.y * 4.0) + 2.0;
    var flow = vec2(0.0);
    for (var i: i32 = 0; i < i32(layer_count); i = i + 1) {
        let layer_time = time * params.x * (1.0 + f32(i) * 0.3);
        let layer_scale = 1.0 + f32(i) * 0.5;
        let noise_flow = vec2(fbm(swirl_uv * layer_scale + vec2(layer_time)), fbm(swirl_uv * layer_scale * 1.1 + vec2(layer_time * 0.8)));
        flow += noise_flow * 0.2 / layer_scale;
        swirl_uv = swirl(swirl_uv, mouse + 0.1 * vec2(cos(layer_time), sin(layer_time)), twist * 0.1 * layer_scale, layer_time);
    }

    // Psychedelic rainbow hue from angle + flow + time
    let polar = vec2(length(swirl_uv - 0.5), atan2(swirl_uv.y - 0.5, swirl_uv.x - 0.5));
    let hue = fract(polar.y / 6.28318 + flow.x * 0.5 + time * params.z + polar.x * 0.1);
    let sat = 1.0;
    let val = 0.8 + 0.2 * sin(time * 3.0 + polar.x * 5.0);
    let rainbow = hsv2rgb(vec3(hue, sat, val));

    // Subtle image tinting
    let src = textureSampleLevel(readTexture, u_sampler, swirl_uv + flow * 0.02 * depth, 0.0);
    let color = mix(src.rgb * 0.3, rainbow, 0.7 + 0.3 * depth);

    // Glow trails from ripples
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let ripple_dist = length(uv - ripple.xy);
        if (ripple_dist < 0.2) {
            let ripple_hue = fract(ripple.z * 0.1 + time * 2.0);
            color += hsv2rgb(vec3(ripple_hue, 1.0, 1.0 - ripple_dist * 5.0)) * 0.5;
        }
    }

    textureStore(writeTexture, global_id.xy, vec4(color, 1.0));

    // Depth with swirl modulation
    let swirl_depth = depth + abs(flow.x + flow.y) * 0.2;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(swirl_depth, 0.0, 0.0, 0.0));
}
