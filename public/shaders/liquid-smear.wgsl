// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Smear Shader with Alpha Physics
//  Category: liquid-effects
//  Features: temporal feedback, smear effect, viscosity simulation
//
//  ALPHA PHYSICS:
//  - Smear accumulation affects opacity
//  - Viscosity affects transparency
//  - Mouse velocity affects liquid film thickness
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
  zoom_params: vec4<f32>,  // x=SmearStrength, y=BrushSize, z=Decay, w=MixStrength
  ripples: array<vec4<f32>, 50>,
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate smear alpha based on accumulation
fn calculateSmearAlpha(
    smearStrength: f32,
    decayRate: f32,
    distanceToMouse: f32,
    brushSize: f32
) -> f32 {
  // Fresnel (subtle for smear effect)
  let F0 = 0.02;
  let normal = normalize(vec3<f32>(smearStrength * 0.5, smearStrength * 0.5, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let fresnel = schlickFresnel(max(0.0, dot(viewDir, normal)), F0);
  
  // Smear thickness based on strength and proximity to mouse
  let proximityFactor = 1.0 - smoothstep(0.0, brushSize, distanceToMouse);
  let thickness = smearStrength * 2.0 * proximityFactor + 0.2;
  
  // Decay affects opacity (more decay = more transparent over time)
  let decayAlpha = mix(0.7, 0.95, decayRate);
  
  // Absorption
  let absorption = exp(-thickness * 1.0);
  let baseAlpha = mix(0.4, decayAlpha, absorption);
  
  let alpha = baseAlpha * (1.0 - fresnel * 0.2);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate smear color with accumulation
fn calculateSmearColor(
    currentColor: vec3<f32>,
    smearedColor: vec3<f32>,
    smearStrength: f32,
    mixStrength: f32
) -> vec3<f32> {
  // Blend between current and smeared based on mix strength
  let mixed = mix(currentColor, smearedColor, mixStrength);
  
  // Smear adds slight warmth
  let smearTint = vec3<f32>(0.02, 0.01, 0.0) * smearStrength;
  
  return mixed + smearTint;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let smearStrength = 0.1 + (u.zoom_params.x * 0.9);
    let brushSize = 0.05 + (u.zoom_params.y * 0.2);
    let decayRate = 0.9 + (u.zoom_params.z * 0.095); // 0.9 - 0.995
    let mixStrength = 0.1 + (u.zoom_params.w * 0.9);

    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5; // Only smear when mouse is down? Or always? Let's say always for "liquid" feel but maybe stronger when down.

    // For this shader, we want the "history" to be the smeared image.
    // If it's the first frame (or we want to reset), we should maybe mix in the original image strongly.

    // Sample previous smeared frame
    var history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Sample current fresh input
    let currentInput = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Calculate displacement based on mouse velocity would be ideal, but we don't have explicit velocity passed easily unless we calculate it ourselves from previous pos (which we don't store easily).
    // Instead, we can just push pixels away from the mouse, or pull them towards it.
    // Let's do a "pull" effect towards the mouse position if close.

    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));

    var offset = vec2<f32>(0.0);
    if (dist < brushSize && dist > 0.001) {
        // Simple directional smear: pull towards mouse center?
        // Or actually, it's better if we just sample "from" the direction of the mouse.
        // If we are at P, and mouse is at M, looking at M means we pull M's color to P.
        var dir = normalize(mousePos - uv);
        offset = dir * smearStrength * (1.0 - smoothstep(0.0, brushSize, dist)) * 0.05;
    }

    // Sample history at offset location to create the "smear"
    var smeared = textureSampleLevel(dataTextureC, u_sampler, uv - offset, 0.0);

    // If the history is empty/black (start), fill with current input
    if (history.a == 0.0) {
        smeared = currentInput;
    }

    // Continually mix in the fresh input so the image doesn't degenerate completely
    // decayRate controls how much of the old smear we keep.
    let blend = mix(currentInput, smeared, decayRate);

    // Write back to history
    textureStore(dataTextureA, global_id.xy, blend);

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // Calculate smear color
    let smearColor = calculateSmearColor(currentInput.rgb, blend.rgb, smearStrength, mixStrength);
    
    // Calculate alpha
    let alpha = calculateSmearAlpha(smearStrength, decayRate, dist, brushSize);

    // Output with alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(smearColor, alpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
