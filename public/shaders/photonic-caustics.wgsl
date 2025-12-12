// Photonic Caustics Accumulator
// Simulates light caustics through refractive surfaces with chromatic dispersion

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // caustic accumulation
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // photon data
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read accumulated caustics
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=LightHeight
  zoom_params: vec4<f32>,  // x=IOR, y=LightSize, z=Dispersion, w=Intensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_BOUNCES: i32 = 4;
const PHOTON_COUNT: i32 = 32;

// Noise functions for surface perturbation
fn hash31(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * noise2D(p * freq + vec2<f32>(time * 0.2, time * 0.15));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

// Compute surface normal from height field
fn getSurfaceNormal(uv: vec2<f32>, texelSize: vec2<f32>, time: f32) -> vec3<f32> {
  // Use depth and noise for heightfield
  let h = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).r;
  let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
  let hU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).r;
  let hD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;
  
  // Add animated noise perturbation
  let noiseScale = 8.0;
  let noiseAmp = 0.1;
  let nL = fbm(uv * noiseScale + vec2<f32>(-texelSize.x * noiseScale, 0.0), time) * noiseAmp;
  let nR = fbm(uv * noiseScale + vec2<f32>(texelSize.x * noiseScale, 0.0), time) * noiseAmp;
  let nU = fbm(uv * noiseScale + vec2<f32>(0.0, -texelSize.y * noiseScale), time) * noiseAmp;
  let nD = fbm(uv * noiseScale + vec2<f32>(0.0, texelSize.y * noiseScale), time) * noiseAmp;
  
  let dx = ((hR + nR) - (hL + nL)) * 2.0;
  let dy = ((hD + nD) - (hU + nU)) * 2.0;
  
  return normalize(vec3<f32>(-dx, -dy, 0.2));
}

// Schlick's Fresnel approximation
fn fresnelSchlick(cosTheta: f32, ior: f32) -> f32 {
  let r0 = (1.0 - ior) / (1.0 + ior);
  let r0sq = r0 * r0;
  return r0sq + (1.0 - r0sq) * pow(1.0 - cosTheta, 5.0);
}

// Snell's law refraction
fn refractRay(incident: vec3<f32>, normal: vec3<f32>, eta: f32) -> vec3<f32> {
  let cosi = -dot(normal, incident);
  let sin2t = eta * eta * (1.0 - cosi * cosi);
  if (sin2t > 1.0) {
    // Total internal reflection
    return reflect(incident, normal);
  }
  let cost = sqrt(1.0 - sin2t);
  return incident * eta + normal * (eta * cosi - cost);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u.config.y;
  
  // Parameters
  let baseIOR = mix(1.1, 1.8, u.zoom_params.x);
  let lightSize = mix(0.05, 0.3, u.zoom_params.y);
  let dispersion = mix(0.0, 0.1, u.zoom_params.z);
  let intensity = mix(0.5, 3.0, u.zoom_params.w);
  
  // Light source position (from mouse or center)
  let lightPos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let lightHeight = mix(0.5, 2.0, u.zoom_config.w);
  
  // Read previous accumulation for temporal blending
  let prevCaustic = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  
  // Trace photons backwards from this pixel to light sources
  var causticAccum = vec3<f32>(0.0);
  let surfaceNormal = getSurfaceNormal(uv, texelSize, time);
  
  // For each photon
  for (var p = 0; p < PHOTON_COUNT; p = p + 1) {
    // Random offset for photon origin within light area
    let seed = vec3<f32>(uv, f32(p) + time * 0.01);
    let randomAngle = hash31(seed) * 2.0 * PI;
    let randomRadius = sqrt(hash31(seed + vec3<f32>(1.0, 0.0, 0.0))) * lightSize;
    let photonOrigin = lightPos + vec2<f32>(cos(randomAngle), sin(randomAngle)) * randomRadius;
    
    // Direction from light to this pixel
    let toPixel = uv - photonOrigin;
    let dist2D = length(toPixel);
    let dir2D = toPixel / max(dist2D, 0.001);
    
    // 3D direction considering light height
    let lightDir = normalize(vec3<f32>(dir2D, -lightHeight));
    
    // Sample surface at photon hit point
    let hitNormal = getSurfaceNormal(uv, texelSize, time);
    
    // Fresnel and refraction for each color channel (chromatic dispersion)
    let cosTheta = abs(dot(lightDir, hitNormal));
    
    // Different IOR for R, G, B channels
    let iorR = baseIOR - dispersion;
    let iorG = baseIOR;
    let iorB = baseIOR + dispersion;
    
    // Refract for each channel
    let refractR = refractRay(lightDir, hitNormal, 1.0 / iorR);
    let refractG = refractRay(lightDir, hitNormal, 1.0 / iorG);
    let refractB = refractRay(lightDir, hitNormal, 1.0 / iorB);
    
    // Compute caustic intensity based on ray convergence
    let convergenceR = abs(dot(refractR, vec3<f32>(0.0, 0.0, -1.0)));
    let convergenceG = abs(dot(refractG, vec3<f32>(0.0, 0.0, -1.0)));
    let convergenceB = abs(dot(refractB, vec3<f32>(0.0, 0.0, -1.0)));
    
    // Fresnel term
    let fresnel = 1.0 - fresnelSchlick(cosTheta, baseIOR);
    
    // Attenuation with distance
    let attenuation = 1.0 / (1.0 + dist2D * 5.0);
    
    // Caustic intensity - brighter where rays converge
    let causticR = pow(convergenceR, 4.0) * fresnel * attenuation;
    let causticG = pow(convergenceG, 4.0) * fresnel * attenuation;
    let causticB = pow(convergenceB, 4.0) * fresnel * attenuation;
    
    causticAccum = causticAccum + vec3<f32>(causticR, causticG, causticB);
  }
  
  // Normalize by photon count
  causticAccum = causticAccum / f32(PHOTON_COUNT);
  causticAccum = causticAccum * intensity;
  
  // Add ripple-based light sources
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let toRipple = uv - ripple.xy;
        let dist = length(toRipple);
        let rippleStrength = (1.0 - rippleAge / 3.0) * 0.5;
        
        // Caustic pattern around ripple
        let angle = atan2(toRipple.y, toRipple.x);
        let wave = sin(dist * 30.0 - rippleAge * 5.0) * 0.5 + 0.5;
        let causticRing = wave * rippleStrength / (1.0 + dist * 10.0);
        
        causticAccum = causticAccum + vec3<f32>(causticRing * 0.5, causticRing * 0.7, causticRing * 1.0);
      }
    }
  }
  
  // Temporal accumulation for smoother caustics
  let blendFactor = 0.15;
  let accumulatedCaustic = mix(prevCaustic.rgb, causticAccum, blendFactor);
  
  // Store accumulated caustics
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(accumulatedCaustic, 1.0));
  
  // Get source image
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Refraction displacement based on surface normal
  let refractDisplace = surfaceNormal.xy * 0.02;
  let refractedColor = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace, 0.0);
  
  // Chromatic aberration for refracted view
  let chromaOffset = dispersion * 0.01;
  let colorR = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace + vec2<f32>(chromaOffset, 0.0), 0.0).r;
  let colorG = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace, 0.0).g;
  let colorB = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace - vec2<f32>(chromaOffset, 0.0), 0.0).b;
  let refractedChromatic = vec3<f32>(colorR, colorG, colorB);
  
  // Blend refracted image with caustics
  var finalColor = mix(sourceColor.rgb, refractedChromatic, 0.3);
  
  // Add caustic highlights
  finalColor = finalColor + accumulatedCaustic;
  
  // Specular highlights
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let reflectDir = reflect(-viewDir, surfaceNormal);
  let lightDir = normalize(vec3<f32>(lightPos - uv, lightHeight));
  let specular = pow(max(dot(reflectDir, lightDir), 0.0), 64.0);
  finalColor = finalColor + vec3<f32>(specular * 0.5);
  
  // Output
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
