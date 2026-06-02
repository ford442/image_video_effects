// ═══════════════════════════════════════════════════════════════════════════════
//  Lenia Cellular Automata
//  Category: simulation
//  Features: audio-reactive, temporal, chromatic-species, mouse-interactive,
//            continuous-life, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════════════════

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

fn growthKernel(x: f32) -> f32 {
    return exp(-pow((x - 0.5) / 0.15, 2.0) * 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Audio-driven parameters
    let radius = (u.zoom_params.x * 10.0 + 3.0) * (1.0 + mids * 0.2);
    let growthRate = u.zoom_params.y * 0.1 * (1.0 + bass * 0.3);
    let accumulationRate = u.zoom_params.z;
    let threshold = u.zoom_params.w * (1.0 - treble * 0.1);

    let pixelSize = 1.0 / u.config.zw;
    var neighborSum = 0.0;
    var weightSum = 0.0;

    // Larger neighborhood for more organic growth
    let neighRadius = i32(radius * 0.5 + 1.0);
    for (var y: i32 = -neighRadius; y <= neighRadius; y++) {
        for (var x: i32 = -neighRadius; x <= neighRadius; x++) {
            if (x == 0 && y == 0) { continue; }
            let offset = vec2<f32>(f32(x), f32(y)) * pixelSize;
            let dist = length(vec2<f32>(f32(x), f32(y)));
            let weight = 1.0 / (1.0 + dist * dist);
            let neighbor = textureSampleLevel(dataTextureC, u_sampler, uv + offset, 0.0);
            neighborSum += neighbor.r * weight;
            weightSum += weight;
        }
    }

    let avgNeighbor = neighborSum / max(weightSum, 0.001);
    let center = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

    // Lenia update rule with audio modulation
    let growth = growthKernel(avgNeighbor) * 2.0 - 1.0;
    let newValue = center + growthRate * growth;
    let clamped = clamp(newValue, 0.0, 1.0);
    let finalValue = smoothstep(threshold * 0.5, threshold, clamped);

    // Chromatic species: R, G, B channels evolve with different thresholds
    let rValue = smoothstep(threshold * 0.5 * 0.9, threshold * 0.9, clamped);
    let gValue = smoothstep(threshold * 0.5, threshold, clamped);
    let bValue = smoothstep(threshold * 0.5 * 1.1, threshold * 1.1, clamped);

    // Audio-driven color saturation
    let color = vec3<f32>(
        rValue * (0.7 + 0.3 * sin(finalValue * 3.14 + bass * 2.0)),
        gValue * (0.5 + 0.5 * sin(finalValue * 3.14 + 2.094 + mids * 2.0)),
        bValue * (0.8 + 0.2 * sin(finalValue * 3.14 + 4.188 + treble * 2.0))
    );

    // Temporal accumulation with advanced alpha
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let newAlpha = finalValue * (0.5 + bass * 0.1);
    let accumulatedAlpha = prev.a * (1.0 - accumulationRate * 0.05) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let finalColor = mix(prev.rgb, color, blendFactor);

    // Mouse interaction: inject life near cursor
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mDist = length(uv - mouse);
    let mouseInfluence = smoothstep(0.1, 0.0, mDist) * mouseDown * 0.5;
    let influencedColor = mix(finalColor, vec3<f32>(1.0, 0.9, 0.7), mouseInfluence);
    let influencedAlpha = clamp(totalAlpha + mouseInfluence, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(dataTextureA, coord, vec4<f32>(finalValue, finalValue, finalValue, influencedAlpha));
    textureStore(writeTexture, global_id.xy, vec4<f32>(influencedColor, influencedAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
