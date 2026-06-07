// ═══════════════════════════════════════════════════════════════════════════════
//  Aurora Rift 2 - Advanced Alpha with Physical Transmittance
//  Category: atmospheric
//  Alpha Mode: Physical Transmittance (Beer's Law) + Depth-Layered
//  Features: advanced-alpha, volumetric, spectral-rendering
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

// Mode 4: Physical Transmittance (Beer's Law)
fn physicalTransmittance(
    baseColor: vec3<f32>,
    opticalDepth: f32,
    absorptionCoeff: vec3<f32>
) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.3, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined atmospheric alpha
fn calculateAtmosphericAlpha(
    uv: vec2<f32>,
    opticalDepth: f32,
    density: f32,
    params: vec4<f32>
) -> f32 {
    let volAlpha = volumetricAlpha(density, opticalDepth);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

// Noise functions
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Spectral aurora colors
fn auroraColor(t: f32) -> vec3<f32> {
    return vec3<f32>(
        0.2 + 0.8 * sin(t * 6.28),
        0.5 + 0.5 * sin(t * 6.28 + 1.0),
        0.8 + 0.2 * sin(t * 6.28 + 2.0)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y * 2.0 + 0.5;
    let depthWeight = u.zoom_params.z;
    let turbulence = u.zoom_params.w * 3.0 + 1.0;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Aurora curtain simulation
    let curtainUV = uv * vec2<f32>(3.0, 1.0);
    
    // Multiple layers of aurora curtains
    var accumulatedLight = vec3<f32>(0.0);
    var accumulatedOpticalDepth = 0.0;
    
    for (var i: i32 = 0; i < 5; i++) {
        let layer = f32(i);
        let layerOffset = vec2<f32>(time * speed * 0.1 * (1.0 + layer * 0.1), 0.0);
        
        // FBM for curtain shape
        let n1 = fbm(curtainUV + layerOffset + vec2<f32>(layer * 10.0), 4);
        let n2 = fbm(curtainUV * 2.0 - layerOffset * 0.5 + vec2<f32>(layer * 5.0), 3);
        
        // Curtain shape
        let curtainY = 0.3 + n1 * 0.4 + n2 * 0.2;
        let curtainWidth = 0.15 + n2 * 0.1;
        
        // Distance from curtain center
        let distFromCurtain = abs(uv.y - curtainY);
        let curtainIntensity = smoothstep(curtainWidth, 0.0, distFromCurtain);
        
        // Spectral color
        let colorPhase = time * 0.2 + layer * 0.3 + n1;
        let auroraCol = auroraColor(colorPhase) * intensity;
        
        // Optical depth for this layer
        let layerOpticalDepth = curtainIntensity * (0.2 + n1 * 0.3);
        
        // Accumulate with Beer's Law
        let transmittance = exp(-accumulatedOpticalDepth * 2.0);
        accumulatedLight += auroraCol * layerOpticalDepth * transmittance;
        accumulatedOpticalDepth += layerOpticalDepth;
    }
    
    // Sample background
    let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Apply aurora with physical transmittance
    let absorptionCoeff = vec3<f32>(0.5, 0.3, 0.8);
    let transmitted = physicalTransmittance(bgSample.rgb, accumulatedOpticalDepth, absorptionCoeff);
    
    // Final composite
    let finalColor = transmitted + accumulatedLight;
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let density = accumulatedOpticalDepth * 2.0;
    let alpha = calculateAtmosphericAlpha(uv, accumulatedOpticalDepth, density, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Depth pass-through
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
