// Prismatic Serpent River — braided chromatic creatures flowing through space.

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
    return vec3<f32>(0.50, 0.52, 0.54) + vec3<f32>(0.50, 0.48, 0.46) *
        cos(TAU * (vec3<f32>(1.0, 0.66, 0.39) * t + vec3<f32>(0.01, 0.30, 0.64)));
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
    let serpentCount = u.zoom_params.x;
    let flowSpeed = u.zoom_params.y;
    let bodyScale = u.zoom_params.z;
    let iridescence = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (4.5 + serpentCount * 3.5)) * u.zoom_config.w;
    let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDistance;
    p += dragTangent * dragMask * (0.06 + bodyScale * 0.18);

    let lanes = 3.0 + floor(serpentCount * 8.0);
    let speed = 0.6 + flowSpeed * 4.8 + audio.x * 0.5;
    let laneCoord = (p.y + 0.55) * lanes;
    let lane = floor(laneCoord);
    let laneY = fract(laneCoord) - 0.5;
    let slither = sin(p.x * (8.0 + bodyScale * 14.0) - time * speed + lane * 1.83) * (0.10 + bodyScale * 0.17);
    let bodyDistance = abs(laneY - slither);
    let body = exp(-bodyDistance * (22.0 + bodyScale * 42.0));
    let scalePhase = fract(p.x * (7.0 + bodyScale * 15.0) - time * speed * 0.42 + lane * 0.271);
    let scales = pow(0.5 + 0.5 * cos(scalePhase * TAU + laneY * 18.0), 10.0) * body;
    let eyePhase = fract(p.x * (2.0 + serpentCount * 4.0) - time * speed * 0.20 + lane * 0.131);
    let eyes = exp(-pow((eyePhase - 0.5) / 0.045, 2.0)) * exp(-bodyDistance * 85.0);
    let wake = exp(-abs(laneY - slither * 1.35) * 10.0) * (0.5 + 0.5 * sin(p.x * 30.0 - time * speed * 2.0));
    let finPhase = fract(p.x * (4.0 + bodyScale * 8.0) - time * speed * 0.28 + lane * 0.37);
    let prismFins = exp(-pow((finPhase - 0.5) / 0.075, 2.0)) * exp(-abs(bodyDistance - 0.055) * 42.0);
    let riverCurrent = pow(0.5 + 0.5 * sin(p.x * 12.0 + p.y * 19.0 - time * speed * 1.3), 14.0) * exp(-abs(laneY) * 2.5);

    var clickShed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(delta) - age * (0.18 + flowSpeed * 0.15));
            clickShed += (1.0 - smoothstep(0.0, 0.027, ring)) * (0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 11.0 - age * 7.0)) * (1.0 - age / 3.0);
        }
    }

    let hue = lane / max(lanes, 1.0) + scalePhase * iridescence + time * (0.04 + iridescence * 0.18);
    var hdr = palette(hue) * body * (0.8 + iridescence * 2.0 + audio.y);
    hdr += palette(hue + 0.32) * scales * (1.3 + audio.z);
    hdr += vec3<f32>(1.0, 0.85, 0.35) * eyes * (1.4 + audio.x);
    hdr += palette(hue + 0.65) * (wake * 0.35 + clickShed * 1.8 + dragMask * 0.8);
    hdr += palette(hue + 0.48) * (prismFins * 1.25 + riverCurrent * 0.18) * (0.5 + audio.z);
    let historyUV = clamp(uv - vec2<f32>((0.004 + flowSpeed * 0.010) / max(aspect, 0.001), sin(time + uv.x * 7.0) * 0.002), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + iridescence * 0.16 + dragMask * 0.14, 0.0, 0.42));
    let structure = clamp(body + scales * 0.5 + prismFins * 0.4 + eyes + clickShed * 0.5, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr), clamp(0.10 + structure * 0.88, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.12 + body * 0.58 + scales * 0.18 + eyes * 0.12, 0.0, 0.95), 0.0, 0.0, 0.0));
}
