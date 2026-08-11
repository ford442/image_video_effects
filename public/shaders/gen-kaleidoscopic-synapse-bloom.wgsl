// Kaleidoscopic Synapse Bloom — psychedelic neural petals with drag memory.

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
    return vec3<f32>(0.55, 0.48, 0.52) + vec3<f32>(0.45, 0.50, 0.48) *
        cos(TAU * (vec3<f32>(1.0, 0.73, 0.47) * t + vec3<f32>(0.02, 0.28, 0.61)));
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
    let bloomDensity = u.zoom_params.x;
    let pulseSpeed = u.zoom_params.y;
    let neuralWarp = u.zoom_params.z;
    let colorFlux = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let tangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDistance;
    let dragMask = exp(-mouseDistance * (5.0 + bloomDensity * 4.0)) * u.zoom_config.w;
    p += tangent * dragMask * (0.10 + neuralWarp * 0.22);

    let radius = max(length(p), 0.002);
    let angle = atan2(p.y, p.x);
    let sectors = 5.0 + floor(bloomDensity * 8.0);
    let foldedAngle = abs(fract(angle / TAU * sectors + 0.5) - 0.5) * 2.0;
    let pulse = time * (1.5 + pulseSpeed * 7.0 + audio.x * 1.5);
    let axon = 0.5 + 0.5 * sin(radius * (32.0 + neuralWarp * 48.0) - pulse + foldedAngle * 17.0);
    let branch = pow(1.0 - abs(2.0 * fract(foldedAngle * (2.0 + neuralWarp * 4.0) + log(radius + 0.03) * 1.7 - time * 0.18) - 1.0), 8.0);
    let runnerPhase = fract(radius * (5.0 + bloomDensity * 8.0) - time * (0.8 + pulseSpeed * 2.8));
    let runner = exp(-pow((runnerPhase - 0.5) / 0.075, 2.0));
    let nodes = pow(axon, 12.0) * (0.35 + branch * 1.8) + branch * (0.18 + runner * 1.5);
    // A counter-rotating dendrite web keeps the second pass visually independent
    // from the radial axon runner instead of merely brightening it.
    let counterPhase = angle * (sectors + 3.0) - log(radius + 0.025) * (7.0 + neuralWarp * 7.0) + pulse * 0.72;
    let dendrites = pow(0.5 + 0.5 * cos(counterPhase), 18.0) * exp(-radius * (0.8 + bloomDensity));
    let synapseBridge = exp(-abs(fract(radius * (9.0 + bloomDensity * 12.0) + foldedAngle * 2.0 + time * pulseSpeed) - 0.5) * 20.0) * dendrites;

    var clickBloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.20 + pulseSpeed * 0.12));
            clickBloom += (1.0 - smoothstep(0.0, 0.025, ring)) * (1.0 - age / 3.0);
        }
    }

    let hue = radius * 0.8 + foldedAngle * 0.42 + time * (0.05 + colorFlux * 0.22) + audio.y * 0.2;
    var hdr = palette(hue) * nodes * (1.1 + colorFlux * 2.4 + audio.z);
    hdr += palette(hue + 0.35) * runner * branch * (0.6 + audio.x);
    hdr += palette(hue + 0.52) * (dendrites * 0.65 + synapseBridge * 1.4) * (0.6 + audio.y);
    hdr += palette(time * 0.1 + clickBloom) * clickBloom * 1.8;
    hdr += palette(hue + 0.6) * dragMask * (0.5 + neuralWarp * 1.5);
    let historyUV = clamp(uv - normalize(p + vec2<f32>(0.0001)) * (0.003 + pulseSpeed * 0.008), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.12 + neuralWarp * 0.16 + dragMask * 0.16, 0.0, 0.42));
    let alpha = clamp(0.12 + nodes * 0.75 + dendrites * 0.28 + clickBloom * 0.45 + dragMask * 0.35, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr), alpha);
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    let depth = clamp(0.16 + branch * 0.34 + runner * 0.25 + dendrites * 0.18 + clickBloom * 0.18, 0.0, 0.95);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
