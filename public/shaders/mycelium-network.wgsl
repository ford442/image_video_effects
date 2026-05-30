// ═══════════════════════════════════════════════════════════════════
//  Mycelium Network
//  Category: generative
//  Features: generative, audio-reactive, branching-network, pulsing-nutrients, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
// ═══════════════════════════════════════════════════════════════════

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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let networkDensity = u.zoom_params.x * 12.0 + 4.0;
    let branchAngle = u.zoom_params.y * 1.5;
    let pulseSpeed = u.zoom_params.z * 3.0;
    let glowIntensity = u.zoom_params.w;

    let p = uv * networkDensity;
    let cellId = floor(p);
    let cellUV = fract(p) - 0.5;

    var color = vec3<f32>(0.03, 0.02, 0.04);
    var glow = 0.0;

    // Central trunk + branches per cell
    let seed = cellId;
    let trunkDir = hash22(seed) - 0.5;
    let trunkLen = 0.3 + hash21(seed + vec2<f32>(1.0, 0.0)) * 0.4;
    let branchCount = 2 + i32(hash21(seed + vec2<f32>(2.0, 0.0)) * 3.0);

    // Trunk
    let trunkEnd = trunkDir * trunkLen;
    let toTrunk = cellUV;
    let trunkProj = clamp(dot(toTrunk, normalize(trunkEnd)), 0.0, trunkLen);
    let trunkClosest = normalize(trunkEnd) * trunkProj;
    let trunkDist = length(cellUV - trunkClosest);
    let trunkWidth = 0.015;
    let trunk = smoothstep(trunkWidth, 0.0, trunkDist);

    // Nutrient pulse along trunk
    let pulsePos = fract(time * pulseSpeed * 0.1 + hash21(seed + vec2<f32>(3.0, 0.0)));
    let pulseDist = abs(trunkProj / max(trunkLen, 0.001) - pulsePos);
    let pulse = smoothstep(0.1, 0.0, pulseDist) * (1.0 + bass * 2.0);

    color = color + vec3<f32>(0.4, 0.8, 0.5) * trunk * (0.3 + mids * 0.3);
    color = color + vec3<f32>(1.0, 0.9, 0.6) * pulse * trunk;
    glow = glow + trunk + pulse * 2.0;

    // Branches
    for (var bi = 0; bi < branchCount; bi = bi + 1) {
        let bf = f32(bi);
        let bAngle = atan2(trunkEnd.y, trunkEnd.x) + (bf - 1.0) * branchAngle;
        let bDir = vec2<f32>(cos(bAngle), sin(bAngle));
        let bLen = trunkLen * (0.4 + hash21(seed + vec2<f32>(bf + 4.0, 0.0)) * 0.4);
        let bOrigin = trunkClosest;
        let bProj = clamp(dot(cellUV - bOrigin, bDir), 0.0, bLen);
        let bClosest = bOrigin + bDir * bProj;
        let bDist = length(cellUV - bClosest);
        let bWidth = trunkWidth * 0.6;
        let branch = smoothstep(bWidth, 0.0, bDist);

        // Tip glow
        let tipDist = abs(bProj - bLen);
        let tipGlow = smoothstep(0.05, 0.0, tipDist) * (1.0 + treble);

        let bPulsePos = fract(time * pulseSpeed * 0.15 + bf * 0.3);
        let bPulseDist = abs(bProj / max(bLen, 0.001) - bPulsePos);
        let bPulse = smoothstep(0.08, 0.0, bPulseDist) * (1.0 + bass);

        color = color + vec3<f32>(0.3, 0.7, 0.4) * branch * 0.5;
        color = color + vec3<f32>(0.8, 1.0, 0.7) * tipGlow * branch * glowIntensity;
        color = color + vec3<f32>(1.0, 0.95, 0.7) * bPulse * branch;
        glow = glow + branch + tipGlow * 0.5 + bPulse;
    }

    // Spore clouds at intersections
    let spore = hash21(cellId + vec2<f32>(time * 0.1, 0.0));
    let sporeMask = step(0.97, spore) * smoothstep(0.3, 0.0, length(cellUV));
    color = color + vec3<f32>(0.6, 0.9, 0.7) * sporeMask * glowIntensity;
    glow = glow + sporeMask;

    let alpha = clamp(glow * 0.4 + 0.1 + bass * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.3, 0.0, 0.0, 0.0));
}
