// ═══════════════════════════════════════════════════════════════════
//  Crystalline Fracture v2
//  Category: generative
//  Features: audio-reactive, fracture-mechanics, stress-intensity,
//            crack-propagation, iridescence, subsurface-scatter, upgraded-rgba, aces-tone-map
//  Complexity: Very High
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let cellCount = mix(3.0, 15.0, u.zoom_params.x) * (1.0 + depth * 0.5);
    let edgeGlow = u.zoom_params.y;
    let fractureAmt = u.zoom_params.z;
    let chromatic = u.zoom_params.w * 0.02;

    let aspect = res.x / res.y;
    let p = uv * vec2<f32>(aspect, 1.0) * cellCount;
    let cellId = floor(p);
    let cellUV = fract(p);

    // Stress field: bass loading + mouse point stress + temporal crack memory
    let mouseDist = length(uv - mouse);
    let mouseField = exp(-mouseDist * mouseDist * 20.0) * u.zoom_config.w;
    let mouseStress = smoothstep(0.15, 0.0, mouseDist) * u.zoom_config.w * 4.0;
    var stress = bass * 2.0 + mouseStress + mouseField * 2.0 + prev.r * 0.5;

    // Fracture toughness from mids
    let toughness = 0.4 + mids * 0.6;

    // Catastrophic failure events triggered by treble
    let catastrophic = step(0.8, treble) * 2.0;
    stress = stress + catastrophic;

    // Percolation connectivity boost from neighboring cracks
    let connectivity = smoothstep(0.3, 0.7, prev.g);
    stress = stress + connectivity * 0.3;

    // Time-evolving Voronoi crystal cells
    var minDist = 1e9;
    var secondMinDist = 1e9;
    var nearestId = vec2<f32>(0.0);
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let nid = cellId + vec2<f32>(f32(x), f32(y));
            let center = hash22(nid + vec2<f32>(time * 0.01 * fractureAmt, 0.0)) + vec2<f32>(f32(x), f32(y));
            let d = length(cellUV - center);
            if (d < minDist) {
                secondMinDist = minDist;
                minDist = d;
                nearestId = nid;
            } else if (d < secondMinDist) {
                secondMinDist = d;
            }
        }
    }

    let edgeDist = secondMinDist - minDist;
    let edge = smoothstep(0.05, 0.0, edgeDist);

    // Stress intensity factor K drives crack propagation
    let crackSpeed = 0.1 + bass * 0.2;
    let crackLength = hash21(nearestId) * 2.0 + time * crackSpeed * fractureAmt;
    let K = stress * sqrt(max(crackLength, 0.0));
    let crack = step(toughness, K);
    let branch = step(toughness * 1.3, K) * hash21(nearestId + vec2<f32>(1.0, 0.0));
    let crackDensity = crack + branch * 0.5;

    // Crack tip singularity glow
    let tip = smoothstep(0.015, 0.0, minDist) * crack * (1.0 - branch);

    // Hackle marks on fracture surfaces
    let hackle = sin(dot(cellUV, vec2<f32>(12.0, 5.0)) + hash21(nearestId) * 6.28) * 0.5 + 0.5;
    let hackleMask = smoothstep(0.45, 0.55, hackle) * edge * crackDensity;

    let hackleDir = atan2(cellUV.y - 0.5, cellUV.x - 0.5);
    let hackleRidge = sin(hackleDir * 6.0 + hash21(nearestId) * 6.28) * 0.5 + 0.5;
    let hackleMask2 = smoothstep(0.4, 0.6, hackleRidge) * edge * crackDensity * 0.5;

    // Thin-film iridescence on fracture surfaces
    let film = sin(length(cellUV - 0.5) * 25.0 - time * 1.5 + depth * 3.14) * 0.5 + 0.5;
    let irid = mix(vec3<f32>(0.9, 0.2, 0.2), vec3<f32>(0.2, 0.8, 0.9), film) * edge * crackDensity;

    // Internal refraction lines
    let refraction = sin(minDist * 20.0 + time * 0.5) * smoothstep(0.3, 0.0, edgeDist) * 0.12 * fractureAmt;

    // Subsurface scattering approximation
    let sss = smoothstep(0.25, 0.0, edgeDist) * 0.25 * (1.0 + mids);

    // Chromatic aberration on internal reflections
    let ca = chromatic * (1.0 + treble) * edgeDist;
    let rEdge = smoothstep(0.05 + ca, 0.0, edgeDist);
    let bEdge = smoothstep(0.05 - ca, 0.0, edgeDist);
    let chromaEdge = vec3<f32>(rEdge, edge, bEdge) * edgeGlow * (1.0 + treble);

    // Cell interior with depth perspective (crystal thickness)
    let cellHue = hash21(cellId + vec2<f32>(time * 0.005, 0.0));
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let h = abs(fract(vec3<f32>(cellHue) + k) * 6.0 - vec3<f32>(3.0));
    let cellColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)) * (0.3 + mids * 0.2) * (1.0 - depth * 0.3);

    // HDR bloom at crack tips
    let bloom = tip * 3.0 * (1.0 + bass);
    var color = cellColor + chromaEdge + irid + vec3<f32>(sss) + vec3<f32>(refraction) + vec3<f32>(bloom);
    color = color + vec3<f32>(0.35, 0.3, 0.25) * hackleMask;
    color = color + vec3<f32>(0.3, 0.25, 0.2) * hackleMask2;

    // ACES tone mapping
    color = aces_tone_map(color);

    // Alpha: crack density × stress intensity × depth perspective
    let alpha = clamp(crackDensity * K * depth + edge * 0.15, 0.0, 1.0);

    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(stress, crackDensity, 0.0, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(edge * 0.5 + crackDensity * 0.3, 0.0, 0.0, 0.0));
}
