// ═══════════════════════════════════════════════════════════════════════════════
//  fire_smoke_volumetric.wgsl - Volumetric Fire/Smoke with Density Alpha
//  
//  RGBA Focus: Alpha = smoke density, RGB = blackbody temperature
//  Techniques:
//    - Ray-marched volumetric fire
//    - Curl noise for turbulent motion
//    - Blackbody radiation coloring (temperature)
//    - Mouse creates heat source
//    - Audio drives turbulence
//  
//  Target: 4.7★ rating
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

const PI: f32 = 3.14159265359;

// Hash functions
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    return fract((q.x + q.y) * q.z);
}

// Noise
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(
            mix(hash3(i), hash3(i + vec3<f32>(1,0,0)), f.x),
            mix(hash3(i + vec3<f32>(0,1,0)), hash3(i + vec3<f32>(1,1,0)), f.x),
            f.y
        ),
        mix(
            mix(hash3(i + vec3<f32>(0,0,1)), hash3(i + vec3<f32>(1,0,1)), f.x),
            mix(hash3(i + vec3<f32>(0,1,1)), hash3(i + vec3<f32>(1,1,1)), f.x),
            f.y
        ),
        f.z
    );
}

// Curl noise for divergence-free velocity
fn curlNoise3D(p: vec3<f32>, time: f32) -> vec3<f32> {
    let eps = 0.01;
    
    let dx = vec3<f32>(eps, 0.0, 0.0);
    let dy = vec3<f32>(0.0, eps, 0.0);
    let dz = vec3<f32>(0.0, 0.0, eps);
    
    let pTime = vec3<f32>(p.xy, p.z + time * 0.5);
    
    let x1 = noise3(pTime + dy);
    let x2 = noise3(pTime - dy);
    let x3 = noise3(pTime + dz);
    let x4 = noise3(pTime - dz);
    
    let y1 = noise3(pTime + dx);
    let y2 = noise3(pTime - dx);
    let y3 = noise3(pTime + dz);
    let y4 = noise3(pTime - dz);
    
    let z1 = noise3(pTime + dx);
    let z2 = noise3(pTime - dx);
    let z3 = noise3(pTime + dy);
    let z4 = noise3(pTime - dy);
    
    return vec3<f32>(
        (z3 - z4 - y3 + y4) / (2.0 * eps),
        (x3 - x4 - z1 + z2) / (2.0 * eps),
        (y1 - y2 - x1 + x2) / (2.0 * eps)
    );
}

// Temperature to blackbody color
fn blackbodyColor(t: f32) -> vec3<f32> {
    // Approximate blackbody radiation
    let temp = clamp(t, 0.0, 1.0);
    
    // Red to yellow to white
    let r = 1.0;
    let g = smoothstep(0.0, 0.6, temp);
    let b = smoothstep(0.4, 1.0, temp);
    
    return vec3<f32>(r, g, b);
}

// Fire density field
fn fireDensity(p: vec3<f32>, time: f32, mouse: vec3<f32>, audioPulse: f32) -> vec4<f32> {
    let uv = p.xy;
    let height = p.z;
    
    // Turbulence
    let turb = curlNoise3D(p * 2.0, time);
    let warpedP = p + turb * 0.1 * (1.0 + audioPulse);
    
    // Base noise
    let n1 = noise3(warpedP * 2.0 + vec3<f32>(0.0, -time * 0.5, 0.0));
    let n2 = noise3(warpedP * 4.0 + vec3<f32>(0.0, -time * 1.0, 0.0)) * 0.5;
    let n3 = noise3(warpedP * 8.0 + vec3<f32>(0.0, -time * 2.0, 0.0)) * 0.25;
    
    let noiseVal = n1 + n2 + n3;
    
    // Height falloff (fire rises)
    let heightFalloff = exp(-height * 2.0);
    
    // Mouse heat source
    let toMouse = length(uv - mouse.xy);
    let heatSource = smoothstep(0.2, 0.0, toMouse) * (1.0 - height * 0.5);
    
    // Temperature (0 = cool smoke, 1 = hot fire)
    let temp = (noiseVal * 0.5 + 0.5) * heightFalloff * (1.0 + heatSource * 2.0);
    temp = clamp(temp + heatSource, 0.0, 1.0);
    
    // Density (smoke)
    let density = smoothstep(0.3, 0.7, temp) * heightFalloff * (1.0 - temp * 0.5);
    density = density * (1.0 + audioPulse * 0.5);
    
    // Color from temperature
    let color = blackbodyColor(temp);
    
    // Smoke adds gray as it cools
    let smokeColor = vec3<f32>(0.3, 0.3, 0.35);
    let finalColor = mix(smokeColor, color, temp);
    
    return vec4<f32>(finalColor, density);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let fireHeight = 0.5 + u.zoom_params.x; // 0.5-1.5
    let turbulence = u.zoom_params.y; // 0-1
    let smokeAmount = u.zoom_params.z; // 0-1
    let glowIntensity = 0.5 + u.zoom_params.w; // 0.5-1.5
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Ray march setup
    let ro = vec3<f32>(uv, 0.0);
    let rd = vec3<f32>(0.0, 0.0, 1.0);
    
    let steps = 32;
    let stepSize = fireHeight / f32(steps);
    
    var accumColor = vec3<f32>(0.0);
    var transmittance = 1.0;
    var maxTemp = 0.0;
    
    // Ray march through fire volume
    for (var i: i32 = 0; i < steps; i = i + 1) {
        let t = f32(i) * stepSize;
        let p = ro + rd * t;
        
        let sampleRGBA = fireDensity(p, time * (1.0 + audioPulse), 
                                     vec3<f32>(mousePos, 0.0), audioPulse);
        
        // Apply turbulence
        let turb = curlNoise3D(p * 3.0, time);
        sampleRGBA.a *= 1.0 + length(turb) * turbulence * 0.5;
        
        // Smoke amount adjustment
        sampleRGBA.a = mix(sampleRGBA.a * 0.3, sampleRGBA.a, smokeAmount + (1.0 - sampleRGBA.w));
        
        // Beer-Lambert absorption
        let absorption = exp(-sampleRGBA.a * stepSize * 5.0);
        
        // Accumulate
        let emission = sampleRGBA.rgb * sampleRGBA.a * stepSize * glowIntensity;
        accumColor += transmittance * emission;
        transmittance *= absorption;
        
        maxTemp = max(maxTemp, sampleRGBA.w);
        
        if (transmittance < 0.01) { break; }
    }
    
    // Background
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Blend
    let finalRGB = accumColor + bg * transmittance;
    let finalAlpha = 1.0 - transmittance;
    
    // HDR bloom from hot areas
    let bloom = maxTemp * maxTemp * glowIntensity * 0.5;
    finalRGB += vec3<f32>(1.0, 0.7, 0.3) * bloom;
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB * vignette, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}
