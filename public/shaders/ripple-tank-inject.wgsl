// ═══ RIPPLE TANK — GRAPH NODE: SOURCE INJECTION ════════════════════════════
//  Tier C graph: mouse driver, click ripples, audio-reactive rain.
//
//  Reads dataTextureC (binding 9, host copies dataA→C before dispatch),
//  writes dataTextureB (binding 8).

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash2f(n: f32) -> vec2<f32> {
    return vec2<f32>(hashf(n), hashf(n + 73.156));
}

fn splash(distSq: f32, radius: f32) -> f32 {
    let d = sqrt(distSq) / radius;
    return smoothstep(1.0, 0.0, d) * cos(d * PI * 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv     = vec2<f32>(pixel) / res;
    let aspect = vec2<f32>(res.x / res.y, 1.0);
    let time   = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sourceStrength = mix(0.15, 1.5, u.zoom_params.z) * (1.0 + bass * 0.6);
    let driverFreq     = mix(4.0, 18.0, u.zoom_params.z) * (1.0 + treble * 0.5);

    let state = textureLoad(dataTextureC, pixel, 0);
    var height   = state.r;
    var velocity = state.g;
    var phase    = state.a;
    let prevHeight = state.b;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let dm = (uv - mouse) * aspect;
    let mouseDistSq = dot(dm, dm);
    let mouseRadius = 0.018;
    if (mouseDown && mouseDistSq < mouseRadius * mouseRadius) {
        phase += driverFreq * 0.016;
        let drive = sin(phase * TAU) * sourceStrength * 0.4;
        height += drive * splash(mouseDistSq, mouseRadius);
    }
    phase = fract(phase);

    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z <= 0.0) { continue; }
        let age = time - ripple.z;
        if (age < 0.0 || age > 0.1) { continue; }
        let dr = (uv - ripple.xy) * aspect;
        let distSq = dot(dr, dr);
        let radius = 0.02;
        if (distSq < radius * radius) {
            let punch = (1.0 - age / 0.1) * sourceStrength * ripple.w;
            height -= punch * 0.5 * splash(distSq, radius);
        }
    }

    let dripRate = 0.7 + treble * 0.9;
    for (var d = 0; d < 2; d++) {
        let t = time * dripRate + f32(d) * 0.5;
        let cell = floor(t);
        let age  = fract(t) / dripRate;
        let pos  = hash2f(cell * 7.31 + f32(d) * 91.7) * 0.8 + vec2<f32>(0.1);
        if (age < 0.08) {
            let dd = (uv - pos) * aspect;
            let distSq = dot(dd, dd);
            let radius = 0.014;
            if (distSq < radius * radius) {
                let amp = sourceStrength * 0.25 * (0.35 + mids * 0.8);
                height -= amp * splash(distSq, radius) * (1.0 - age / 0.08);
            }
        }
    }

    height   = clamp(height, -1.5, 1.5);
    velocity = clamp(velocity, -0.8, 0.8);

    textureStore(dataTextureB, pixel, vec4<f32>(height, velocity, prevHeight, phase));
}
