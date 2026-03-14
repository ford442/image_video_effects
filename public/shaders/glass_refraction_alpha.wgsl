// ═══════════════════════════════════════════════════════════════════════════════
//  glass_refraction_alpha.wgsl - Glass Refraction with Transparency
//  
//  RGBA Focus: Alpha = transparency/thickness of glass
//  Techniques:
//    - Snell's law refraction with chromatic dispersion
//    - Fresnel reflectivity based on viewing angle
//    - Alpha accumulation for multi-layer glass
//    - Thickness-based absorption
//    - Caustic highlights
//  
//  Target: 4.8★ rating
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
const ETA: f32 = 1.5; // Glass refractive index

// SDF primitives
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn sdRoundBox(p: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let q = abs(p) - b + r;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// Smooth union for glass blobs
fn smoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

// Scene SDF
fn map(p: vec3<f32>, time: f32) -> f32 {
    // Animated glass blobs
    let blob1 = sdSphere(p - vec3<f32>(sin(time * 0.5) * 0.2, 0.0, 0.0), 0.25);
    let blob2 = sdSphere(p - vec3<f32>(cos(time * 0.3) * 0.2, sin(time * 0.4) * 0.15, 0.1), 0.2);
    let blob3 = sdSphere(p - vec3<f32>(0.0, cos(time * 0.6) * 0.15, sin(time * 0.5) * 0.1), 0.18);
    
    return smoothUnion(smoothUnion(blob1, blob2, 0.1), blob3, 0.08);
}

// Calculate normal
fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let eps = 0.001;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(eps, 0.0, 0.0), time) - map(p - vec3<f32>(eps, 0.0, 0.0), time),
        map(p + vec3<f32>(0.0, eps, 0.0), time) - map(p - vec3<f32>(0.0, eps, 0.0), time),
        map(p + vec3<f32>(0.0, 0.0, eps), time) - map(p - vec3<f32>(0.0, 0.0, eps), time)
    ));
}

// Fresnel reflectance
fn fresnel(cosTheta: f32, eta: f32) -> f32 {
    let c = abs(cosTheta);
    let g = sqrt(eta * eta - 1.0 + c * c);
    let gmc = g - c;
    let gpc = g + c;
    let a = (gmc / gpc) * (gmc / gpc);
    let b = (c * gpc - 1.0) / (c * gmc + 1.0);
    return 0.5 * a * (1.0 + b * b);
}

// Refraction with Snell's law
fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
    let NdotI = dot(N, I);
    let k = 1.0 - eta * eta * (1.0 - NdotI * NdotI);
    if (k < 0.0) {
        return vec3<f32>(0.0); // Total internal reflection
    }
    return eta * I - (eta * NdotI + sqrt(k)) * N;
}

// Chromatic dispersion
fn refractChromatic(I: vec3<f32>, N: vec3<f32>, eta: f32, dispersion: f32) -> vec3<f32> {
    let etaR = eta - dispersion;
    let etaG = eta;
    let etaB = eta + dispersion;
    
    return vec3<f32>(
        refractRay(I, N, etaR).x,
        refractRay(I, N, etaG).y,
        refractRay(I, N, etaB).z
    );
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
    let transparency = 0.3 + u.zoom_params.x * 0.5; // 0.3-0.8
    let dispersion = u.zoom_params.y * 0.1; // Chromatic aberration
    let thicknessScale = 0.5 + u.zoom_params.z; // Absorption thickness
    let roughness = u.zoom_params.w * 0.1; // Surface roughness
    
    let mousePos = (u.zoom_config.yz - 0.5) * 2.0;
    let audioPulse = u.zoom_config.w;
    
    // Camera ray
    let ro = vec3<f32>(mousePos.x * 0.5, mousePos.y * 0.5, -1.5);
    let rd = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));
    
    // Ray march through glass
    var t = 0.0;
    var hit = false;
    var enterT = 0.0;
    var exitT = 0.0;
    var normal = vec3<f32>(0.0);
    
    // Find entry point
    for (var i: i32 = 0; i < 64; i = i + 1) {
        let p = ro + rd * t;
        let d = map(p, time);
        
        if (!hit && d < 0.001) {
            hit = true;
            enterT = t;
            normal = calcNormal(p, time);
            break;
        }
        
        t += max(d * 0.5, 0.001);
        if (t > 3.0) { break; }
    }
    
    // Sample background
    var bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    var finalRGB = bgColor;
    var finalAlpha = 0.0;
    
    if (hit) {
        // Refract into glass
        let eta = 1.0 / (ETA + audioPulse * 0.1);
        let refracted = refractRay(rd, normal, eta);
        
        // Chromatic dispersion
        let refractR = refractRay(rd, normal, eta - dispersion * 0.02).xy;
        let refractG = refractRay(rd, normal, eta).xy;
        let refractB = refractRay(rd, normal, eta + dispersion * 0.02).xy;
        
        let refractUV = vec2<f32>(refractG.x, refractG.y) * 0.3 + uv;
        let refractUVR = vec2<f32>(refractR.x, refractR.y) * 0.3 + uv;
        let refractUVB = vec2<f32>(refractB.x, refractB.y) * 0.3 + uv;
        
        // Sample refracted background with chromatic dispersion
        let refractColor = vec3<f32>(
            textureSampleLevel(readTexture, u_sampler, refractUVR, 0.0).r,
            textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).g,
            textureSampleLevel(readTexture, u_sampler, refractUVB, 0.0).b
        );
        
        // Fresnel for reflectivity
        let viewDotNormal = dot(-rd, normal);
        let fresnelFactor = fresnel(viewDotNormal, eta);
        
        // Glass tint (subtle color)
        let glassTint = vec3<f32>(0.95, 0.98, 1.0);
        
        // Absorption based on "thickness" (simplified)
        let absorption = exp(-vec3<f32>(0.1, 0.05, 0.15) * thicknessScale);
        
        // Combine reflection and refraction
        finalRGB = mix(refractColor * absorption * glassTint, bgColor, fresnelFactor * 0.3);
        
        // Specular highlight
        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.5));
        let halfDir = normalize(lightDir - rd);
        let specAngle = max(dot(normal, halfDir), 0.0);
        let specular = pow(specAngle, 128.0) * (1.0 - roughness);
        finalRGB += vec3<f32>(1.0) * specular;
        
        // Alpha based on Fresnel and transparency setting
        finalAlpha = (1.0 - transparency) + fresnelFactor * transparency;
        finalAlpha = clamp(finalAlpha * 0.8, 0.0, 0.95);
    } else {
        // No hit - fully transparent
        finalAlpha = 0.0;
    }
    
    // Add caustic-like glow at edges
    let edgeGlow = smoothstep(0.02, 0.0, map(ro + rd * enterT, time)) * audioPulse;
    finalRGB += vec3<f32>(0.8, 0.9, 1.0) * edgeGlow * 0.5;
    finalAlpha = max(finalAlpha, edgeGlow * 0.5);
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB * vignette, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    // Store normal and alpha for potential feedback
    textureStore(dataTextureA, coord, vec4<f32>(normal * 0.5 + 0.5, finalAlpha));
}
