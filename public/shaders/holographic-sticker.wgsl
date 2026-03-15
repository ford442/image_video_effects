// ═══════════════════════════════════════════════════════════════
//  Holographic Sticker - Foil hologram with interference physics
//  Category: artistic
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, foil reflection, 60Hz flicker
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_FOIL: f32 = 1.45;   // Holographic foil refractive index
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Hue to RGB
fn hue_to_rgb(h: f32) -> vec3<f32> {
    let r = abs(h * 6.0 - 3.0) - 1.0;
    let g = 2.0 - abs(h * 6.0 - 2.0);
    let b = 2.0 - abs(h * 6.0 - 4.0);
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Thin-film interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Foil diffraction (microscopic ridges on holographic foil)
fn foilDiffraction(uv: vec2<f32>, viewAngle: f32, wavelength: f32) -> f32 {
    // Holographic foil has microscopic diffraction grating
    let gratingFreq = 500.0; // lines per mm scale
    let ridgePattern = sin(uv.x * gratingFreq + uv.y * gratingFreq * 0.3);
    
    // Viewing angle affects which wavelength is visible
    let angleShift = viewAngle * 2.0;
    let diffraction = sin(ridgePattern * 3.14159 + angleShift / wavelength);
    
    return diffraction * diffraction;
}

// Holographic foil interference spectrum
fn foilInterference(uv: vec2<f32>, viewAngle: f32, tilt: vec2<f32>, time: f32) -> vec3<f32> {
    // Tilt affects optical path through foil
    let tiltEffect = dot(tilt, vec2<f32>(0.5)) * 0.1;
    let opticalPath = 0.4 + tiltEffect + sin(viewAngle * 2.0) * 0.05;
    
    let diffR = foilDiffraction(uv, viewAngle, LAMBDA_R);
    let diffG = foilDiffraction(uv, viewAngle, LAMBDA_G);
    let diffB = foilDiffraction(uv, viewAngle, LAMBDA_B);
    
    let intR = thinFilmInterference(opticalPath, LAMBDA_R, 1.0) * diffR;
    let intG = thinFilmInterference(opticalPath, LAMBDA_G, 1.0) * diffG;
    let intB = thinFilmInterference(opticalPath, LAMBDA_B, 1.0) * diffB;
    
    return vec3<f32>(intR, intG, intB);
}

// 60Hz flicker
fn projectionFlicker(time: f32) -> f32 {
    return 0.92 + 0.08 * sin(time * 377.0);
}

// Sparkle effect from foil
fn foilSparkle(uv: vec2<f32>, time: f32) -> f32 {
    let sparkle = hash(uv * 200.0 + time * 0.5);
    return step(0.97, sparkle) * sparkle;
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // Mouse interaction for light direction / foil tilt
    var mouse = u.zoom_config.yz;
    let tilt = (mouse - 0.5) * 2.0; // -1 to 1
    let viewAngle = atan2(tilt.y, tilt.x);

    // Sample texture and calculate luminance
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // Calculate normal from luminance gradient
    let offset = 1.0 / resolution;
    let lum_r = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lum_u = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Normal vector (perturbed by luminance)
    let normal = normalize(vec3<f32>(lum - lum_r, lum - lum_u, 0.05));

    // View vector is effectively perpendicular to screen + tilt
    let view = normalize(vec3<f32>(0.0, 0.0, 1.0));

    // Light vector driven by mouse/tilt
    let light = normalize(vec3<f32>(-tilt.x, -tilt.y, 0.5));

    // Specular reflection
    let half_vec = normalize(light + view);
    let NdotH = max(dot(normal, half_vec), 0.0);
    let specular = pow(NdotH, 10.0);

    // ═══════════════════════════════════════════════════════════════
    // Foil Interference Physics
    // ═══════════════════════════════════════════════════════════════
    
    let interference = foilInterference(uv, viewAngle, tilt, time);
    
    // Prismatic color shift based on viewing angle and position
    // We add interference to simulate the "sparkle" of the foil
    let sparkle = hash(uv * 100.0) * 0.2 + foilSparkle(uv, time) * 0.5;
    let prism_val = specular + (uv.x + uv.y) * 0.5 + time * 0.1 + sparkle;
    
    // Combine interference with prismatic rainbow
    let rainbow = hue_to_rgb(fract(prism_val)) * (0.5 + interference * 0.5);

    // Foil mask: brighter areas get more foil effect
    let foil_mask = smoothstep(0.2, 0.8, lum);

    // Combine: Base image + Rainbow Specular with interference
    var final_color = mix(color, rainbow, specular * foil_mask * 0.8);

    // Add a bit of the rainbow to the base color based on tilt to simulate ambient iridescence
    final_color += rainbow * 0.1 * foil_mask;
    
    // Add interference colors
    final_color = mix(final_color, interference, foil_mask * 0.3);
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation with Foil Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency (foil is semi-transparent)
    let base_alpha = 0.08;
    
    // Diffraction efficiency from interference
    let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
    
    // Alpha boosted where foil reflects (specular highlights)
    var alpha = base_alpha + diffraction_efficiency * 0.25 + specular * foil_mask * 0.2;
    
    // Sparkles increase alpha momentarily
    alpha += foilSparkle(uv, time) * 0.15;
    
    // 60Hz flicker
    alpha *= projectionFlicker(time);
    
    // Bright areas of image contribute to alpha
    alpha += lum * 0.1 * foil_mask;
    
    // Pepper's ghost reflection (faint secondary image)
    let ghost_uv = uv + tilt * 0.003;
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
    final_color = mix(final_color, ghost, PEPPER_GHOST_REFLECTION * 0.5);
    
    // Speckle noise
    let speckle = hash(uv * 150.0 + time);
    alpha *= 0.95 + speckle * 0.08;
    
    // Cap alpha
    alpha = min(alpha, 0.55);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, alpha));
    
    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
