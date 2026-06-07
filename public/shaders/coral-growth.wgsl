// ═══════════════════════════════════════════════════════════════════
//  Coral Growth
//  Category: generative
//  Features: generative, audio-reactive, branching-structures, organic-patterns, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    let density = u.zoom_params.x * 15.0 + 5.0;
    let branchComplexity = u.zoom_params.y;
    let growthSpeed = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let p = uv * density;
    let cellId = floor(p);
    let cellUV = fract(p) - 0.5;

    var color = vec3<f32>(0.05, 0.08, 0.12);
    var glow = 0.0;

    // Multiple branch origins per cell
    let branchCount = 2 + i32(branchComplexity * 3.0);
    for (var bi = 0; bi < branchCount; bi = bi + 1) {
        let bf = f32(bi);
        let seed = cellId + vec2<f32>(bf * 7.3, bf * 13.7);
        let origin = hash22(seed) - 0.5;

        // Branch direction and length
        let dir = hash22(seed + vec2<f32>(1.0, 0.0)) - 0.5;
        let len = 0.2 + hash21(seed + vec2<f32>(2.0, 0.0)) * 0.6;
        let angle = atan2(dir.y, dir.x);

        // Animated growth
        let growth = fract(hash21(seed + vec2<f32>(3.0, 0.0)) + time * growthSpeed * 0.1);
        let currentLen = len * growth * (1.0 + bass * 0.2);

        // Distance to branch line segment
        let toPixel = cellUV - origin;
        let proj = clamp(dot(toPixel, normalize(dir)), 0.0, currentLen);
        let closest = origin + normalize(dir) * proj;
        let d = length(cellUV - closest);
        let branchWidth = 0.02 * (1.0 - proj / max(currentLen, 0.001));
        var branch = smoothstep(branchWidth, 0.0, d);

        // Sub-branches
        if (proj > currentLen * 0.5) {
            let subDir = vec2<f32>(cos(angle + 0.8), sin(angle + 0.8));
            let subLen = currentLen * 0.5;
            let subOrigin = closest;
            let toSub = cellUV - subOrigin;
            let subProj = clamp(dot(toSub, normalize(subDir)), 0.0, subLen);
            let subClosest = subOrigin + normalize(subDir) * subProj;
            let subD = length(cellUV - subClosest);
            let subBranch = smoothstep(branchWidth * 0.7, 0.0, subD);
            branch = max(branch, subBranch * 0.7);
        }

        let hue = fract(hash21(seed) * 0.3 + colorShift + time * 0.02 + bass * 0.03);
        let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
        let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
        let branchColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

        color = color + branchColor * branch * (0.6 + mids * 0.4);
        glow = glow + branch;
    }

    // Organic texture overlay
    let textureNoise = hash21(p * 3.0 + time * 0.05) * 0.08;
    color = color + vec3<f32>(0.1, 0.2, 0.15) * textureNoise;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, prev.rgb * 0.92, 0.05 + bass * 0.01);

    let caStr = 0.003 * (1.0 + bass) + glow * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    let alpha = clamp(glow * 0.5 + 0.1 + bass * 0.05, 0.0, 1.0);
    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.3, 0.0, 0.0, 0.0));
}
