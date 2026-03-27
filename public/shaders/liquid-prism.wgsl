// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Prism Shader with Alpha Physics
//  Category: liquid-effects
//  Features: chromatic aberration, ripple refraction, transparent crystal
//
//  ALPHA PHYSICS:
//  - Prism/crystal transparency with refraction
//  - Fresnel at glass-air boundaries
//  - Dispersion affects perceived opacity
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
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Strength, y=Frequency, z=Speed, w=Transparency
  ripples: array<vec4<f32>, 50>,
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate prism alpha - glass-like transparency
fn calculatePrismAlpha(
    distortionMag: f32,
    viewDotNormal: f32,
    baseTransparency: f32
) -> f32 {
  // Glass F0 ≈ 0.04 (similar to water but slightly higher)
  let F0 = 0.04;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // More distortion = thicker glass = less transparent
  let thicknessFactor = smoothstep(0.0, 0.1, distortionMag);
  
  // Base transparency from parameter
  let baseAlpha = mix(0.3, 0.85, baseTransparency);
  
  // Fresnel adds reflection at edges, reducing transmission
  // Thicker areas = more opaque
  let alpha = baseAlpha * (1.0 - thicknessFactor * 0.3) * (1.0 - fresnel * 0.25);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate prism color with dispersion
fn calculatePrismColor(
    r: f32,
    g: f32,
    b: f32,
    distortionMag: f32,
    highlight: f32
) -> vec3<f32> {
  // Dispersion creates rainbow effect
  let dispersion = vec3<f32>(
      r * (1.0 + distortionMag * 0.2),
      g,
      b * (1.0 - distortionMag * 0.1)
  );
  
  // Add prism highlight (caustic-like)
  let caustic = vec3<f32>(0.15, 0.18, 0.2) * highlight;
  
  return dispersion + caustic;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Parameters
    let strength = u.zoom_params.x * 0.1; // Distortion Strength
    let frequency = u.zoom_params.y * 20.0 + 5.0; // Ripple Frequency
    let speed = u.zoom_params.z * 5.0; // Ripple Speed
    let aberration = u.zoom_params.w * 0.05; // RGB Split Amount
    let baseTransparency = u.zoom_params.w; // Also controls base transparency

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;
    let diff = uv - mousePos;
    let distVec = diff * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate Ripple
    // Radial sine wave emanating from mouse
    let wavePhase = dist * frequency - time * speed;
    let wave = sin(wavePhase);

    // Decay wave with distance
    let decay = 1.0 / (1.0 + dist * 5.0);

    // Distortion vector
    // We displace along the vector from mouse (or gradient of wave)
    var dir = normalize(diff + vec2<f32>(0.0001, 0.0001)); // Avoid div by zero
    let displace = dir * wave * strength * decay;

    // Aberration: Sample RGB at different offsets
    let rUV = uv + displace * (1.0 + aberration);
    let gUV = uv + displace;
    let bUV = uv + displace * (1.0 - aberration);

    // Edge handling (clamp to 0-1 implicitly by sampler, or explicitly?)
    // Sampler usually repeats or clamps. Let's trust sampler.

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Add some "Prism" brightness boost at the wave peaks
    let highlight = smoothstep(0.8, 1.0, wave) * decay * strength * 10.0;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // Distortion magnitude for thickness estimation
    let distortionMag = length(displace);
    
    // Approximate normal from displacement
    let normal = normalize(vec3<f32>(
        -displace.x * 50.0,
        -displace.y * 50.0,
        1.0
    ));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let viewDotNormal = dot(viewDir, normal);
    
    // Calculate prism color
    let prismColor = calculatePrismColor(r, g, b, distortionMag, highlight);
    
    // Calculate alpha
    let alpha = calculatePrismAlpha(distortionMag, viewDotNormal, baseTransparency);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(prismColor, alpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
