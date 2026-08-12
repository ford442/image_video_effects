// Cosmic Velvet Hypnosis — soft spiral wells, chromatic runners, and click halos.

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

const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.50, 0.47, 0.55) + vec3<f32>(0.50, 0.52, 0.45) *
        cos(TAU * (vec3<f32>(1.0, 0.72, 0.46) * t + vec3<f32>(0.0, 0.25, 0.59)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let spiralArms = u.zoom_params.x;
    let spinRate = u.zoom_params.y;
    let velvetSoftness = u.zoom_params.z;
    let saturation = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (3.5 + spiralArms * 5.0)) * u.zoom_config.w;
    let tangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDistance;
    p += tangent * dragMask * (0.08 + velvetSoftness * 0.20);

    let radius = max(length(p), 0.002);
    let angle = atan2(p.y, p.x);
    let arms = 3.0 + floor(spiralArms * 10.0);
    let spin = time * (0.25 + spinRate * 2.8 + audio.x * 0.25);
    let spiralPhase = angle * arms + log(radius + 0.035) * (5.0 + velvetSoftness * 8.0) - spin * arms;
    let velvet = pow(0.5 + 0.5 * cos(spiralPhase), mix(12.0, 2.5, velvetSoftness));
    let rings = pow(0.5 + 0.5 * sin(radius * (28.0 + spiralArms * 34.0) - spin * 7.0), 8.0);
    let runnerPhase = fract(angle / TAU * arms + radius * (3.0 + spiralArms * 7.0) - time * (0.6 + spinRate * 3.0));
    let runner = exp(-pow((runnerPhase - 0.5) / 0.07, 2.0)) * velvet;
    let core = exp(-radius * (6.0 + velvetSoftness * 6.0));
    let counterSpiral = pow(0.5 + 0.5 * sin(angle * (arms + 2.0) - log(radius + 0.03) * 7.0 + spin * 0.73), mix(10.0, 3.0, velvetSoftness));
    let moire = pow(0.5 + 0.5 * cos(spiralPhase * 0.55 - angle * 3.0 + time * (0.4 + spinRate)), 14.0) * counterSpiral;

    var clickHalo = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.2) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(delta) - age * (0.17 + spinRate * 0.14));
            clickHalo += (1.0 - smoothstep(0.0, 0.032 + velvetSoftness * 0.018, ring)) * (1.0 - age / 3.2);
        }
    }

    let hue = angle / TAU + radius * 0.7 + saturation * 0.35 + time * (0.03 + spinRate * 0.12);
    var hdr = palette(hue) * velvet * (0.6 + saturation * 2.5 + audio.y);
    hdr += palette(hue + 0.36) * rings * (0.25 + runner * 1.8 + audio.z * 0.45);
    hdr += palette(hue + 0.51) * (counterSpiral * 0.42 + moire * 0.85) * (0.5 + audio.y);
    hdr += palette(hue + 0.68) * clickHalo * 1.9;
    hdr += vec3<f32>(0.85, 0.25, 1.0) * (core * (0.7 + audio.x) + dragMask * 0.9);
    let radialDirection = p / radius;
    let historyUV = clamp(uv - vec2<f32>(radialDirection.x / max(aspect, 0.001), radialDirection.y) * (0.003 + spinRate * 0.007) + vec2<f32>(-radialDirection.y / max(aspect, 0.001), radialDirection.x) * 0.002, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + velvetSoftness * 0.19 + dragMask * 0.12, 0.0, 0.42));
    let structure = clamp(velvet * 0.7 + counterSpiral * 0.28 + rings * 0.35 + runner + clickHalo * 0.45 + core * 0.4, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr), clamp(0.12 + structure * 0.86, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.12 + velvet * 0.48 + rings * 0.22 + core * 0.18, 0.0, 0.95), 0.0, 0.0, 0.0));
}
