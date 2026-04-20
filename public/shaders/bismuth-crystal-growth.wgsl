// ═══════════════════════════════════════════════════════════════════
//  bismuth-crystal-growth
//  Category: advanced-hybrid
//  Features: phase-field-crystal, hopper-crystals, iridescence,
//            temporal, mouse-driven
//  Complexity: Very High
//  Chunks From: bismuth-crystallizer.wgsl, alpha-crystal-growth-phase.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Phase-field crystal growth drives a bismuth hopper-crystal
//  structure. The solid-liquid interface generates oxide-layer
//  iridescence colors based on local crystal orientation and
//  growth velocity. Mouse and ripples seed new nucleation sites.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let time = u.config.x;

    // ═══ Read Previous State ═══
    let prevState = textureLoad(dataTextureC, coord, 0);
    var phase = prevState.r;
    var temp = prevState.g;
    var orientation = prevState.b;
    var impurity = prevState.a;

    if (time < 0.1) {
        phase = 0.0;
        temp = -0.2;
        orientation = 0.0;
        impurity = hash12(uv * 100.0) * 0.1;
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.02) {
            phase = 1.0;
            temp = 0.0;
            orientation = atan2(uv.y - 0.5, uv.x - 0.5);
        }
    }

    phase = clamp(phase, 0.0, 1.0);
    temp = clamp(temp, -1.0, 1.0);
    impurity = clamp(impurity, 0.0, 1.0);

    // Parameters
    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    let growthRate = mix(0.001, 0.01, u.zoom_params.z);
    let color_freq = u.zoom_params.w * 10.0 + 2.0;

    // Neighbors
    let left  = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down  = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up    = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapPhase = left.r + right.r + down.r + up.r - 4.0 * phase;
    let angle = orientation;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let gradPhase = vec2<f32>(right.r - left.r, up.r - down.r) * 0.5;
    let alignment = abs(dot(normalize(gradPhase + vec2<f32>(0.0001)), dir));
    let anisoFactor = 1.0 + anisotropy * (alignment - 0.5) * 2.0;

    let m = temp + supercooling * (1.0 - 2.0 * impurity);
    let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);
    phase += phaseReaction * growthRate * anisoFactor + lapPhase * 0.1 * growthRate;
    phase = clamp(phase, 0.0, 1.0);

    let lapTemp = left.g + right.g + down.g + up.g - 4.0 * temp;
    let latentHeat = (phase - prevState.r) * 0.5;
    temp += lapTemp * 0.05 + latentHeat;
    temp = clamp(temp, -1.0, 1.0);

    let lapOrient = left.b + right.b + down.b + up.b - 4.0 * orientation;
    orientation += lapOrient * 0.01 * phase;
    if (phase > 0.1 && phase < 0.9) {
        orientation = mix(orientation, atan2(gradPhase.y, gradPhase.x), 0.05);
    }

    let lapImpurity = left.a + right.a + down.a + up.a - 4.0 * impurity;
    let phaseChange = phase - prevState.r;
    impurity += lapImpurity * 0.02 - phaseChange * 0.1;
    impurity = clamp(impurity, 0.0, 1.0);

    // Mouse seed
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.04, 0.0, mouseDist) * mouseDown;
    phase = mix(phase, 1.0, mouseInfluence);
    if (mouseInfluence > 0.01) {
        orientation = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
        temp = mix(temp, 0.0, mouseInfluence);
    }

    // Ripple nucleation
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.3 && rDist < 0.03) {
            let nucleation = smoothstep(0.03, 0.0, rDist) * max(0.0, 1.0 - age * 3.0);
            phase = mix(phase, 1.0, nucleation * 0.5);
        }
    }
    phase = clamp(phase, 0.0, 1.0);

    // Store state
    textureStore(dataTextureA, coord, vec4<f32>(phase, temp, orientation, impurity));

    // ═══ Bismuth Visualization ═══
    let orientNorm = fract(orientation / 6.283185307);
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

    let liquidColor = vec3<f32>(0.05, 0.08, 0.15) * (1.0 + temp * 0.5);
    let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
    let interfaceColor = vec3<f32>(0.9, 0.95, 1.0);

    var displayColor = mix(liquidColor, crystalColor, smoothstep(0.4, 0.6, phase));
    displayColor = mix(displayColor, interfaceColor, interfaceMask * 0.5);
    displayColor = mix(displayColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.3);

    // ═══ Bismuth Iridescence ═══
    let distFromCenter = length(uv - vec2<f32>(0.5));
    let cosTheta = 1.0 - distFromCenter;
    let F0_bismuth = vec3<f32>(0.8, 0.85, 0.9);
    let fresnel = fresnelMetal(max(cosTheta, 0.0), F0_bismuth);

    let oxideThickness = phase * 5.0 * color_freq + time * 0.1;
    let interferenceColor = vec3<f32>(
        0.5 + 0.5 * cos(oxideThickness),
        0.5 + 0.5 * cos(oxideThickness + 2.0),
        0.5 + 0.5 * cos(oxideThickness + 4.0)
    );

    displayColor = mix(displayColor, displayColor * interferenceColor + fresnel * 0.2, phase * 0.7);

    let transmission = (1.0 - distFromCenter * 0.5) * (1.0 - phase * 0.3);
    let alpha = clamp(transmission, 0.4, 1.0);

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
