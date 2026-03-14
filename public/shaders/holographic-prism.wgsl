// ═══════════════════════════════════════════════════════════════
//  Holographic Prism - Faceted hologram with interference physics
//  Category: artistic
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, dispersion, diffraction efficiency
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
  config: vec4<f32>,       // x=Time, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=FacetDensity, y=Dispersion, z=RotationSpeed, w=Glitch
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_PRISM: f32 = 1.52;  // Glass-like prism material
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Dispersion effect - different wavelengths refract differently
fn dispersionShift(wavelength: f32, dispersionStrength: f32) -> f32 {
    // Shorter wavelengths (blue) refract more than longer (red)
    // wavelength normalized 0-1 where 0=red, 1=blue
    return (1.0 - wavelength) * dispersionStrength;
}

// Prism interference spectrum
fn prismInterference(uv: vec2<f32>, angle: f32, facet_id: f32, time: f32) -> vec3<f32> {
    // Each facet creates its own interference pattern
    let facetPhase = facet_id * 0.5;
    let opticalPath = 0.45 + sin(angle * 2.0 + facetPhase + time * 0.3) * 0.1;
    
    let r = thinFilmInterference(opticalPath, LAMBDA_R, 1.0);
    let g = thinFilmInterference(opticalPath, LAMBDA_G, 1.0);
    let b = thinFilmInterference(opticalPath, LAMBDA_B, 1.0);
    
    return vec3<f32>(r, g, b);
}

// Facet edge diffraction
fn facetDiffraction(facetEdge: f32, angle: f32, wavelength: f32) -> f32 {
    let edgePhase = facetEdge * 10.0 + angle;
    let diffraction = sin(edgePhase * wavelength * 20.0);
    return diffraction * diffraction;
}

// 60Hz flicker
fn projectionFlicker(time: f32) -> f32 {
    return 0.9 + 0.1 * sin(time * 377.0);
}

// Holographic scanline
fn holographicScanline(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let scan = sin(uv.y * 600.0 + time * 20.0) * 0.5 + 0.5;
    return 1.0 - scan * intensity * 0.3;
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
    let time = u.config.x;

    // Parameters
    let facetDensity = mix(3.0, 12.0, u.zoom_params.x);
    let dispersionStr = mix(0.00, 0.05, u.zoom_params.y);
    let rotationSpeed = mix(-1.0, 1.0, u.zoom_params.z);
    let glitchInt = u.zoom_params.w;

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    var center = vec2<f32>(0.5, 0.5);
    var effectiveCenter = center;
    if (mouse.x >= 0.0) {
        effectiveCenter = mouse;
    }

    // Coordinate relative to center
    var p = uv - effectiveCenter;
    p.x = p.x * aspect;

    let dist = length(p);
    let angle = atan2(p.y, p.x);

    // Quantize angle to create shards/facets
    let pi = 3.14159;
    let shards = facetDensity;
    let quantizedAngle = floor(angle / (2.0 * pi) * shards) * (2.0 * pi) / shards;
    let facet_id = f32(floor(angle / (2.0 * pi) * shards));

    // Calculate rotation for this shard
    let rot = quantizedAngle + time * rotationSpeed + dist * 2.0;

    // Rotate the original UV offset around the effective center
    let rotatedOffset = rotate(p, rot * 0.2);

    // Un-aspect correct
    var finalOffset = rotatedOffset;
    finalOffset.x = finalOffset.x / aspect;

    let baseUV = effectiveCenter + finalOffset;

    // ═══════════════════════════════════════════════════════════════
    // Prism Dispersion with Interference Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate interference for this facet
    let interference = prismInterference(uv, angle, facet_id, time);
    
    // Chromatic Abberation / Dispersion with interference coloring
    // Sample R, G, B at slightly different positions based on dispersion physics
    let rOffset = vec2<f32>(dispersionStr * cos(rot) * (1.0 + interference.r), dispersionStr * sin(rot));
    let bOffset = vec2<f32>(-dispersionStr * cos(rot) * (1.0 + interference.b), -dispersionStr * sin(rot));

    let r = textureSampleLevel(readTexture, u_sampler, baseUV + rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, baseUV + bOffset, 0.0).b;

    var finalColor = vec3<f32>(r, g, b);
    
    // Add interference colors to facets
    finalColor = mix(finalColor, interference, 0.4);

    // Holographic Glitch (scanlines + flicker)
    let scanline = sin(uv.y * 600.0 + time * 20.0) * 0.1 * glitchInt;
    let flicker = sin(time * 45.0) * 0.05 * glitchInt;

    finalColor = finalColor + scanline + flicker;
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation with Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency
    let base_alpha = 0.05;
    
    // Diffraction efficiency varies by facet and interference
    let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
    
    // Alpha boosted at facet edges (where diffraction occurs)
    let facetEdge = abs(fract(angle / (2.0 * pi) * shards) - 0.5);
    let edgeDiffraction = facetDiffraction(facetEdge, angle, 0.5);
    
    var alpha = base_alpha + diffraction_efficiency * 0.3 + edgeDiffraction * 0.15 * glitchInt;
    
    // Scanline alpha modulation
    alpha *= holographicScanline(uv, time, 0.4);
    
    // 60Hz flicker
    alpha *= projectionFlicker(time);
    
    // Facet edge highlight with alpha boost
    let edgeHighlight = smoothstep(0.45, 0.5, facetEdge);
    alpha += edgeHighlight * 0.08;
    finalColor += vec3<f32>(0.2, 0.4, 0.6) * edgeHighlight * interference.b;
    
    // Pepper's ghost reflection
    let ghost_uv = uv + vec2<f32>(0.002, 0.002);
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb;
    finalColor = mix(finalColor, ghost * interference, PEPPER_GHOST_REFLECTION);
    
    // Speckle noise
    let speckle = fract(sin(dot(uv * 80.0 + time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    alpha *= 0.94 + speckle * 0.1;
    
    // Cap alpha
    alpha = min(alpha, 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
