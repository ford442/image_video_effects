// ═══════════════════════════════════════════════════════════════
//  Domain-Warped FBM Grid
//  Category: generative
//  Features: domain warping, FBM noise, organic movement
//  
//  Scientific Concept:
//  - Domain Warping: distort UV coordinates with noise before sampling
//  - FBM (Fractal Brownian Motion): Sum multiple octaves of noise
//  - f(p) = fbm(p + fbm(p + fbm(p))) - nested distortion
//
//  Artistic Vision:
//  - Grid lines that flow and undulate like fabric in wind
//  - Organic movement rather than rigid geometric animation
//  - Depth through varying line thickness based on distortion
//  - Color gradients based on distortion magnitude
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // x=time, y=rippleCount, z=resolutionX, w=resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=distortionAmount, y=gridScale, z=lineThickness, w=colorShift
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
//  Hash Functions - Simple pseudo-random number generation
// ═══════════════════════════════════════════════════════════════
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yzz) * p.zyx);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══════════════════════════════════════════════════════════════
//  Value Noise - Smooth interpolation between random values
// ═══════════════════════════════════════════════════════════════
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    // Quintic interpolation curve
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    // Four corners
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ═══════════════════════════════════════════════════════════════
//  FBM (Fractal Brownian Motion) - Sum multiple octaves of noise
//  Each octave has half the amplitude and double the frequency
// ═══════════════════════════════════════════════════════════════
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    
    return value;
}

// ═══════════════════════════════════════════════════════════════
//  Domain Warping - Nested FBM distortion
//  f(p) = fbm(p + fbm(p + fbm(p)))
//  Creates organic, flowing distortions
// ═══════════════════════════════════════════════════════════════
fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
    // First level of distortion
    let q = vec2<f32>(
        fbm(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
        fbm(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
    );
    
    // Second level - nested distortion
    let r = vec2<f32>(
        fbm(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
        fbm(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
    );
    
    // Final displacement
    var warped = uv + amount * r;
    
    return warped;
}

// ═══════════════════════════════════════════════════════════════
//  Grid Line Function - Draw grid using warped coordinates
// ═══════════════════════════════════════════════════════════════
fn gridLine(warpedUV: vec2<f32>, gridSize: f32, thickness: f32) -> vec4<f32> {
    // Calculate grid positions
    let gridPos = warpedUV * gridSize;
    let gridFract = fract(gridPos - 0.5) - 0.5;
    
    // Distance to nearest grid line
    let lineDist = abs(gridFract);
    let nearestLine = min(lineDist.x, lineDist.y);
    
    // Vary thickness based on distortion (more distorted = thicker lines)
    let adjustedThickness = thickness * (1.0 + length(gridFract) * 0.5);
    
    // Grid intensity with smooth falloff
    var intensity = 1.0 - smoothstep(0.0, adjustedThickness, nearestLine);
    
    // Secondary glow for neon effect
    let glow = 0.3 * (1.0 - smoothstep(0.0, adjustedThickness * 3.0, nearestLine));
    
    return vec4<f32>(intensity, glow, nearestLine, adjustedThickness);
}

// ═══════════════════════════════════════════════════════════════
//  Color Palette - Gradient based on distortion amount
// ═══════════════════════════════════════════════════════════════
fn colorPalette(t: f32, shift: f32) -> vec3<f32> {
    // Cyberpunk palette: cyan → blue → magenta → purple
    let cyan = vec3<f32>(0.0, 1.0, 0.9);
    let blue = vec3<f32>(0.1, 0.4, 1.0);
    let magenta = vec3<f32>(1.0, 0.0, 0.8);
    let purple = vec3<f32>(0.6, 0.0, 1.0);
    let gold = vec3<f32>(1.0, 0.7, 0.1);
    
    let shiftedT = fract(t + shift);
    
    var color: vec3<f32>;
    if (shiftedT < 0.25) {
        color = mix(cyan, blue, shiftedT * 4.0);
    } else if (shiftedT < 0.5) {
        color = mix(blue, magenta, (shiftedT - 0.25) * 4.0);
    } else if (shiftedT < 0.75) {
        color = mix(magenta, purple, (shiftedT - 0.5) * 4.0);
    } else {
        color = mix(purple, gold, (shiftedT - 0.75) * 4.0);
    }
    
    return color;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    
    // Pixel coordinate to 0-1 UV
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    // Get parameters from uniforms (with defaults)
    let distortionAmount = u.zoom_params.x;  // 0.0 to 1.0
    let gridScale = u.zoom_params.y;         // 0.5 to 3.0
    let lineThickness = u.zoom_params.z;     // 0.01 to 0.1
    let colorShift = u.zoom_params.w;        // 0.0 to 1.0
    
    // Apply defaults if parameters are not set
    let warpAmount = select(0.4, distortionAmount, distortionAmount > 0.001);
    let scale = select(1.5, gridScale, gridScale > 0.1);
    let thickness = select(0.03, lineThickness, lineThickness > 0.001);
    let shift = select(0.0, colorShift, colorShift > 0.001);
    
    // Aspect correction for square grid cells
    let aspect = resolution.x / resolution.y;
    var p = uv;
    p.x *= aspect;
    
    // ═══════════════════════════════════════════════════════════
    //  Domain Warping Application
    //  Transform rigid UV space into flowing organic coordinates
    // ═══════════════════════════════════════════════════════════
    let warpedP = domainWarp(p, time, scale * 2.0, warpAmount);
    
    // Calculate distortion magnitude for color effects
    let distortionMag = length(warpedP - p);
    
    // ═══════════════════════════════════════════════════════════
    //  Grid Rendering with Warped Coordinates
    // ═══════════════════════════════════════════════════════════
    let gridSize = 8.0;
    let gridResult = gridLine(warpedP, gridSize, thickness);
    
    let lineIntensity = gridResult.x;
    let lineGlow = gridResult.y;
    let nearestDist = gridResult.z;
    
    // ═══════════════════════════════════════════════════════════
    //  Color Composition
    // ═══════════════════════════════════════════════════════════
    // Base color from palette, shifted by distortion and time
    let colorT = distortionMag * 2.0 + time * 0.05 + shift;
    let baseColor = colorPalette(colorT, shift);
    
    // Secondary accent color for depth
    let accentT = distortionMag * 3.0 - time * 0.03 + 0.5 + shift;
    let accentColor = colorPalette(accentT, shift + 0.25);
    
    // Mix colors based on distortion
    let mixFactor = smoothstep(0.0, 0.5, distortionMag);
    let lineColor = mix(baseColor, accentColor, mixFactor);
    
    // ═══════════════════════════════════════════════════════════
    //  Final Color Assembly
    // ═══════════════════════════════════════════════════════════
    var finalColor = vec3<f32>(0.02, 0.02, 0.05); // Dark background
    
    // Add grid lines with glow
    finalColor = finalColor + lineColor * lineIntensity;
    finalColor = finalColor + lineColor * lineGlow * 0.5;
    
    // Add subtle ambient glow based on distortion
    finalColor = finalColor + accentColor * distortionMag * 0.15;
    
    // Vignette effect (subtle darkening at edges)
    let vignetteUV = uv * (1.0 - uv);
    let vignette = vignetteUV.x * vignetteUV.y * 15.0;
    finalColor = finalColor * clamp(vignette, 0.0, 1.0);
    
    // Tone mapping for better contrast
    finalColor = pow(finalColor, vec3<f32>(0.85));
    
    // Output to color texture
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    
    // Output depth (store distortion magnitude as depth for potential effects)
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(distortionMag, 0.0, 0.0, 0.0));
}


