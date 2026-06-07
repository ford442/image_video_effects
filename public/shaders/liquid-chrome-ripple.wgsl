// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Chrome Ripple Shader with Alpha Physics
//  Category: liquid-effects
//  Features: chrome reflection, ripple refraction, metallic liquid
//
//  ALPHA PHYSICS:
//  - Chrome/metallic has higher F0 for Fresnel
//  - Ripples create varying thickness
//  - Metal reflections reduce perceived transparency
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=FlowSpeed, y=DistortStr, z=Metalness, w=RippleFreq
  ripples: array<vec4<f32>, 50>,
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate chrome liquid alpha
fn calculateChromeAlpha(
    rippleMag: f32,
    metalness: f32,
    viewDotNormal: f32
) -> f32 {
  // Chrome/metallic has high F0 (0.6-1.0 range)
  // Base metal F0 ≈ 0.04 for dielectric, up to 1.0 for metals
  let baseF0 = mix(0.04, 0.8, metalness);
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), baseF0);
  
  // Ripples create varying liquid film thickness
  let filmThickness = rippleMag * 2.0 + 0.1;
  
  // For metallic liquids, absorption is different
  // More metal = less transmission
  let metalFactor = 1.0 - metalness * 0.6;
  let absorption = exp(-filmThickness * metalFactor);
  
  // Base alpha
  let baseAlpha = mix(0.5, 0.9, absorption);
  
  // High Fresnel = more reflection = less transmission
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate chrome color with metallic properties
fn calculateChromeColor(
    baseColor: vec3<f32>,
    metalCol: vec3<f32>,
    metalness: f32,
    ripple: f32,
    flowSpeed: f32
) -> vec3<f32> {
  // Chrome effect: high contrast, metallic tint
  let gray = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
  
  // Metallic color with ripple modulation
  let modulatedMetal = metalCol * (0.5 + 0.5 * ripple);
  
  // Mix based on metalness
  let chromeMix = mix(baseColor, modulatedMetal, metalness * (0.5 + 0.5 * ripple));
  
  // Add flow shimmer
  let shimmer = vec3<f32>(0.05, 0.05, 0.05) * ripple * flowSpeed;
  
  return chromeMix + shimmer;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let flowSpeed = u.zoom_params.x * 2.0;    // x: Flow Speed
    let distortStr = u.zoom_params.y * 0.2;   // y: Distortion Strength
    let metalness = u.zoom_params.z;          // z: Metal/Reflection Mix
    let rippleFreq = u.zoom_params.w * 50.0;  // w: Ripple Frequency

    // Calculate normal from luminance gradient
    let e = 1.0 / resolution;
    let lC = textureSampleLevel(readTexture, u_sampler, uv, 0.0).r; // Approximation using R channel as luminance
    let lR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(e.x, 0.0), 0.0).r;
    let lT = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, e.y), 0.0).r;

    let dX = lC - lR;
    let dY = lC - lT;
    var normal = normalize(vec3<f32>(dX, dY, 0.05)); // 0.05 controls height scale

    // Mouse Ripple
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let ripple = sin(dist * rippleFreq - time * 5.0) * exp(-dist * 3.0);

    // Perturb normal with ripple
    normal.x += ripple * distortStr;
    normal.y += ripple * distortStr;
    normal = normalize(normal);

    // Environment Mapping (using the texture itself as the environment)
    // Refract vector
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let refractDir = refract(viewDir, normal, 0.8); // 0.8 index

    let sampleUV = uv + refractDir.xy * distortStr;

    // Chrome effect: modify color curves
    var col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Make it metallic (high contrast, silver tint)
    let gray = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let metalCol = vec3<f32>(
        sin(gray * 10.0 + time * flowSpeed), 
        sin(gray * 10.0 + 2.0 + time * flowSpeed), 
        sin(gray * 10.0 + 4.0 + time * flowSpeed)
    ) * 0.5 + 0.5;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    let rippleMag = abs(ripple) * distortStr;
    let viewDotNormal = dot(viewDir, normal);
    
    // Calculate chrome color
    let chromeColor = calculateChromeColor(col.rgb, metalCol, metalness, ripple, flowSpeed);
    
    // Calculate alpha
    let alpha = calculateChromeAlpha(rippleMag, metalness, viewDotNormal);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(chromeColor, alpha));

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
