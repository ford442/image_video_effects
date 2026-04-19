// ═══════════════════════════════════════════════════════════════════
//  Alpha Reaction Diffusion RGBA
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Chemical A (activator 1)
//    G = Chemical B (inhibitor 1)
//    B = Chemical C (activator 2)
//    A = Chemical D (inhibitor 2)
//  Why f32: Reaction-diffusion requires precise sub-threshold
//  concentrations; 8-bit quantization collapses subtle gradients
//  and destroys pattern formation.
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

@compute @workgroup_size(8, 8, 1)
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

    // === PARAMETERS ===
    let feed = mix(0.02, 0.06, u.zoom_params.x);
    let kill = mix(0.04, 0.07, u.zoom_params.y);
    let diffA = 0.8; // A diffuses faster
    let diffB = 0.3;
    let diffC = 0.7;
    let diffD = 0.25;
    let crossInhibit = u.zoom_params.z * 0.3;
    let dt = 0.8;

    // === 4-SPECIES REACTION ===
    // A feeds B, C feeds D
    // B inhibits C, D inhibits A
    let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
    let dB = diffB * lapB + A * B * B - (feed + kill) * B;
    let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B;
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

    // === MOUSE INJECTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    B += mouseInfluence * 0.3;
    D += mouseInfluence * 0.2;
    B = clamp(B, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

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

    // === VISUALIZATION ===
    // Map chemicals to distinct colors
    let colorA = vec3<f32>(0.0, 0.4, 1.0) * A;   // Blue
    let colorB = vec3<f32>(1.0, 0.2, 0.0) * B;   // Red-orange
    let colorC = vec3<f32>(0.0, 1.0, 0.3) * C;   // Green
    let colorD = vec3<f32>(1.0, 0.8, 0.0) * D;   // Gold
    let displayColor = colorA + colorB + colorC + colorD;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Mix with source image based on param4
    let sourceMix = u.zoom_params.w;
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(displayColor, sourceColor, sourceMix * 0.5);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, A + C));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
