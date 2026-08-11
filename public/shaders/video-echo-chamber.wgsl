// Video echo chamber with orbiting history conveyors and click-launched echoes.

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

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

fn rotate2(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let globalDecay = mix(0.82, 0.995, u.zoom_params.x);
    let mouseRadius = mix(0.03, 0.35, u.zoom_params.y);
    let echoStrength = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    let current = textureLoad(readTexture, coord, 0);
    let prev = historyLoadUV(uv);

    let center = u.zoom_config.yz;
    let local = uv - center;
    let mouseMask = smoothstep(mouseRadius, mouseRadius * 0.15, length(local));
    let orbit = (0.004 + echoStrength * 0.018) * (0.35 + mouseMask * (0.65 + u.zoom_config.w));
    let angle = time * (1.8 + audio.y * 1.5);
    let orbitUV = center + rotate2(local, orbit * sin(angle)) / (1.0 - orbit * cos(angle));

    // A second directional conveyor creates horizontal chromatic afterimages.
    let runner = pow(0.5 + 0.5 * sin(uv.y * 42.0 - time * (7.0 + audio.x * 4.0)), 14.0);
    let streak = vec2<f32>((0.003 + runner * 0.018) * (1.0 + echoStrength), 0.0);
    let echoR = historyLoadUV(orbitUV - streak * (1.0 + colorShift)).r;
    let echoG = historyLoadUV(orbitUV).g;
    let echoB = historyLoadUV(orbitUV + streak * (1.0 + colorShift)).b;
    var echoColor = vec3<f32>(echoR, echoG, echoB);

    var clickEcho = 0.0;
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.22 + audio.z * 0.08));
            clickEcho += (1.0 - smoothstep(0.0, 0.028, ring)) * (1.0 - age / 2.8);
        }
    }
    echoColor += clickEcho * vec3<f32>(0.30, 0.12, 0.42);
    let historyWeight = echoStrength * globalDecay * (0.45 + runner * 0.25);
    let blended = mix(current.rgb, echoColor, clamp(historyWeight + clickEcho * 0.18, 0.0, 0.92));
    let brightness = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let newAlpha = clamp(mix(current.a, brightness * mix(1.0, 0.65 + depth * 0.35, echoStrength), echoStrength), 0.0, 1.0);
    let alpha = clamp(prev.a * globalDecay * echoStrength + newAlpha * (1.0 - echoStrength * 0.45), 0.0, 1.0);
    let output = vec4<f32>(clamp(blended, vec3<f32>(0.0), vec3<f32>(1.0)), alpha);

    textureStore(dataTextureA, coord, output);
    textureStore(writeTexture, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
