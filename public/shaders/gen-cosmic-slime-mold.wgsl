// ═══════════════════════════════════════════════════════════════════
//  Cosmic Slime Mold
//  Category: generative
//  Features: slime-mold, cosmic, organic, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Hash functions
fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// Fractal Brownian Motion
fn fbm(p: vec2<f32>) -> f32 {
    var val: f32 = 0.0;
    var amp: f32 = 0.5;
    var freq: f32 = 1.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        val += amp * vnoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// Ridged noise for vein structures
fn ridgedNoise(p: vec2<f32>) -> f32 {
    return 1.0 - abs(vnoise(p) * 2.0 - 1.0);
}

// Ridged FBM for dendritic patterns
fn rfbm(p: vec2<f32>) -> f32 {
    var val: f32 = 0.0;
    var amp: f32 = 0.5;
    var freq: f32 = 1.0;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        val += amp * ridgedNoise(p * freq);
        freq *= 2.1;
        amp *= 0.55;
    }
    return val;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Physarum growth ~1 mm/h, Steiner tree approximation
fn slimeGradient(p: vec2<f32>, time: f32) -> vec2<f32> {
    // Nutrient gradient following: moves toward higher chemoattractant concentrations
    let chemotaxis = 0.3;
    let nR = vnoise(p + vec2<f32>(0.01, 0.0) + time * 0.05);
    let nL = vnoise(p - vec2<f32>(0.01, 0.0) + time * 0.05);
    let nU = vnoise(p + vec2<f32>(0.0, 0.01) + time * 0.05);
    let nD = vnoise(p - vec2<f32>(0.0, 0.01) + time * 0.05);
    return vec2<f32>(nR - nL, nU - nD) * chemotaxis * 10.0;
}

// 2D rotation
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Slime color gradient: deep purple -> hot pink -> electric cyan
fn slimeColor(t: f32) -> vec3<f32> {
    let c0 = vec3<f32>(0.25, 0.0, 0.45);    // Deep purple
    let c1 = vec3<f32>(0.7, 0.0, 0.6);      // Magenta
    let c2 = vec3<f32>(1.0, 0.08, 0.58);    // Hot pink
    let c3 = vec3<f32>(0.0, 0.85, 1.0);      // Electric cyan
    let c4 = vec3<f32>(0.0, 1.0, 0.6);       // Neon green edge

    let tt = clamp(t, 0.0, 1.0);
    if (tt < 0.25) {
        return mix(c0, c1, tt / 0.25);
    } else if (tt < 0.5) {
        return mix(c1, c2, (tt - 0.25) / 0.25);
    } else if (tt < 0.75) {
        return mix(c2, c3, (tt - 0.5) / 0.25);
    } else {
        return mix(c3, c4, (tt - 0.75) / 0.25);
    }
}

// Dendritic branching SDF - returns distance to vein structure
fn veinStructure(p: vec2<f32>, seed: f32, scale: f32, time: f32) -> f32 {
    // Multiple branching levels
    var d: f32 = 1000.0;

    // Main trunk
    let n1 = vnoise(vec2<f32>(p.x * 2.0 * scale, seed));
    let trunk = abs(p.y - n1 * 0.4);
    d = min(d, trunk);

    // Branch 1
    let branchAngle1 = 0.6 + sin(seed * 3.0 + time * 0.5) * 0.3;
    let b1 = rot2(branchAngle1) * p;
    let n2 = vnoise(vec2<f32>(b1.x * 3.0 * scale, seed + 10.0));
    let branch1 = abs(b1.y - n2 * 0.2);
    d = min(d, branch1);

    // Branch 2
    let branchAngle2 = -0.5 + cos(seed * 2.0 + time * 0.3) * 0.2;
    let b2 = rot2(branchAngle2) * p;
    let n3 = vnoise(vec2<f32>(b2.x * 3.5 * scale, seed + 20.0));
    let branch2 = abs(b2.y - n3 * 0.18);
    d = min(d, branch2);

    // Branch 3 - finer
    let branchAngle3 = 1.2 + sin(seed * 5.0 + time * 0.7) * 0.4;
    let b3 = rot2(branchAngle3) * p;
    let n4 = vnoise(vec2<f32>(b3.x * 5.0 * scale, seed + 30.0));
    let branch3 = abs(b3.y - n4 * 0.12);
    d = min(d, branch3);

    return d;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
    let uv01 = vec2<f32>(pixel) / resolution;
    let time = u.config.x;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseDown = u.zoom_config.w;
    let mouseNorm = (mouse - resolution * 0.5) / min(resolution.x, resolution.y);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = u.zoom_params.x * (1.0 + bass * 1.5);
    let speed = u.zoom_params.y * (1.0 + mids * 2.0);
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    var col = vec3<f32>(0.0);

    // Dark cosmic background
    let bgStars = vnoise(uv * 25.0);
    let starMask = smoothstep(0.88, 0.95, bgStars);
    col += vec3<f32>(0.5, 0.7, 1.0) * starMask * 0.3 * (1.0 + treble * 2.0);
    col += vec3<f32>(0.03, 0.0, 0.08);

    // Subtle nebula background
    let nebula = fbm(uv * 3.0 + vec2<f32>(time * 0.02 * speed, time * 0.03 * speed));
    col += slimeColor(fract(nebula * 0.3 + colorShift)) * nebula * 0.1;

    // ---- SLIME MOLD VEINS ----
    // Multiple vein networks growing from different seed points
    let numVeins = 6;
    for (var v: i32 = 0; v < numVeins; v = v + 1) {
        let fv = f32(v);
        let seed = fv * 17.31 + 100.0;

        // Seed point for this vein network
        let seedAngle = seed * 0.7 + time * 0.1 * speed;
        let seedRadius = 0.1 + 0.3 * abs(sin(seed * 0.5));
        var seedPos = vec2<f32>(cos(seedAngle), sin(seedAngle)) * seedRadius;

        // Mouse feeding - veins grow toward mouse when down
        if (mouseDown > 0.5) {
            let toMouse = mouseNorm - seedPos;
            seedPos += toMouse * 0.3;
        }

        // Local coordinates relative to seed
        let localP = uv - seedPos;
        let nutrientGrad = slimeGradient(localP, time);
        let scaledP = (localP + nutrientGrad * 0.05) * (1.5 + 2.0 * scale);

        // Growth factor - veins extend over time with pulses
        let growthPhase = fract(time * 0.06 * speed + fv * 0.17);
        let growthPulse = smoothstep(0.0, 0.3, growthPhase) * (1.0 - smoothstep(0.7, 1.0, growthPhase));
        let extraGrowth = mouseDown * 0.5 * (1.0 + 0.5 * sin(time * 4.0 * speed));
        let growth = growthPhase + extraGrowth;

        // Vein distance field
        let vDist = veinStructure(scaledP, seed, scale, time);

        // Dendritic noise overlay for organic texture
        let dendrite = rfbm(scaledP * 2.0 + seed);
        let dendrite2 = rfbm(scaledP * 3.5 + seed + 50.0);

        // Combined vein mask
        let veinWidth = 0.015 * (1.0 + growth * 0.5) / scale;
        let veinMask = smoothstep(veinWidth, 0.0, vDist) * growth;
        let dendriteMask = smoothstep(0.35, 0.65, dendrite) * smoothstep(0.3, 0.7, dendrite2) * growth * 0.4 * (1.0 + treble * 2.0);

        let combinedMask = max(veinMask, dendriteMask);

        // Tip glow - bright leading edge
        let tipRadius = growth * 0.5;
        let distFromSeed = length(localP);
        let tipMask = smoothstep(tipRadius + 0.05, tipRadius - 0.05, distFromSeed)
                    * smoothstep(tipRadius - 0.15, tipRadius - 0.05, distFromSeed);

        // Color based on vein age/distance from center
        let colorT = fract(fv / f32(numVeins) + growth * 0.3 + colorShift + distFromSeed * 0.5);
        let veinColor = slimeColor(colorT);
        let tipColor = vec3<f32>(1.0, 0.9, 0.7); // Bright tip

        // Contribution
        col += veinColor * combinedMask * intensity * 2.0;
        col += tipColor * tipMask * intensity * 1.5 * (1.0 + treble * 2.0);

        // Glow around veins
        let glowMask = smoothstep(veinWidth * 4.0, 0.0, vDist) * growth * 0.3;
        col += veinColor * glowMask * intensity * 0.8;
    }

    // ---- FEEDER ZONES AT MOUSE ----
    if (mouseDown > 0.5) {
        // Rapid growth pulse at mouse position
        let mouseDist = length(uv - mouseNorm);
        let feedGlow = exp(-mouseDist * mouseDist * 20.0);
        let feedPulse = 0.5 + 0.5 * sin(time * 8.0 * speed);

        // Spreading tendrils from mouse
        let tendril = rfbm((uv - mouseNorm) * 5.0 * scale + time * speed);
        let tendrilMask = smoothstep(0.4, 0.7, tendril) * smoothstep(0.5, 0.0, mouseDist);

        let feedColor = slimeColor(fract(time * 0.1 * speed + colorShift + 0.3));
        col += feedColor * feedGlow * feedPulse * intensity * 4.0;
        col += feedColor * tendrilMask * intensity * 2.5;

        // Core white-hot spot
        let coreGlow = exp(-mouseDist * mouseDist * 80.0);
        col += vec3<f32>(1.0, 0.8, 0.9) * coreGlow * intensity * 3.0 * (1.0 + treble);
    }

    // Global organic noise overlay
    let organicNoise = vnoise(uv * 8.0 * scale + time * speed * 0.5);
    let organicMask = smoothstep(0.4, 0.6, organicNoise) * 0.1 * intensity;
    col += slimeColor(fract(time * 0.05 * speed + colorShift)) * organicMask;

    // Pulsing vignette
    let vigPulse = 1.0 + 0.1 * sin(time * 2.0 * speed);
    let vig = 1.0 - dot(uv * 0.7, uv * 0.7) * vigPulse;
    col *= clamp(vig, 0.0, 1.0) * 1.3;

    // Read depth for chromatic aberration
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // ACES tone map
    col = acesToneMap(col);
    col = pow(col, vec3<f32>(0.9));

    // Brightness boost
    col = col * 2.0;

    // Semantic alpha
    let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

    // Temporal feedback
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, col, 0.25);
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, alpha));

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
}
