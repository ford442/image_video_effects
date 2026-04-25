// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Xeno Botanical Synth Flora - L-System Growth Simulation
//  Category: generative
//  Alpha Mode: Depth-Layered Alpha + Physical Transmittance
//  Features: advanced-alpha, botanical, generative, depth-aware, l-system
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
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioMid = plasmaBuffer[0].y;
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

    // Main stem with L-system fractal branching
    let branchAngle = angle + time * 0.2 * audioReactivity;
    let branchPattern = branchDensity(centered, branchAngle, complexity, time);

    // Turing pattern venation on leaves
    let venation = turingPattern(uv * 3.0, time * 0.5);

    // Organic noise for bark texture
    let barkNoise = fbm(floor(uv * 20.0) + time * 0.1 * audioReactivity, 3);

    // Leaf shapes at branch tips
    let leafUV = (fract(uv * 4.0) - 0.5) * 2.0;
    let leafDist = sdLeaf(leafUV, 0.8, 0.3);
    let leafMask = smoothstep(0.05, -0.05, leafDist);

    // Combine structures
    let flora = smoothstep(0.0, 0.5 + glowSpread * barkNoise, branchPattern * growth);
    let leafFlora = leafMask * venation * growth;
    let combinedFlora = max(flora, leafFlora);

    // Nutrient flow visualization (green channel emphasis)
    let nutrient = fbm(uv * 8.0 + vec2<f32>(time * 0.1, 0.0), 2) * growth;

    // Bioluminescence (blue channel, pulsing)
    let bioPulse = sin(time * 2.0 + radius * 10.0) * 0.5 + 0.5;
    let biolum = bioPulse * leafMask * audioReactivity;

    // Color encoding: R=branch ID, G=nutrient, B=bioluminescence
    let floraColorBase = vec3<f32>(
        0.15 + combinedFlora * 0.5 + lSystemIterate(u32(uv.x * 100.0), u32(uv.y * 100.0), 3) * 0.2,
        0.4 + nutrient * 0.4 + combinedFlora * 0.3,
        0.2 + biolum * 0.6 + combinedFlora * 0.2
    );

    // Blend with input image (layer chain compatibility)
    let inputCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let floraColor = mix(inputCol, floraColorBase * depthLayeredAlpha(floraColorBase, uv, depthWeight), 0.85);

    let feather = glowSpread * 0.5 + 0.05;
    let alpha = volumetricAlpha(combinedFlora, 1.0) * depthLayeredAlpha(floraColorBase, uv, depthWeight) * smoothstep(0.0, feather, combinedFlora);

    textureStore(writeTexture, global_id.xy, vec4<f32>(floraColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
