// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Xeno Botanical Synth Flora - L-System Growth Simulation
//  Category: generative
//  Alpha Mode: Depth-Layered Alpha + Physical Transmittance
//  Features: advanced-alpha, botanical, generative, depth-aware, l-system, mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Upgraded: 2026-09-27
//  Ideas: leaf midrib and lateral veins; treble conductive filaments on branch ridges; held phototropism and click spore spray
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ NOISE & MATH ═══

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * hash(pp);
        pp = pp * 2.03 + vec2<f32>(1.7, 3.1);
        amplitude *= 0.5;
    }
    return value;
}

// ═══ L-SYSTEM BRANCHING ═══

fn branchDensity(uv: vec2<f32>, angle: f32, complexity: f32, t: f32) -> f32 {
    let rotUV = vec2<f32>(
        uv.x * cos(angle) - uv.y * sin(angle),
        uv.x * sin(angle) + uv.y * cos(angle)
    );
    let branches = sin(rotUV.x * complexity) * cos(rotUV.y * complexity * 0.7);
    let growth = smoothstep(-0.2, 0.8, branches + sin(t * 0.3) * 0.1);
    return growth;
}

// ═══ LEAF SDF ═══

fn sdLeaf(p: vec2<f32>, len: f32, wid: f32) -> f32 {
    let q = vec2<f32>(abs(p.x), p.y);
    let vein = sin(p.x * 20.0) * 0.02 * len;
    let outline = abs(q.y - vein) - wid * (1.0 - q.x / len);
    let tip = length(q - vec2<f32>(len, 0.0)) - wid * 0.5;
    return min(max(outline, q.x - len), tip);
}

// Midrib plus lateral veins on the existing leaf, not a second plant.
fn leafVeinMask(p: vec2<f32>, len: f32) -> f32 {
    let onBlade = smoothstep(len, 0.0, p.x) * step(0.0, p.x);
    let midrib = exp(-abs(p.y) * 90.0) * onBlade;
    let lateral = exp(-abs(fract(p.x * 7.0) - 0.5) * 16.0) * exp(-abs(p.y) * 10.0) * onBlade;
    return midrib * 0.85 + lateral * 0.4;
}

// ═══ TURING PATTERN ═══

fn turingPattern(uv: vec2<f32>, t: f32) -> f32 {
    let scale = 18.0;
    let p = uv * scale;
    let activator = sin(p.x + t * 0.5) * sin(p.y + t * 0.3);
    let inhibitor = sin(p.x * 0.5 + t * 0.2) * sin(p.y * 0.5 + t * 0.15);
    return smoothstep(0.0, 0.5, activator - inhibitor * 0.6);
}

// ═══ L-SYSTEM ITERATION (simplified string-rewrite approximation) ═══

fn lSystemIterate(seed: u32, ruleOffset: u32, iterations: i32) -> f32 {
    var state = fract(f32(seed) * 0.618);
    for (var i: i32 = 0; i < iterations; i = i + 1) {
        let rule = fract(f32(seed + u32(i) + ruleOffset) * 0.317);
        if (rule < 0.33) {
            state = state * 0.5;
        } else if (rule < 0.66) {
            state = state * 0.5 + 0.5;
        } else {
            state = abs(state - 0.5) * 2.0;
        }
    }
    return state;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let audioMid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + audioMid * 0.5;

    let growth = u.zoom_params.x * (1.0 + audioMid * 0.3);
    let complexity = u.zoom_params.y * 10.0 + 3.0;
    let depthWeight = u.zoom_params.z;
    let glowSpread = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Botanical pattern with L-system branching
    let centered = uv - 0.5;
    let angle = atan2(centered.y, centered.x);
    let radius = length(centered);

    // Held phototropism: branch fan leans toward the pointer without a spring.
    let pointer = u.zoom_config.yz - vec2<f32>(0.5);
    let held = u.zoom_config.w;
    let pointerAngle = atan2(pointer.y, pointer.x);
    let branchAngle = angle + time * 0.2 * audioReactivity + held * (pointerAngle - angle) * 0.35;
    let branchPattern = branchDensity(centered, branchAngle, complexity, time);

    // Turing pattern venation on leaves
    let venation = turingPattern(uv * 3.0, time * 0.5);

    // Organic noise for bark texture
    let barkNoise = fbm(floor(uv * 20.0) + time * 0.1 * audioReactivity, 3);

    // Leaf shapes at branch tips
    let leafUV = (fract(uv * 4.0) - 0.5) * 2.0;
    let leafDist = sdLeaf(leafUV, 0.8, 0.3);
    let leafMask = smoothstep(0.05, -0.05, leafDist);
    let veins = leafVeinMask(leafUV, 0.8) * leafMask;

    // Combine structures
    let flora = smoothstep(0.0, 0.5 + glowSpread * barkNoise, branchPattern * growth);
    let leafFlora = leafMask * venation * growth;
    let combinedFlora = max(flora, leafFlora);

    // Conductive filaments sit on the existing branch ridges.
    let ridge = smoothstep(0.42, 0.55, branchPattern) * (1.0 - smoothstep(0.62, 0.78, branchPattern));
    let filament = ridge * (0.35 + treble * 1.1) * growth;

    // Click spore spray: short radial grains, not a shockwave ring.
    var spore = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age > 0.0 && age < 2.4) {
            let delta = uv - rp.xy;
            let dist = length(delta);
            let life = exp(-age * 1.6);
            let spray = sin(atan2(delta.y, delta.x) * 9.0 + age * 6.0);
            let grain = smoothstep(0.55, 0.95, spray) * exp(-dist * 7.0) * life;
            spore = max(spore, grain);
        }
    }

    // Nutrient flow visualization (green channel emphasis)
    let nutrient = fbm(uv * 8.0 + vec2<f32>(time * 0.1, 0.0), 2) * growth;

    // Bioluminescence (blue channel, pulsing)
    let bioPulse = sin(time * 2.0 + radius * 10.0) * 0.5 + 0.5;
    let biolum = bioPulse * leafMask * audioReactivity * (1.0 + bass * 0.35);

    // Color encoding: R=branch ID, G=nutrient, B=bioluminescence
    var floraColorBase = vec3<f32>(
        0.15 + combinedFlora * 0.5 + lSystemIterate(u32(uv.x * 100.0), u32(uv.y * 100.0), 3) * 0.2,
        0.4 + nutrient * 0.4 + combinedFlora * 0.3,
        0.2 + biolum * 0.6 + combinedFlora * 0.2
    );
    floraColorBase = floraColorBase + vec3<f32>(0.15, 0.85, 0.35) * veins;
    floraColorBase = floraColorBase + vec3<f32>(0.25, 0.85, 1.0) * filament;
    floraColorBase = floraColorBase + vec3<f32>(0.85, 1.0, 0.45) * spore * (0.6 + treble);

    // Blend with input image (layer chain compatibility)
    let inputCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var floraColor = mix(inputCol, floraColorBase * depthLayeredAlpha(floraColorBase, uv, depthWeight), 0.85);

    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    floraColor = mix(floraColor, prev, 0.06);

    let feather = glowSpread * 0.5 + 0.05;
    let coverage = max(combinedFlora, max(veins, max(filament, spore)));
    let alpha = volumetricAlpha(coverage, 1.0) * depthLayeredAlpha(floraColorBase, uv, depthWeight) * smoothstep(0.0, feather, coverage);

    let outColor = vec4<f32>(acesToneMap(floraColor), alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
