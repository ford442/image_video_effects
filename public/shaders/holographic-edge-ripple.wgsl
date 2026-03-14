// ═══════════════════════════════════════════════════════════════
//  Holographic Edge Ripple - Ripple hologram with interference physics
//  Category: artistic
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, diffraction efficiency, 60Hz flicker
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=WaveSpeed, y=Frequency, z=Aberration, w=EdgeThreshold
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_EMULSION: f32 = 1.52;
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized 0-1)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Interference & Physics Functions
// ═══════════════════════════════════════════════════════════════

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Thin-film interference calculation
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Wavelength-dependent diffraction efficiency
fn wavelengthDiffraction(uv: vec2<f32>, angle: f32, wavelength: f32) -> f32 {
    // Simulate diffraction grating efficiency variation
    let braggAngle = wavelength * 0.5;
    let angleDiff = abs(angle - braggAngle);
    return exp(-angleDiff * angleDiff * 50.0);
}

// Rainbow interference pattern
fn interferenceSpectrum(uv: vec2<f32>, angle: f32, dist: f32, time: f32) -> vec3<f32> {
    // Optical path varies with viewing angle
    let opticalPath = 0.43 + sin(angle + dist * 5.0) * 0.05;
    
    let r = thinFilmInterference(opticalPath, LAMBDA_R, 1.0);
    let g = thinFilmInterference(opticalPath, LAMBDA_G, 1.0);
    let b = thinFilmInterference(opticalPath, LAMBDA_B, 1.0);
    
    // Angle-dependent intensity
    let effR = wavelengthDiffraction(uv, angle, LAMBDA_R);
    let effG = wavelengthDiffraction(uv, angle, LAMBDA_G);
    let effB = wavelengthDiffraction(uv, angle, LAMBDA_B);
    
    return vec3<f32>(r * effR, g * effG, b * effB);
}

// Holographic scanline effect with alpha modulation
fn holographicScanlines(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    // Horizontal scanlines
    let scanFreq = 800.0;
    let scanline = sin(uv.y * scanFreq + time * 5.0) * 0.5 + 0.5;
    
    // Slow vertical scan (bar effect)
    let barPos = fract(time * 0.2);
    let barEffect = 1.0 - smoothstep(0.0, 0.05, abs(uv.y - barPos));
    
    return vec2<f32>(scanline, barEffect * intensity);
}

// 60Hz flicker typical of holographic displays
fn projectionFlicker(time: f32) -> f32 {
    return 0.9 + 0.1 * sin(time * 377.0); // 60Hz
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let texel = 1.0 / resolution;
    let time = u.config.x;

    // Parameters
    let waveSpeed = u.zoom_params.x;
    let frequency = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let edgeThreshold = u.zoom_params.w;

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;

    // Calculate aspect-corrected distance to mouse
    let aspect = resolution.x / resolution.y;
    let aspect_uv = vec2<f32>(uv.x * aspect, uv.y);
    let aspect_mouse = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(aspect_uv, aspect_mouse);
    let angle = atan2(uv.y - mousePos.y, (uv.x - mousePos.x) * aspect);

    // Sobel Edge Detection
    let c00 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb;
    let c10 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, -1.0), 0.0).rgb;
    let c20 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, -1.0), 0.0).rgb;
    let c01 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 0.0), 0.0).rgb;
    let c21 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 0.0), 0.0).rgb;
    let c02 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 1.0), 0.0).rgb;
    let c12 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, 1.0), 0.0).rgb;
    let c22 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 1.0), 0.0).rgb;

    let gx = -luminance(c00) - 2.0 * luminance(c10) - luminance(c20) + luminance(c02) + 2.0 * luminance(c12) + luminance(c22);
    let gy = -luminance(c00) - 2.0 * luminance(c01) - luminance(c02) + luminance(c20) + 2.0 * luminance(c21) + luminance(c22);
    let edgeVal = length(vec2<f32>(gx, gy));

    // Create edge mask
    let isEdge = smoothstep(edgeThreshold * 0.5, edgeThreshold, edgeVal);

    // Calculate Ripple
    let wave = sin(dist * frequency - time * waveSpeed);

    // ═══════════════════════════════════════════════════════════════
    // Holographic Interference & Alpha
    // ═══════════════════════════════════════════════════════════════
    
    // Base alpha for hologram (mostly transparent)
    let base_alpha = 0.05;
    
    // Calculate interference pattern at this point
    let interference = interferenceSpectrum(uv, angle, dist, time);
    
    // Diffraction efficiency peaks at edges and ripples
    let diffraction_efficiency = isEdge * 0.8 + abs(wave) * 0.4;
    
    // Apply Aberration with interference coloring
    let localAberration = aberration * (1.0 + isEdge * 2.0) * (1.0 / (dist + 0.1));
    let aberrPhase = wave * 6.28;
    
    let offsetR = vec2<f32>(localAberration * cos(aberrPhase), 0.0);
    let offsetG = vec2<f32>(0.0, localAberration * sin(aberrPhase));
    let offsetB = vec2<f32>(-localAberration * cos(aberrPhase), -localAberration * sin(aberrPhase));

    let colorR = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let colorG = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let colorB = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    var finalColor = vec3<f32>(colorR, colorG, colorB);
    
    // Mix in interference colors at edges
    finalColor = mix(finalColor, interference, isEdge * 0.7);

    // Edge glow from interference fringes
    let glowColor = vec3<f32>(0.3 + 0.7 * interference.r, 0.5 + 0.5 * interference.g, 0.7 + 0.3 * interference.b);
    finalColor = mix(finalColor, glowColor, isEdge * 0.6 * abs(wave));
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Alpha boosted at interference fringes (edges and ripples)
    var alpha = base_alpha + diffraction_efficiency * 0.35;
    
    // Scanline alpha modulation
    let scanEffects = holographicScanlines(uv, time, 0.3);
    alpha *= 0.85 + scanEffects.x * 0.15;
    
    // Add scan bar intensity
    alpha += scanEffects.y * 0.1;
    
    // 60Hz flicker
    alpha *= projectionFlicker(time);
    
    // Pepper's ghost reflection effect
    let ghost_uv = uv + vec2<f32>(0.002, 0.002);
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
    finalColor = mix(finalColor, ghost, PEPPER_GHOST_REFLECTION * 0.5);
    
    // Holographic speckle noise
    let speckle = fract(sin(dot(uv * 100.0 + time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    alpha *= 0.95 + speckle * 0.08;
    
    // Cap alpha for transparency
    alpha = min(alpha, 0.5);

    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
