// ═══════════════════════════════════════════════════════════════════
//  Alpha Crystal Growth Phase
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Phase field (0.0 = liquid, 1.0 = solid)
//    G = Temperature / supercooling (can be negative)
//    B = Crystal orientation angle (0 to 2pi)
//    A = Impurity concentration (affects growth rate and color)
//  Why f32: Phase field is a smooth continuous interface; 8-bit
//  would make the solid-liquid boundary 1-pixel wide and destroy
//  dendritic branching. Orientation needs full 0-2pi range.
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

// ═══ CHUNK: hash12 (from chunk-library.md / gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var phase = prevState.r;
    var temp = prevState.g;
    var orientation = prevState.b;
    var impurity = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        phase = 0.0;
        temp = -0.2; // Undercooled liquid
        orientation = 0.0;
        impurity = hash12(uv * 100.0) * 0.1;
        // Seed crystal at center
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

    // === PARAMETERS ===
    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    let growthRate = mix(0.001, 0.01, u.zoom_params.z);

    // === PHASE-FIELD UPDATE ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapPhase = left.r + right.r + down.r + up.r - 4.0 * phase;

    // Anisotropic growth: prefer growth along orientation direction
    let angle = orientation;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let gradPhase = vec2<f32>(right.r - left.r, up.r - down.r) * 0.5;
    let alignment = abs(dot(normalize(gradPhase + vec2<f32>(0.0001)), dir));
    let anisoFactor = 1.0 + anisotropy * (alignment - 0.5) * 2.0;

    // Phase field driving force
    let m = temp + supercooling * (1.0 - 2.0 * impurity);
    let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);

    phase += phaseReaction * growthRate * anisoFactor + lapPhase * 0.1 * growthRate;
    phase = clamp(phase, 0.0, 1.0);

    // === TEMPERATURE UPDATE ===
    let lapTemp = left.g + right.g + down.g + up.g - 4.0 * temp;
    // Latent heat release on solidification
    let latentHeat = (phase - prevState.r) * 0.5;
    temp += lapTemp * 0.05 + latentHeat;
    temp = clamp(temp, -1.0, 1.0);

    // === ORIENTATION UPDATE ===
    // Orientation diffuses along solid regions
    let lapOrient = left.b + right.b + down.b + up.b - 4.0 * orientation;
    orientation += lapOrient * 0.01 * phase;
    // Align with local gradient where solidifying
    if (phase > 0.1 && phase < 0.9) {
        orientation = mix(orientation, atan2(gradPhase.y, gradPhase.x), 0.05);
    }

    // === IMPURITY REJECTION ===
    // Impurities get pushed ahead of growing crystal
    let lapImpurity = left.a + right.a + down.a + up.a - 4.0 * impurity;
    let phaseChange = phase - prevState.r;
    impurity += lapImpurity * 0.02 - phaseChange * 0.1;
    impurity = clamp(impurity, 0.0, 1.0);

    // === MOUSE SEED CRYSTALS ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.04, 0.0, mouseDist) * mouseDown;
    phase = mix(phase, 1.0, mouseInfluence);
    if (mouseInfluence > 0.01) {
        orientation = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
        temp = mix(temp, 0.0, mouseInfluence);
    }

    // === RIPPLE NUCLEATION ===
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

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(phase, temp, orientation, impurity));

    // === VISUALIZATION ===
    // Solid = crystal color based on orientation
    let orientNorm = fract(orientation / 6.283185307);
    let h6 = orientNorm * 6.0;
    let c = 0.8;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var crystalColor: vec3<f32>;
    if (h6 < 1.0) { crystalColor = vec3(c, x, 0.3); }
    else if (h6 < 2.0) { crystalColor = vec3(x, c, 0.3); }
    else if (h6 < 3.0) { crystalColor = vec3(0.3, c, x); }
    else if (h6 < 4.0) { crystalColor = vec3(0.3, x, c); }
    else if (h6 < 5.0) { crystalColor = vec3(x, 0.3, c); }
    else { crystalColor = vec3(c, 0.3, x); }

    // Liquid = dark undercooled
    let liquidColor = vec3<f32>(0.05, 0.08, 0.15) * (1.0 + temp * 0.5);

    // Interface = bright
    let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
    let interfaceColor = vec3<f32>(0.9, 0.95, 1.0);

    var displayColor = mix(liquidColor, crystalColor, smoothstep(0.4, 0.6, phase));
    displayColor = mix(displayColor, interfaceColor, interfaceMask * 0.5);

    // Impurity tint
    displayColor = mix(displayColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.3);

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, phase));

    // Depth pass-through
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
