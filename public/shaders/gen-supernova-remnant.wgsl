// ═══════════════════════════════════════════════════════════════════
//  Supernova Remnant - Expanding shell structures with shockwave physics
//  Category: generative
//  Features: procedural, shockwave physics, turbulence
//  Created: 2026-03-22
//  By: Agent 4A
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

// Noise functions
fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    return mix(
        mix(
            mix(hash31(vec3<f32>(n + 0.0)), hash31(vec3<f32>(n + 1.0)), f.x),
            mix(hash31(vec3<f32>(n + 157.0)), hash31(vec3<f32>(n + 158.0)), f.x),
            f.y
        ),
        mix(
            mix(hash31(vec3<f32>(n + 113.0)), hash31(vec3<f32>(n + 114.0)), f.x),
            mix(hash31(vec3<f32>(n + 270.0)), hash31(vec3<f32>(n + 271.0)), f.x),
            f.y
        ),
        f.z
    );
}

// FBM for turbulence
fn fbm(p: vec3<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec3<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Turbulence displacement
fn turbulence(uv: vec2<f32>, t: f32, chaos: f32) -> vec2<f32> {
    let scale = 5.0;
    let n1 = fbm(vec3<f32>(uv * scale, t * 0.3), 4);
    let n2 = fbm(vec3<f32>(uv * scale + 100.0, t * 0.3), 4);
    return vec2<f32>(n1, n2) * chaos;
}

// Shell density at radius
fn shellDensity(r: f32, shellRadius: f32, thickness: f32) -> f32 {
    let d = abs(r - shellRadius);
    return smoothstep(thickness, 0.0, d);
}

// Temperature to color (blackbody approximation)
fn temperatureColor(temp: f32) -> vec3<f32> {
    // temp 0-1 maps from white-hot to cool red/purple
    if (temp > 0.8) {
        return mix(vec3<f32>(1.0, 1.0, 0.8), vec3<f32>(1.0, 1.0, 1.0), (temp - 0.8) / 0.2);
    } else if (temp > 0.6) {
        return mix(vec3<f32>(1.0, 0.8, 0.3), vec3<f32>(1.0, 1.0, 0.8), (temp - 0.6) / 0.2);
    } else if (temp > 0.4) {
        return mix(vec3<f32>(0.9, 0.4, 0.1), vec3<f32>(1.0, 0.8, 0.3), (temp - 0.4) / 0.2);
    } else if (temp > 0.2) {
        return mix(vec3<f32>(0.6, 0.2, 0.3), vec3<f32>(0.9, 0.4, 0.1), (temp - 0.2) / 0.2);
    } else {
        return mix(vec3<f32>(0.2, 0.1, 0.3), vec3<f32>(0.6, 0.2, 0.3), temp / 0.2);
    }
}

// Rayleigh-Taylor instability pattern
fn rayleighTaylor(uv: vec2<f32>, t: f32) -> f32 {
    let n1 = fbm(vec3<f32>(uv * 8.0, t * 0.2), 3);
    let n2 = fbm(vec3<f32>(uv * 16.0 + n1, t * 0.3), 3);
    return n1 * n2;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let explosionEnergy = mix(0.3, 1.5, u.zoom_params.x);
    let shellDensityParam = mix(3.0, 12.0, u.zoom_params.y);
    let chaos = mix(0.1, 0.8, u.zoom_params.z);
    let colorTempShift = mix(-0.2, 0.2, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    
    // Apply turbulence displacement
    let turb = turbulence(p + 0.5, t, chaos);
    let pTurb = p + turb * 0.1;
    
    // Polar coordinates
    let r = length(pTurb);
    let angle = atan2(pTurb.y, pTurb.x);
    
    // Generate multiple expanding shells
    var col = vec3<f32>(0.0);
    var totalDensity = 0.0;
    
    let numShells = i32(shellDensityParam);
    for (var i: i32 = 0; i < numShells; i++) {
        let fi = f32(i);
        
        // Each shell has different speed (inner shells faster)
        let speed = explosionEnergy * (1.0 + 0.2 * fi);
        let shellAge = fract(t * 0.05 * speed + fi * 0.1);
        let shellRadius = shellAge * 0.8;
        
        // Shell thickness varies with age
        let thickness = 0.03 + 0.02 * shellAge;
        
        // Rayleigh-Taylor fingers at shell edge
        let fingers = rayleighTaylor(vec2<f32>(r, angle * 2.0), t + fi);
        let fingerMod = 1.0 + fingers * chaos;
        
        // Density with modulation
        let d = shellDensity(r * fingerMod, shellRadius, thickness);
        
        // Temperature decreases with age
        let temp = (1.0 - shellAge) * 0.9 + 0.1 + colorTempShift;
        
        // Add turbulence detail
        let detail = fbm(vec3<f32>(pTurb * 20.0, t * 0.5 + fi), 3);
        let turbDensity = d * (0.7 + 0.3 * detail);
        
        // Color with temperature
        let shellCol = temperatureColor(clamp(temp, 0.0, 1.0));
        
        // Accumulate with alpha blending
        col = col + shellCol * turbDensity * (1.0 - totalDensity);
        totalDensity = min(totalDensity + turbDensity, 1.0);
    }
    
    // Central star/core
    let coreRadius = 0.03 * explosionEnergy;
    let coreGlow = exp(-r / coreRadius);
    let coreCol = vec3<f32>(1.0, 0.95, 0.8) * coreGlow;
    col = col + coreCol * (1.0 - totalDensity);
    
    // Nebula background
    let nebula = fbm(vec3<f32>(p * 3.0, t * 0.1), 4);
    let nebulaCol = vec3<f32>(0.1, 0.05, 0.2) * nebula * 0.5;
    col = col + nebulaCol;
    
    // Shockwave front (rarefaction)
    let shockRadius = 0.6 + 0.1 * sin(t * 0.2);
    let shockWidth = 0.02;
    let shockDist = abs(r - shockRadius);
    let shock = smoothstep(shockWidth, 0.0, shockDist);
    col = col + vec3<f32>(0.3, 0.5, 0.9) * shock * 0.3;
    
    // Vignette
    let vignette = 1.0 - r * 0.8;
    col *= vignette;
    
    // Gamma correction
    col = pow(col, vec3<f32>(0.9));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(1.0 - r * 0.5, 0.0, 0.0, 0.0));
}
