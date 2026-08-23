// ═══════════════════════════════════════════════════════════════════
//  Sim: Decay System RGBA
//  Category: simulation
//  Features: simulation, rgba-state-machine, temporal, mouse-driven
//  Complexity: High
//  Chunks From: sim-decay-system.wgsl, alpha-reaction-diffusion-rgba.wgsl
//  Created: 2026-04-18
//  By: Agent CB-2 - RGBA Simulation Upgrader
// ═══════════════════════════════════════════════════════════════════
//  Four-layer material decay with cross-coupling. Each layer decays
//  at a different rate and affects the decay rate of other layers.
//  RGBA Channels:
//    R = Paint layer integrity (1=perfect, 0=fully peeled)
//    G = Metal corrosion (0=pristine, 1=fully rusted)
//    B = Organic rot / wood decay (0=healthy, 1=fully rotten)
//    A = Structural integrity (1=sound, 0=collapsed)
//  Cross-coupling: when paint fails, metal corrodes faster;
//                  when structure weakens, all layers decay faster.
//  Why f32: Subtle early-stage decay requires precision below 0.01;
//  8-bit would make everything appear either perfect or ruined.
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Edge detection from source image
fn detectEdges(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let edgeX = length(right - left);
    let edgeY = length(up - down);
    return (edgeX + edgeY) * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixel = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

    // Read current decay state
    let state = stateAt(coord, dims);
    var paint = state.r;      // 1.0 = perfect paint
    var metal = state.g;      // 0.0 = no rust
    var organic = state.b;    // 0.0 = no rot
    var structure = state.a;  // 1.0 = sound

    // Source image for initialization and edge detection
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let edges = detectEdges(uv, pixel);
    let isEdge = step(0.08, edges);

    // Initialize from source on first frame
    if (time < 0.1) {
        let brightness = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));
        // Bright areas = paint; mid = metal; dark = organic
        paint = smoothstep(0.3, 0.7, brightness);
        metal = smoothstep(0.2, 0.5, brightness) * (1.0 - smoothstep(0.5, 0.8, brightness));
        organic = 1.0 - smoothstep(0.1, 0.4, brightness);
        structure = 0.8 + brightness * 0.2;
    }

    // === PARAMETERS ===
    let baseDecay = mix(0.0005, 0.005, u.zoom_params.x);
    let edgeVulnerability = mix(1.0, 5.0, u.zoom_params.y);
    let moisture = u.zoom_params.z;
    let recovery = mix(0.0, 0.002, u.zoom_params.w);

    // === NEIGHBOR STATE (for spread) ===
    var decayedNeighbors = 0.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            if (x == 0 && y == 0) { continue; }
            let nState = stateAt(coord + vec2<i32>(x, y), dims);
            // Count how many neighbors have failed structure
            decayedNeighbors += step(0.5, 1.0 - nState.a);
        }
    }

    // === CROSS-COUPLED DECAY ===
    // Paint fails first; exposed metal rusts; organic rots; all affect structure

    // Paint decay: faster at edges, accelerated by moisture
    let paintDecayRate = baseDecay * (1.0 + edgeVulnerability * isEdge) *
        (1.0 + moisture * 0.5 + audio.x * 0.45);
    paint = paint - paintDecayRate * (1.0 + decayedNeighbors * 0.05);

    // Metal corrosion: accelerated when paint is gone, by moisture
    let exposedMetal = 1.0 - smoothstep(0.2, 0.5, paint);
    let rustRate = baseDecay * 2.0 * (1.0 + exposedMetal * 2.0) * (1.0 + moisture * 1.5);
    metal = metal + rustRate * (1.0 + decayedNeighbors * 0.08);

    // Organic rot: accelerated by moisture, spreads from neighbors
    let rotRate = baseDecay * 1.5 * (1.0 + moisture * 2.0);
    organic = organic + rotRate * (1.0 + decayedNeighbors * 0.1);

    // Structural integrity: decays when other layers fail
    let layerDamage = (1.0 - paint) * 0.2 + metal * 0.3 + organic * 0.2;
    let structDecay = baseDecay * 0.5 * (1.0 + layerDamage * 3.0) * (1.0 + decayedNeighbors * 0.15);
    structure = structure - structDecay;

    // === RECOVERY (mouse "restoration") ===
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseRestore = smoothstep(0.12, 0.0, mouseDist) * clamp(u.zoom_config.w, 0.0, 1.0);
    paint += recovery * (1.0 + mouseRestore * 20.0);
    structure += recovery * 0.5 * (1.0 + mouseRestore * 20.0);
    metal -= recovery * 0.5 * (1.0 + mouseRestore * 10.0);
    organic -= recovery * 0.3 * (1.0 + mouseRestore * 10.0);

    // === RIPPLE DAMAGE ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let strength = exp(-abs(rDist - age * 0.18) * 50.0 - age * 1.2);
            paint -= strength * 0.3;
            structure -= strength * 0.2;
            metal += strength * (0.08 + audio.y * 0.08);
        }
    }

    // Clamp
    paint = clamp(paint, 0.0, 1.0);
    metal = clamp(metal, 0.0, 1.0);
    organic = clamp(organic, 0.0, 1.0);
    structure = clamp(structure, 0.0, 1.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(paint, metal, organic, structure));

    // === STATE -> VISUAL COLOR MAPPING ===
    // Layer colors
    let paintColor = sourceColor * vec3<f32>(0.85, 0.90, 0.95); // Faded paint
    let rustColor = vec3<f32>(0.65, 0.30, 0.08);                // Iron oxide
    let rotColor = vec3<f32>(0.25, 0.20, 0.12);                 // Dark rot
    let structDim = 0.4 + structure * 0.6;                       // Darken as structure fails

    // Composite layers from bottom up
    var displayColor = sourceColor * structDim;

    // Add rust where metal is corroded
    displayColor = mix(displayColor, rustColor, metal * 0.8);

    // Add rot where organic decay exists
    displayColor = mix(displayColor, rotColor, organic * 0.6);

    // Blend original paint over where paint still exists
    displayColor = mix(displayColor, sourceColor * paintColor * structDim, paint);

    // Add rust texture noise in corroded areas
    let rustNoise = hash12(uv * 150.0 + time * 0.005);
    let rustTexture = vec3<f32>(0.55, 0.28, 0.06) * rustNoise;
    displayColor = mix(displayColor, rustTexture, metal * (1.0 - paint) * 0.5);

    // Add moisture darkening
    displayColor *= 1.0 - moisture * 0.15 * (1.0 - paint);

    // Edge corrosion highlight
    let edgeCorrosion = isEdge * (1.0 - paint) * vec3<f32>(0.15, 0.08, 0.03);
    displayColor += edgeCorrosion + audio * vec3<f32>(0.08, 0.04, 0.12) *
        ((1.0 - paint) + metal + organic) * 0.3;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let totalDamage = (1.0 - paint) * 0.3 + metal * 0.3 + organic * 0.2 + (1.0 - structure) * 0.2;
    let alpha = clamp(totalDamage * 0.88 + (1.0 - structure) * 0.12, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(aces(displayColor), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - totalDamage * 0.15), 0.0, 0.0, 0.0));
}
