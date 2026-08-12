// Gray-Scott-inspired state with directional advection and traveling feed fronts.

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let diffusionRate = 0.025 + u.zoom_params.x * 0.075;
    let feedRate = 0.018 + u.zoom_params.y * 0.052;
    let killRate = 0.035 + u.zoom_params.z * 0.045;
    let accumulationRate = u.zoom_params.w;

    // Rotate a one-pixel state conveyor to move the chemistry coherently.
    let flowDir = normalize(vec2<f32>(cos(time * 0.71), sin(time * 0.93)));
    let advectPixels = vec2<i32>(round(flowDir * (1.0 + u.zoom_params.x * 2.0)));
    let baseCoord = coord - advectPixels;
    let prev = historyLoad(baseCoord);
    let left = historyLoad(baseCoord + vec2<i32>(-1, 0));
    let right = historyLoad(baseCoord + vec2<i32>(1, 0));
    let up = historyLoad(baseCoord + vec2<i32>(0, -1));
    let down = historyLoad(baseCoord + vec2<i32>(0, 1));
    let laplacian = (left + right + up + down - 4.0 * prev) * 0.25;

    let input = textureLoad(readTexture, coord, 0);
    let seed = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    var a = clamp(max(prev.r, 0.75 + seed * 0.25), 0.0, 1.0);
    var b = clamp(prev.g + seed * 0.002, 0.0, 1.0);

    // Narrow analytic packets alternately feed and inhibit the reaction.
    let packetPhase = dot(uv, normalize(vec2<f32>(0.82, -0.57))) * 24.0 - time * (6.0 + u.zoom_params.y * 9.0);
    let packet = pow(0.5 + 0.5 * cos(packetPhase), 18.0);
    var front = 0.0;
    let aspect = resolution.x / resolution.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.19 + audio.y * 0.06));
            front += (1.0 - smoothstep(0.0, 0.022, ring)) * (1.0 - age / 3.0);
        }
    }
    let mouseSeed = smoothstep(0.09, 0.0, length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0))) * u.zoom_config.w;
    b = clamp(b + packet * (0.008 + audio.z * 0.012) + front * 0.12 + mouseSeed * 0.16, 0.0, 1.0);

    let reaction = a * b * b;
    let newA = clamp(a + diffusionRate * laplacian.r - reaction + feedRate * (1.0 - a), 0.0, 1.0);
    let newB = clamp(b + diffusionRate * 0.5 * laplacian.g + reaction - (killRate + feedRate) * b, 0.0, 1.0);
    let pattern = clamp(newA - newB, -1.0, 1.0);
    let color = vec3<f32>(
        smoothstep(-0.15, 0.55, pattern),
        smoothstep(0.05, 0.68, pattern + packet * 0.2),
        smoothstep(0.22, 0.82, pattern + front * 0.25)
    );
    let newAlpha = 1.0 - exp(-abs(pattern) * 2.0);
    let totalAlpha = clamp(prev.a * (0.90 + accumulationRate * 0.08) + newAlpha * accumulationRate * 0.2, 0.0, 1.0);
    let blendFactor = newAlpha * accumulationRate / max(totalAlpha, 0.001);
    let accumulatedColor = mix(prev.rgb, color, clamp(blendFactor, 0.0, 1.0));

    textureStore(dataTextureA, coord, vec4<f32>(newA, newB, 0.0, totalAlpha));
    textureStore(writeTexture, coord, vec4<f32>(clamp(accumulatedColor, vec3<f32>(0.0), vec3<f32>(1.0)), totalAlpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
