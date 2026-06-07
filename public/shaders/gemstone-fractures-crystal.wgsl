// ═══════════════════════════════════════════════════════════════════
//  gemstone-fractures-crystal
//  Category: advanced-hybrid
//  Features: voronoi-shards, crystal-growth, physical-refraction, temporal
//  Complexity: Very High
//  Chunks From: gemstone-fractures.wgsl, alpha-crystal-growth-phase.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Crystalline gemstone shards with live crystal growth inside each
//  cell. Dendritic crystal patterns grow from shard boundaries,
//  scattering light through fracture lines with orientation-dependent
//  iridescence and physical IOR-based refraction.
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

const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // Parameters
    let scale = u.zoom_params.x * 20.0 + 2.0;
    let iorMix = u.zoom_params.y;
    let rotationBase = u.zoom_params.z;
    let fractureDensity = u.zoom_params.w;
    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    let growthRate = mix(0.001, 0.01, u.zoom_params.z);

    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    // Voronoi logic (from gemstone-fractures)
    let st = uv * vec2<f32>(aspect, 1.0) * scale;
    let i_st = floor(st);
    let f_st = fract(st);

    var m_dist = 1.0;
    var second_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);
            let animPoint = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);
            let diff = neighbor + animPoint - f_st;
            let dist = length(diff);
            if (dist < m_dist) {
                second_dist = m_dist;
                m_dist = dist;
                m_point = point;
                cell_id = i_st + neighbor;
            } else if (dist < second_dist) {
                second_dist = dist;
            }
        }
    }

    // Refraction based on cell
    let rotAngle = (hash22(cell_id).x - 0.5) * rotationBase * 10.0 + time * (hash22(cell_id).y - 0.5) * rotationBase;
    let c = cos(rotAngle);
    let s = sin(rotAngle);
    let center = vec2<f32>(0.5 * aspect, 0.5);
    let fromCenter = uv * vec2<f32>(aspect, 1.0) - center;
    let rotFromCenter = vec2<f32>(
        fromCenter.x * c - fromCenter.y * s,
        fromCenter.x * s + fromCenter.y * c
    );
    let sampleUV = (rotFromCenter + center) / vec2<f32>(aspect, 1.0);

    let dispersion = (ior - 1.0) * 0.3;
    let refraction = iorMix * 0.05;
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(refraction * (1.0 + dispersion), 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(refraction * (1.0 - dispersion), 0.0), 0.0).b;
    var color = vec3<f32>(r, g, b);

    // ═══ Crystal growth inside cells (from alpha-crystal-growth-phase) ═══
    let cellFracture = hash21(cell_id);
    let effectiveFracture = fractureDensity * (0.5 + 0.5 * cellFracture);
    let purity = 1.0 - effectiveFracture;

    // Simulate crystal phase in cell using animated growth
    let cellCenter = (cell_id + 0.5) / (vec2<f32>(aspect, 1.0) * scale);
    let toCellCenter = uv - cellCenter;
    let cellDist = length(toCellCenter * vec2<f32>(aspect, 1.0));
    let crystalPhase = smoothstep(0.5, 0.0, cellDist) * supercooling;
    let anisoFactor = 1.0 + anisotropy * sin(atan2(toCellCenter.y, toCellCenter.x) * 4.0 + time);
    let growth = smoothstep(0.0, 1.0, crystalPhase * growthRate * anisoFactor * 50.0 + time * 0.1);

    // Crystal orientation color
    let orientNorm = fract((atan2(toCellCenter.y, toCellCenter.x) + time * 0.2) / 6.283185307);
    let h6 = orientNorm * 6.0;
    let cc = 0.8;
    let x = cc * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var crystalColor: vec3<f32>;
    if (h6 < 1.0) { crystalColor = vec3<f32>(cc, x, 0.3); }
    else if (h6 < 2.0) { crystalColor = vec3<f32>(x, cc, 0.3); }
    else if (h6 < 3.0) { crystalColor = vec3<f32>(0.3, cc, x); }
    else if (h6 < 4.0) { crystalColor = vec3<f32>(0.3, x, cc); }
    else if (h6 < 5.0) { crystalColor = vec3<f32>(x, 0.3, cc); }
    else { crystalColor = vec3<f32>(cc, 0.3, x); }

    // Blend crystal growth into refraction
    color = mix(color, color * crystalColor * 1.5, growth * 0.4);

    // Physical transmission & fracture (from gemstone-fractures)
    let cosTheta = 1.0 - m_dist;
    let fresnel = fresnelSchlick(max(cosTheta, 0.0), F0);
    let pathLength = mix(0.05, 0.4, m_dist) / max(purity, 0.1);
    let absorptionCoeff = mix(0.2, 4.0, effectiveFracture);
    let absorption = exp(-absorptionCoeff * pathLength);
    let edgeDist = second_dist - m_dist;
    let edgeFactor = smoothstep(0.02, 0.0, edgeDist);
    let transmission = absorption * (1.0 - fresnel) * purity;
    let fractureLine = smoothstep(0.01, 0.0, edgeDist) * effectiveFracture;
    let specular = edgeFactor * fresnel * 0.5;
    color += vec3<f32>(specular);
    let fractureTint = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.85, 0.8), effectiveFracture);
    color = color * fractureTint;

    let alpha = clamp(transmission * (1.0 - fractureLine), 0.3, 1.0);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, alpha));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(growth, crystalPhase, orientNorm, alpha));
}
