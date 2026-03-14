// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Touch Shader with Alpha Physics
//  Category: liquid-effects
//  Features: touch-responsive, viscosity simulation, depth-based refraction
//
//  ALPHA PHYSICS:
//  - Height field maps to liquid thickness
//  - Touch points create thicker liquid (more opaque)
//  - Viscosity affects transparency
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate touch liquid alpha based on height field
fn calculateTouchAlpha(
    height: f32,
    gradientMag: f32,
    viscosity: f32
) -> f32 {
  // Fresnel at surface slopes
  let F0 = 0.02;
  let normal = normalize(vec3<f32>(-gradientMag * 10.0, -gradientMag * 10.0, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let fresnel = schlickFresnel(max(0.0, dot(viewDir, normal)), F0);
  
  // Height = liquid thickness
  // Higher peaks = thicker liquid = more opaque
  // Viscous liquid = more scattering = more opaque
  let thickness = abs(height) * 2.0 + 0.1;
  let viscosityFactor = 1.0 + viscosity * 0.5;
  
  // Beer-Lambert absorption
  let absorption = exp(-thickness * viscosityFactor);
  let baseAlpha = mix(0.35, 0.85, absorption);
  
  // Fresnel reduces transmission at glancing angles
  let alpha = baseAlpha * (1.0 - fresnel * 0.4);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate liquid color with height-based tinting
fn calculateTouchColor(
    baseColor: vec3<f32>,
    height: f32,
    gradientMag: f32,
    tint_strength: f32
) -> vec3<f32> {
  // Height-based absorption
  let absorption = exp(-abs(height) * 1.5);
  let absorbedColor = baseColor * absorption;
  
  // Tint high spots cyan (liquid feel)
  if (tint_strength > 0.0) {
      let tint_col = vec3<f32>(0.0, 0.9, 1.0); // Cyan
      let heightTint = smoothstep(0.0, 0.5, height) * tint_strength * 0.4;
      return mix(absorbedColor, tint_col, heightTint);
  }
  
  return absorbedColor;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let viscosity = u.zoom_params.x;     // 0.0-1.0 (How fast ripples fade)
    let brush_size = u.zoom_params.y;    // 0.0-1.0
    let refraction = u.zoom_params.z;    // 0.0-1.0
    let tint_strength = u.zoom_params.w; // 0.0-1.0

    // Read previous state from dataTextureC (ping-pong input)
    // State: R = Height/Intensity, G = Unused, B = Unused, A = Unused
    let old_state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var height = old_state.r;

    // Decay the height (Viscosity)
    // Higher viscosity = slower decay
    let decay = 0.9 + (viscosity * 0.095);
    height = height * decay;

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    let mouse_down = u.zoom_config.w;

    let d_vec = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec.x * aspect, d_vec.y);
    let dist = length(d_vec_aspect);

    // Brush radius
    let radius = 0.01 + (brush_size * 0.05);

    // If mouse is near, add to height
    if (dist < radius) {
        let add = (1.0 - dist/radius);
        // Add more if mouse down
        let intensity = 0.5 + (mouse_down * 0.5);
        height = min(height + add * intensity * 0.2, 2.0); // Cap height
    }

    // Diffusion (spread to neighbors)
    // Let's sample neighbors from C
    let texel = vec2<f32>(1.0/resolution.x, 1.0/resolution.y);
    let n_u = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let n_d = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let n_l = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
    let n_r = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;

    // Average
    let avg = (n_u + n_d + n_l + n_r) * 0.25;

    // Blend current height towards average (Smooth/Diffuse)
    height = mix(height, avg, 0.5);

    // Write new state to dataTextureA (History)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(height, 0.0, 0.0, 1.0));

    // Render Logic
    // Use gradient of height to distort UVs (Refraction)
    let grad_x = n_r - n_l;
    let grad_y = n_d - n_u;
    let gradientMag = length(vec2<f32>(grad_x, grad_y));

    let distort = vec2<f32>(grad_x, grad_y) * refraction * 2.0;
    let sample_uv = uv - distort;

    var baseColor = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // Calculate color with height-based effects
    let liquidColor = calculateTouchColor(baseColor, height, gradientMag, tint_strength);
    
    // Calculate alpha
    let alpha = calculateTouchAlpha(height, gradientMag, viscosity);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(liquidColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
