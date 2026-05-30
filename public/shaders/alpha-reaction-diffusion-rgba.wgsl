// ═══════════════════════════════════════════════════════════════════
//  Alpha Reaction Diffusion RGBA
//  Category: simulation
//  Features: multi-species-ecosystem, predator-prey, audio-reactive, depth-stratified, mouse-keystone
//  Complexity: High
//  RGBA Channels:
//    R = Chemical A (activator / prey 1)
//    G = Chemical B (inhibitor / predator 1)
//    B = Chemical C (activator / prey 2)
//    A = Chemical D (inhibitor / predator 2)
//  Why f32: Reaction-diffusion requires precise sub-threshold
//  concentrations; 8-bit quantization collapses subtle gradients
//  and destroys pattern formation.
//  Updated: 2026-05-31 — Grok (ecosystem + audio mutation + depth diffusion)
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    // Read current state
    let state = textureLoad(dataTextureC, coord, 0);
    var A = state.r;
    var B = state.g;
    var C = state.b;
    var D = state.a;

    // Seed on first frame (all near zero)
    let time = u.config.x;
    if (time < 0.1) {
        A = 1.0;
        B = 0.0;
        C = 1.0;
        D = 0.0;
        // Seed spots near center
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.05) {
            B = 0.5;
            D = 0.3;
        }
        // Secondary seed
        let seed2Dist = length(uv - vec2<f32>(0.3, 0.7));
        if (seed2Dist < 0.03) {
            B = 0.4;
        }
    }

    // === LAPLACIAN (5-point stencil) ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapA = left.r + right.r + down.r + up.r - 4.0 * A;
    let lapB = left.g + right.g + down.g + up.g - 4.0 * B;
    let lapC = left.b + right.b + down.b + up.b - 4.0 * C;
    let lapD = left.a + right.a + down.a + up.a - 4.0 * D;

    // === AUDIO-DRIVEN ECOSYSTEM PARAMETERS ===
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Bass increases "predation" (kill rate) — predators thrive when the beat hits
    let feed = mix(0.018, 0.065, u.zoom_params.x);
    let baseKill = mix(0.038, 0.072, u.zoom_params.y);
    let kill = baseKill + bass * 0.035;                    // bass = more aggressive predators

    // Diffusion becomes asymmetric and audio-reactive (ecosystem "seasons")
    let diffA = 0.82 + mids * 0.18;   // A (prey 1) diffuses faster in mids
    let diffB = 0.28 + bass * 0.12;   // B (predator 1) slows when bass is high
    let diffC = 0.74 + treble * 0.22; // C (prey 2) gets bursty diffusion on treble
    let diffD = 0.24 + bass * 0.08;

    let crossInhibit = (u.zoom_params.z * 0.32) + (mids * 0.18); // mids increase competition between the two ecosystems
    let dt = 0.82;

    // === 4-SPECIES PREDATOR-PREY REACTION (evolved) ===
    // Two loosely coupled ecosystems with audio-modulated mutation pressure
    // Bass makes predators hungrier, treble makes prey more "spore-like" (erratic diffusion)
    let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D * (1.0 + bass * 0.4);
    let dB = diffB * lapB + A * B * B - (feed + kill) * B;
    let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B * (1.0 + treble * 0.5);
    let dD = diffD * lapD + C * D * D - (feed + kill) * D;

    A = A + dA * dt;
    B = B + dB * dt;
    C = C + dC * dt;
    D = D + dD * dt;

    // Clamp to prevent divergence
    A = clamp(A, 0.0, 1.0);
    B = clamp(B, 0.0, 1.0);
    C = clamp(C, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

    // === MOUSE AS KEYSTONE SPECIES ===
    // Mouse down introduces "invasive" predator pressure (B + D)
    // Holding creates localized extinction events that the ecosystem must recover from
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.12, 0.0, mouseDist) * mouseDown;

    // Bass + mouse = more violent introduction (stronger perturbation)
    let keystoneStrength = 0.32 + bass * 0.25;
    B += mouseInfluence * keystoneStrength;
    D += mouseInfluence * (keystoneStrength * 0.7);

    // Treble + mouse = occasional "spore burst" of the second ecosystem (C)
    if (treble > 0.6) {
        C += mouseInfluence * treble * 0.6;
    }

    B = clamp(B, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);
    C = clamp(C, 0.0, 1.0);

    // === RIPPLE PERTURBATION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.5 && rDist < 0.06) {
            let strength = smoothstep(0.06, 0.0, rDist) * max(0.0, 1.0 - age);
            B += strength * 0.4;
            D += strength * 0.2;
        }
    }
    B = clamp(B, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

    // === ECOSYSTEM VISUALIZATION + DEPTH STRATIFICATION ===
    // Two competing ecosystems with more organic color mixing
    let colorPrey1   = vec3<f32>(0.15, 0.55, 0.95) * A;     // Cool blue prey
    let colorPred1   = vec3<f32>(0.95, 0.25, 0.1) * B;     // Hot predator
    let colorPrey2   = vec3<f32>(0.2, 0.9, 0.45) * C;     // Acid green prey
    let colorPred2   = vec3<f32>(0.95, 0.85, 0.15) * D;    // Gold predator

    // When one pair dominates, the other ecosystem gets slightly desaturated (extinction pressure)
    let biomass1 = A + B;
    let biomass2 = C + D;
    let dominance = clamp((biomass1 - biomass2) * 0.8, -0.6, 0.6);

    var eco1 = colorPrey1 + colorPred1;
    var eco2 = colorPrey2 + colorPred2;

    // Depth modulates diffusion "layers" — deeper = slower, more stable patterns
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthDamp = mix(0.6, 1.05, depth); // deeper areas evolve more slowly

    // Final ecosystem blend with dominance fade
    var displayColor = mix(eco1, eco2, 0.5 + dominance * 0.4) * depthDamp;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.15));

    // Source mix now also carries a little "nutrient" from the image into the simulation
    let sourceMix = u.zoom_params.w;
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let nutrient = dot(sourceColor, vec3<f32>(0.33)) * 0.08 * sourceMix;
    displayColor += nutrient;

    // Alpha now represents total "ecosystem instability" (good for compositing)
    let instability = abs(dA) + abs(dB) + abs(dC) + abs(dD);
    let biomassAlpha = clamp((biomass1 + biomass2) * 0.65 + instability * 2.0, 0.3, 1.0);
    let finalAlpha = mix(biomassAlpha * 0.75, biomassAlpha, depth);

    // Premultiplied write
    let a = clamp(finalAlpha, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(displayColor * a, a));

    // Write depth (slightly modulated by biomass for interesting layering)
    let outDepth = mix(depth, depth * 0.85 + (biomass1 - biomass2) * 0.08, 0.5);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(outDepth, 0.0, 1.0), 0.0, 0.0, 0.0));
}
