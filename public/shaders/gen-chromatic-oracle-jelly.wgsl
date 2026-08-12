// Chromatic Oracle Jelly — drifting bells, watching eyes, and luminous tentacles.

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

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52, 0.50, 0.54) + vec3<f32>(0.48, 0.49, 0.46) *
        cos(TAU * (vec3<f32>(1.0, 0.70, 0.45) * t + vec3<f32>(0.02, 0.27, 0.58)));
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
    let swarmDensity = u.zoom_params.x;
    let driftSpeed = u.zoom_params.y;
    let tentacleCurl = u.zoom_params.z;
    let oracleChroma = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (4.0 + swarmDensity * 5.0)) * u.zoom_config.w;
    p -= mouseDelta / mouseDistance * dragMask * (0.05 + tentacleCurl * 0.16);

    let gridScale = 2.5 + floor(swarmDensity * 6.0);
    let drift = time * (0.15 + driftSpeed * 1.5 + audio.y * 0.12);
    let gridP = vec2<f32>((p.x + 1.0) * gridScale, (p.y + drift * 0.13 + 1.0) * gridScale);
    let cell = floor(gridP);
    var local = fract(gridP) - 0.5;
    let seed = hash21(cell);
    local.x += sin(drift + seed * TAU + cell.y) * (0.06 + tentacleCurl * 0.12);
    local.y += cos(drift * 0.7 + seed * 4.0) * 0.05;
    let bellDistance = length(vec2<f32>(local.x * 1.05, max(local.y + 0.08, 0.0) * 1.5));
    let bell = smoothstep(0.42, 0.25, bellDistance) * smoothstep(0.32, -0.22, local.y);
    let rim = exp(-abs(bellDistance - 0.34) * (35.0 + swarmDensity * 25.0)) * smoothstep(0.30, -0.12, local.y);
    let eyeDistance = length((local - vec2<f32>(0.0, -0.07)) * vec2<f32>(1.0, 1.7));
    let eye = exp(-eyeDistance * 22.0) * bell;
    let pupil = exp(-eyeDistance * (65.0 + oracleChroma * 45.0));
    let tentaclePhase = local.x * (18.0 + tentacleCurl * 30.0) + sin(local.y * 12.0 - drift * 3.0) * (1.0 + tentacleCurl * 3.0);
    let tentacles = pow(0.5 + 0.5 * cos(tentaclePhase), 12.0) * smoothstep(-0.08, 0.48, local.y) * exp(-abs(local.x) * 2.2);
    let oracleAngle = atan2(local.y + 0.07, local.x);
    let oracleSigil = pow(0.5 + 0.5 * cos(oracleAngle * (7.0 + floor(swarmDensity * 6.0)) + drift * 2.0), 14.0) *
        exp(-abs(eyeDistance - 0.15) * (45.0 + oracleChroma * 25.0));
    let deepBell = exp(-abs(bellDistance - 0.48) * 28.0) * (0.5 + 0.5 * sin(drift + seed * TAU));

    var clickOracle = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.1) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(delta) - age * (0.16 + driftSpeed * 0.16));
            clickOracle += (1.0 - smoothstep(0.0, 0.030, ring)) * (1.0 - age / 3.1);
        }
    }

    let hue = seed + oracleChroma * 0.55 + local.y * 0.35 + time * (0.04 + driftSpeed * 0.10);
    var hdr = palette(hue) * bell * (0.6 + oracleChroma * 2.1 + audio.y);
    hdr += palette(hue + 0.34) * (rim * 1.7 + tentacles * (0.7 + audio.z));
    hdr += vec3<f32>(1.0, 0.85, 0.40) * eye * (0.6 + audio.x) - vec3<f32>(0.3, 0.05, 0.45) * pupil;
    hdr += palette(hue + 0.48) * (oracleSigil * 1.2 + deepBell * 0.42) * (0.5 + audio.z);
    hdr += palette(hue + 0.68) * (clickOracle * 1.8 + dragMask * 0.9);
    let historyUV = clamp(uv + vec2<f32>(sin(drift + uv.y * 9.0) * 0.002, 0.003 + driftSpeed * 0.008), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + oracleChroma * 0.16 + dragMask * 0.14, 0.0, 0.42));
    let structure = clamp(bell * 0.65 + rim * 0.5 + tentacles * 0.45 + oracleSigil * 0.35 + eye + clickOracle * 0.45, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), clamp(0.10 + structure * 0.88, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.10 + bell * 0.48 + rim * 0.20 + eye * 0.18, 0.0, 0.95), 0.0, 0.0, 0.0));
}
