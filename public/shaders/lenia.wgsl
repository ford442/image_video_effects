// Lenia-inspired continuous cellular field with advected growth packets.

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

fn historyLoad(pixel: vec2<i32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

fn growthKernel(x: f32) -> f32 {
    return exp(-0.5 * pow((x - 0.5) / 0.15, 2.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let radius = 3.0 + u.zoom_params.x * 10.0;
    let growthRate = (0.008 + u.zoom_params.y * 0.085) * (1.0 + audio.x * 0.35);
    let accumulationRate = u.zoom_params.z;
    let threshold = mix(0.18, 0.72, u.zoom_params.w) * (1.0 - audio.z * 0.08);

    // A smooth conveyor shifts the sampled state; it never hashes the frame.
    let conveyor = vec2<f32>(cos(time * 1.17), sin(time * 0.83));
    let driftPixels = vec2<i32>(round(conveyor * (1.0 + u.zoom_params.y * 3.0)));
    let advectedCoord = coord - driftPixels;
    var neighborSum = 0.0;
    var weightSum = 0.0;
    let neighRadius = i32(radius * 0.5 + 1.0);
    for (var y = -neighRadius; y <= neighRadius; y = y + 1) {
        for (var x = -neighRadius; x <= neighRadius; x = x + 1) {
            if (x == 0 && y == 0) { continue; }
            let delta = vec2<f32>(f32(x), f32(y));
            let weight = 1.0 / (1.0 + dot(delta, delta));
            neighborSum += historyLoad(advectedCoord + vec2<i32>(x, y)).r * weight;
            weightSum += weight;
        }
    }

    let prev = historyLoad(coord);
    let center = historyLoad(advectedCoord).r;
    let avgNeighbor = neighborSum / max(weightSum, 0.001);
    let packetPhase = dot(uv, normalize(vec2<f32>(1.0, 0.63))) * (18.0 + radius) - time * (5.0 + u.zoom_params.y * 10.0);
    let growthPacket = pow(0.5 + 0.5 * sin(packetPhase), 12.0) * (0.025 + audio.y * 0.05);

    var clickFront = 0.0;
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.16 + audio.x * 0.08));
            clickFront += (1.0 - smoothstep(0.0, 0.025, ring)) * (1.0 - age / 3.0);
        }
    }

    let mouseDist = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
    let inoculation = smoothstep(0.11, 0.0, mouseDist) * u.zoom_config.w * 0.32;
    let growth = growthKernel(avgNeighbor) * 2.0 - 1.0;
    let clamped = clamp(center + growthRate * growth + growthPacket + clickFront * 0.10 + inoculation, 0.0, 1.0);
    let finalValue = smoothstep(threshold * 0.5, max(threshold, 0.01), clamped);

    let species = vec3<f32>(
        smoothstep(threshold * 0.42, threshold * 0.90, clamped),
        smoothstep(threshold * 0.50, threshold, clamped),
        smoothstep(threshold * 0.58, threshold * 1.10, clamped)
    );
    let color = species * (0.55 + 0.45 * sin(vec3<f32>(0.0, 2.094, 4.188) + finalValue * 3.14159 + audio * 2.0));
    let newAlpha = clamp(finalValue * (0.55 + audio.x * 0.10) + clickFront * 0.15, 0.0, 1.0);
    let totalAlpha = clamp(prev.a * (0.94 - accumulationRate * 0.05) + newAlpha * accumulationRate, 0.0, 1.0);
    let blendFactor = newAlpha * accumulationRate / max(totalAlpha, 0.001);
    let finalColor = mix(prev.rgb, color, clamp(blendFactor, 0.0, 1.0));
    let influencedAlpha = clamp(totalAlpha + inoculation, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(dataTextureA, coord, vec4<f32>(finalValue, finalValue, finalValue, influencedAlpha));
    textureStore(writeTexture, coord, vec4<f32>(clamp(finalColor + clickFront * vec3<f32>(0.25, 0.12, 0.05), vec3<f32>(0.0), vec3<f32>(1.0)), influencedAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
