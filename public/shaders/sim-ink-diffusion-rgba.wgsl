// ═══════════════════════════════════════════════════════════════════
//  Sim: Ink Diffusion RGBA
//  Category: simulation
//  Features: simulation, rgba-state-machine, temporal, mouse-driven
//  Complexity: High
//  Chunks From: sim-ink-diffusion.wgsl, alpha-fluid-simulation-paint.wgsl
//  Created: 2026-04-18
//  By: Agent CB-2 - RGBA Simulation Upgrader
// ═══════════════════════════════════════════════════════════════════
//  Four-ink wet diffusion on paper texture. Each RGB channel holds
//  one pigment; alpha holds water content that drives all diffusion.
//  RGBA Channels:
//    R = Cyan pigment concentration (0=none, 1=saturated)
//    G = Magenta pigment concentration
//    B = Yellow pigment concentration
//    A = Water saturation (0=dry paper, 1=fully wet)
//  Water acts as the diffusion medium: wetter = pigments spread faster.
//  Pigments mix subtractively (CMY) when they overlap on wet paper.
//  Why f32: Sub-pixel pigment concentration precision required for
//  realistic ink bleeding and water-front propagation.
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

fn paperTexture(uv: vec2<f32>) -> f32 {
    var tex = 0.0;
    for (var i: i32 = 0; i < 3; i++) {
        let fi = f32(i);
        tex += hash12(uv * 100.0 * (fi + 1.0)) * pow(0.5, fi + 1.0);
    }
    return 0.8 + tex * 0.4;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read current state
    let state = textureLoad(dataTextureC, coord, 0);
    var cyan = state.r;
    var magenta = state.g;
    var yellow = state.b;
    var water = state.a;

    // Paper texture affects absorption
    let paper = paperTexture(uv);

    // Seed on first frame: a few ink drops with water
    if (time < 0.1) {
        cyan = 0.0;
        magenta = 0.0;
        yellow = 0.0;
        water = paper * 0.3;
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.08) {
            cyan = 0.6;
            water = 0.8;
        }
        let drop2 = length(uv - vec2<f32>(0.3, 0.6));
        if (drop2 < 0.05) {
            magenta = 0.5;
            water = 0.7;
        }
        let drop3 = length(uv - vec2<f32>(0.7, 0.4));
        if (drop3 < 0.06) {
            yellow = 0.55;
            water = 0.75;
        }
    }

    // === PARAMETERS ===
    let wetness = mix(0.5, 2.0, u.zoom_params.x);
    let pigmentDiffusion = mix(0.1, 0.5, u.zoom_params.y);
    let colorMixing = u.zoom_params.z;
    let evaporation = mix(0.98, 0.999, u.zoom_params.w);

    // === NEIGHBOR SAMPLING ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // === WATER DIFFUSION (drives everything) ===
    let lapWater = left.a + right.a + down.a + up.a - 4.0 * water;
    let waterDiffRate = 0.5 * wetness / paper;
    water = water + waterDiffRate * lapWater;

    // === PIGMENT DIFFUSION (only where water is present) ===
    let wetFactor = smoothstep(0.05, 0.2, water);
    let diffRate = pigmentDiffusion * wetFactor / paper;

    let lapCyan = left.r + right.r + down.r + up.r - 4.0 * cyan;
    let lapMagenta = left.g + right.g + down.g + up.g - 4.0 * magenta;
    let lapYellow = left.b + right.b + down.b + up.b - 4.0 * yellow;

    cyan = cyan + diffRate * lapCyan;
    magenta = magenta + diffRate * lapMagenta;
    yellow = yellow + diffRate * lapYellow;

    // === COLOR MIXING (subtractive on wet paper) ===
    let mixStrength = colorMixing * wetFactor * 0.1;
    cyan = mix(cyan, (cyan + magenta + yellow) / 3.0, mixStrength);
    magenta = mix(magenta, (cyan + magenta + yellow) / 3.0, mixStrength);
    yellow = mix(yellow, (cyan + magenta + yellow) / 3.0, mixStrength);

    // === EVAPORATION ===
    water = water * evaporation;

    // === MOUSE INK DROP ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.08, 0.0, mouseDist) * mouseDown;
    let hue = fract(time * 0.1 + mousePos.x + mousePos.y);
    cyan += mouseInfluence * (0.5 + 0.5 * cos(hue * 6.283185307));
    magenta += mouseInfluence * (0.5 + 0.5 * cos(hue * 6.283185307 + 2.094));
    yellow += mouseInfluence * (0.5 + 0.5 * cos(hue * 6.283185307 + 4.189));
    water += mouseInfluence * 0.5;

    // === RIPPLE WATER INJECTION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rDist < 0.08) {
            let strength = smoothstep(0.08, 0.0, rDist) * max(0.0, 1.0 - age * 0.5);
            water += strength * 0.4;
            cyan += strength * 0.15 * (0.5 + 0.5 * sin(f32(i) * 1.7));
            magenta += strength * 0.15 * (0.5 + 0.5 * sin(f32(i) * 2.3));
            yellow += strength * 0.15 * (0.5 + 0.5 * sin(f32(i) * 3.1));
        }
    }

    // Clamp
    cyan = clamp(cyan, 0.0, 1.0);
    magenta = clamp(magenta, 0.0, 1.0);
    yellow = clamp(yellow, 0.0, 1.0);
    water = clamp(water, 0.0, 1.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(cyan, magenta, yellow, water));

    // === STATE -> VISUAL COLOR MAPPING ===
    // Convert CMY pigment densities to RGB display color
    let pigmentToRGB = vec3<f32>(
        (1.0 - cyan) * (1.0 - yellow),  // Red = no cyan * no yellow... wait, that's not right
        // Actually: CMY->RGB is: R=1-C, G=1-M, B=1-Y for pure pigments
        // But we want to SHOW the ink colors, not subtract them
        0.0, 0.0, 0.0
    );
    // Show ink in their actual colors: cyan, magenta, yellow
    let inkColor = vec3<f32>(
        magenta * 0.3 + yellow * 0.3,  // R component
        cyan * 0.4 + yellow * 0.3,     // G component
        cyan * 0.5 + magenta * 0.4     // B component
    );

    // Paper background
    let paperColor = vec3<f32>(0.95, 0.92, 0.85) * paper;

    // Wet paper darkens slightly
    let wetPaper = paperColor * (1.0 - water * 0.15);

    // Blend ink with paper based on pigment density
    let inkDensity = (cyan + magenta + yellow) / 3.0;
    var displayColor = mix(wetPaper, inkColor, inkDensity);

    // Add paper grain
    displayColor *= 0.98 + hash12(uv * 500.0) * 0.04;

    // Water glisten at high saturation
    let glisten = water * water * 0.1;
    displayColor += vec3<f32>(glisten);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.85, 1.0, inkDensity + water * 0.3);

    textureStore(writeTexture, coord, vec4<f32>(displayColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - inkDensity * 0.1), 0.0, 0.0, 0.0));
}
