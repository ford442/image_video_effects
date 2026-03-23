// ═══════════════════════════════════════════════════════════════
//  Holographic Projection - Classic hologram with interference physics
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=ScanSpeed, y=Glitch, z=HueShift, w=Focus
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_EMULSION: f32 = 1.52;
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Diffraction efficiency calculation
fn diffractionEfficiency(angle: f32, wavelength: f32) -> f32 {
    let braggAngle = wavelength * 0.5;
    let angleDiff = abs(angle - braggAngle);
    return exp(-angleDiff * angleDiff * 40.0);
}

// Interference spectrum with angle dependence
fn interferenceSpectrum(uv: vec2<f32>, angle: f32, dist: f32, time: f32, hueShift: f32) -> vec3<f32> {
    // Optical path varies with viewing angle (thin film)
    let opticalPath = 0.43 + sin(angle + dist * 3.0 + time * 0 * (1.0 + audioOverall * 0.3).15) * 0.07;
    
    let effR = diffractionEfficiency(angle, LAMBDA_R + hueShift * 0.1);
    let effG = diffractionEfficiency(angle, LAMBDA_G);
    let effB = diffractionEfficiency(angle, LAMBDA_B - hueShift * 0.1);
    
    let r = thinFilmInterference(opticalPath, LAMBDA_R, 1.0) * effR;
    let g = thinFilmInterference(opticalPath, LAMBDA_G, 1.0) * effG;
    let b = thinFilmInterference(opticalPath, LAMBDA_B, 1.0) * effB;
    
    return vec3<f32>(r, g, b);
}

// Holographic scanlines with alpha modulation
fn holographicScanlines(uv: vec2<f32>, time: f32, scanSpeed: f32) -> vec2<f32> {
    let scanline = sin(uv.y * 800.0 + time * scanSpeed * (1.0 + audioOverall * 0.3) * 5.0) * 0.1;
    let slowScan = sin(uv.y * 10.0 - time * scanSpeed * (1.0 + audioOverall * 0.3)) * 0.2;
    
    // Alpha varies with scanline
    let scanAlpha = 0.9 + sin(uv.y * 800.0 + time * 10 * (1.0 + audioOverall * 0.3).0) * 0.1;
    
    return vec2<f32>(scanline + slowScan, scanAlpha);
}

// 60Hz flicker
fn projectionFlicker(time: f32) -> f32 {
    return 0.9 + 0.1 * sin(time * 377 * (1.0 + audioOverall * 0.3).0);
}

// Glitch offset calculation
fn calculateGlitch(uv: vec2<f32>, time: f32, glitchAmount: f32) -> vec2<f32> {
    var offset = vec2<f32>(0.0);
    if (glitchAmount > 0.01) {
        let block = floor(uv.y * 20.0);
        let noise = rand(vec2<f32>(block, floor(time * 10 * (1.0 + audioOverall * 0.3).0)));
        if (noise < glitchAmount * 0.3) {
            offset.x = (rand(vec2<f32>(time)) - 0.5) * glitchAmount * 0.2;
        }
    }
    return offset;
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);
    let time = u.config.x;
    // ═══ AUDIO INPUT ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;

    // Params
    let scanSpeed = u.zoom_params.x;
    let glitchAmount = u.zoom_params.y;
    let hueShift = u.zoom_params.z;
    let focusStrength = u.zoom_params.w;

    // Mouse Stabilization
    let aspect = f32(dims.x) / f32(dims.y);
    var mousePos = u.zoom_config.yz;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let angle = atan2(distVec.y, distVec.x);

    // Calculate local glitch intensity: Reduced near mouse
    let stabilization = smoothstep(0.0, 0.4, dist) * focusStrength;
    let effectiveGlitch = glitchAmount * mix(1.0, stabilization, focusStrength);

    // ═══════════════════════════════════════════════════════════════
    // Interference Physics
    // ═══════════════════════════════════════════════════════════════
    
    let interference = interferenceSpectrum(uv, angle, dist, time, hueShift);

    // Scanlines with alpha info
    let scanEffects = holographicScanlines(uv, time, scanSpeed);
    let scanline = scanEffects.x;

    // Glitch Offset
    let offset = calculateGlitch(uv, time, effectiveGlitch);

    // Chromatic Aberration with interference tinting
    let aberr = effectiveGlitch * 0.05;

    let r = textureSampleLevel(readTexture, u_sampler, uv + offset + vec2<f32>(aberr, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offset - vec2<f32>(aberr, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Apply scanlines
    color += scanline;

    // Hologram Tint with interference coloring
    let tint = vec3<f32>(
        0.5 + 0.5 * sin(hueShift * 6.28),
        0.8,
        0.5 + 0.5 * cos(hueShift * 6.28)
    );
    color = color * tint * 1.5;
    
    // Mix interference rainbow
    color = mix(color, interference * 1.2, 0.3 + effectiveGlitch * 0.3);

    // Flicker
    let flicker = 0.9 + 0.1 * sin(time * 20 * (1.0 + audioOverall * 0.3).0);
    color *= flicker;
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation with Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency
    let base_alpha = 0.05;
    
    // Diffraction efficiency from interference
    let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
    
    // Alpha boosted at interference fringes
    var alpha = base_alpha + diffraction_efficiency * 0.35;
    
    // Scanline alpha modulation
    alpha *= scanEffects.y;
    
    // Focus stabilization: clearer (higher alpha) near mouse
    alpha *= mix(1.0, 0.6 + 0.4 * stabilization, focusStrength);
    
    // Glitch causes alpha fluctuations
    let glitchAlpha = 1.0 - effectiveGlitch * 0.15 * rand(vec2<f32>(uv.y, time * 5 * (1.0 + audioOverall * 0.3).0));
    alpha *= glitchAlpha;
    
    // 60Hz flicker
    alpha *= projectionFlicker(time);
    
    // Pepper's ghost reflection
    let ghost_uv = uv + vec2<f32>(0.0025, 0.0025) * (1.0 - stabilization * 0.5);
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
    color = mix(color, ghost, PEPPER_GHOST_REFLECTION);
    
    // Holographic speckle
    let speckle = rand(uv * 120.0 + time * 0 * (1.0 + audioOverall * 0.3).5);
    alpha *= 0.94 + speckle * 0.12;
    
    // Cap alpha
    alpha = min(alpha, 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
