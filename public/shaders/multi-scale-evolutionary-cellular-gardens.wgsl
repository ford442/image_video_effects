// ═══════════════════════════════════════════════════════════════════
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Features: multi-state-ca, rule-evolution, audio-mutation, multi-scale, organic-growth,
//            chromatic-species, bass-mutation-waves, temporal-color-memory, upgraded-rgba, aces-tone-map,
//            8-neighbor-weighted-diffusion, colony-border-bioluminescence, direct-sim-controls
//  Complexity: High
//  Chunks From: cellular automata + slow parameter evolution
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
//  Upgraded: 2026-07-22 (Algorithmist: 8-neighbor diffusion, border glow, real slider wiring)
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

// 8-neighbor diffusion weights: orthogonal cells are distance 1, diagonals ~sqrt(2).
const W_ORTHO: f32 = 1.0;
const W_DIAG: f32 = 0.70710678;
const W_SUM: f32 = 6.82842712; // 4 * W_ORTHO + 4 * W_DIAG

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.25;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // ── Shader-specific slider wiring (no generic boilerplate remap) ──
    // p1 Mutation Pressure -> rule evolution speed & mutation amplitude
    // p2 Species Competition -> predation coefficient between s1 and s2
    // p3 Resource Fertility  -> resource regeneration rate
    // p4 Mouse Nurturing     -> nurture radius AND strength around cursor
    let pMutation = clamp(u.zoom_params.x, 0.0, 1.0);
    let pCompete  = clamp(u.zoom_params.y, 0.0, 1.0);
    let pFertile  = clamp(u.zoom_params.z, 0.0, 1.0);
    let pNurture  = clamp(u.zoom_params.w, 0.0, 1.0);

    let mutationRate = (0.15 + 0.85 * pMutation) * (0.6 + mids * 0.8);
    let competition = 0.05 + 0.75 * pCompete + bass * 0.25;
    let regenRate = 0.004 + 0.028 * pFertile;
    let nurtureRadius = mix(0.06, 0.30, pNurture);
    let nurtureStrength = mix(0.15, 1.0, pNurture);

    // ── Sim state readback: dataTextureC carries (s1, s2, resource, _) ──
    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let s1 = state.r;
    let s2 = state.g;
    let resourceLevel = state.b;

    // ── Full 8-neighbor sampling with distance-correct weights ──
    let ps = 1.0 / res;
    let nE  = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( ps.x,  0.0), 0.0);
    let nW  = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-ps.x,  0.0), 0.0);
    let nN  = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( 0.0,  ps.y), 0.0);
    let nS  = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( 0.0, -ps.y), 0.0);
    let nNE = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( ps.x,  ps.y), 0.0);
    let nNW = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-ps.x,  ps.y), 0.0);
    let nSE = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( ps.x, -ps.y), 0.0);
    let nSW = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-ps.x, -ps.y), 0.0);

    let orthoS1 = (nE.r + nW.r + nN.r + nS.r) * W_ORTHO;
    let diagS1  = (nNE.r + nNW.r + nSE.r + nSW.r) * W_DIAG;
    let orthoS2 = (nE.g + nW.g + nN.g + nS.g) * W_ORTHO;
    let diagS2  = (nNE.g + nNW.g + nSE.g + nSW.g) * W_DIAG;
    let orthoRes = (nE.b + nW.b + nN.b + nS.b) * W_ORTHO;
    let diagRes  = (nNE.b + nNW.b + nSE.b + nSW.b) * W_DIAG;

    let avgS1 = (orthoS1 + diagS1) / W_SUM;
    let avgS2 = (orthoS2 + diagS2) / W_SUM;
    let avgRes = (orthoRes + diagRes) / W_SUM;

    // ── Slow rule evolution: per-epoch drift biased by Mutation Pressure ──
    let epoch = floor(time * (0.15 + pMutation * 0.6));
    let drift = hash12(vec2<f32>(epoch, 7.31)) - 0.5;
    let growth1 = 0.04 + mutationRate * 0.03 + drift * 0.02 * pMutation;
    let growth2 = 0.035 + mutationRate * 0.025 - drift * 0.015 * pMutation;

    // ── Species / resource update (channel layout preserved) ──
    var newS1 = s1 + (avgRes * growth1 - competition * s1 * s2);
    var newS2 = s2 + (avgRes * growth2 - competition * s1 * s2 * 0.8);
    var newRes = resourceLevel * 0.98 + regenRate - (newS1 + newS2) * 0.008;

    // Gentle diffusion pull toward the weighted neighborhood smooths fronts.
    newS1 += (avgS1 - s1) * 0.12;
    newS2 += (avgS2 - s2) * 0.12;

    // Mouse nurturing: slider sets both the radius and the strength of the boost.
    let mouseDist = length(uv - mouse);
    let mouseNurture = smoothstep(nurtureRadius, 0.0, mouseDist) * mouseDown * nurtureStrength;
    newRes += mouseNurture;
    newS1 += mouseNurture * 0.3;
    newS2 += mouseNurture * 0.25;

    newS1 = clamp(newS1, 0.0, 1.8);
    newS2 = clamp(newS2, 0.0, 1.8);
    newRes = clamp(newRes, 0.0, 1.5);

    textureStore(dataTextureA, gid.xy, vec4<f32>(newS1, newS2, newRes, 0.0));

    // ── Colony-border detection: count dominance flips across all 8 neighbors ──
    let domHere = step(s2, s1); // 1 where species 1 dominates
    var flips = 0.0;
    flips += abs(domHere - step(nE.g, nE.r));
    flips += abs(domHere - step(nW.g, nW.r));
    flips += abs(domHere - step(nN.g, nN.r));
    flips += abs(domHere - step(nS.g, nS.r));
    flips += abs(domHere - step(nNE.g, nNE.r));
    flips += abs(domHere - step(nNW.g, nNW.r));
    flips += abs(domHere - step(nSE.g, nSE.r));
    flips += abs(domHere - step(nSW.g, nSW.r));
    let border = flips * 0.125;
    // Restrained bioluminescent accent: only on living, genuinely contested fronts.
    let borderGlow = smoothstep(0.2, 0.6, border) * smoothstep(0.05, 0.25, s1 + s2);
    let glowPulse = 0.75 + 0.25 * sin(time * 2.0 + uv.x * 40.0 + uv.y * 37.0);
    let glowCol = vec3<f32>(0.25, 0.95, 0.75) * borderGlow * (0.18 + bass * 0.12) * glowPulse;

    // Chromatic species separation: species1 = green/cyan, species2 = magenta/purple
    let c1 = vec3<f32>(0.1, 0.7 + bass * 0.2, 0.5 + treble * 0.2) * newS1;
    let c2 = vec3<f32>(0.8 + mids * 0.1, 0.2, 0.6 + treble * 0.2) * newS2;
    let resCol = vec3<f32>(0.3, 0.5, 0.3) * newRes * 0.4;

    // Temporal color memory: previous frame tint bleeds in
    let prevCol = state.rgb;
    let col = mix(c1 + c2 + resCol, prevCol * vec3<f32>(0.95, 0.9, 0.85), 0.08 + bass * 0.03);
    let colGlow = col + glowCol;

    let totalLife = newS1 * 0.6 + newS2 * 0.6;
    let alpha = clamp(totalLife * 0.85 + newRes * 0.2 + borderGlow * 0.25 + bass * 0.05, 0.15, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(acesToneMap(colGlow * 1.15), a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalLife * 0.6 + borderGlow * 0.15, 0.0, 0.0, 0.0));
}
