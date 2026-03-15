// ═══════════════════════════════════════════════════════════════
//  Ink Marbling - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: marble thickness → alpha, fluid dynamics opacity
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Hash for noise
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv_orig = vec2<f32>(global_id.xy) / resolution;
    var uv = uv_orig;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;

    // Parameters
    let warp_strength = u.zoom_params.x * 2.0;
    let layers = 4;
    let turbulence = u.zoom_params.y;
    let ink_viscosity = u.zoom_params.z; // Controls thickness/opacity
    let pattern_density = u.zoom_params.w;

    // Mouse Interaction
    let aspect = resolution.x / resolution.y;
    let mouse_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(mouse_vec);

    // Swirl near mouse
    let swirl = (1.0 - smoothstep(0.0, 0.5, dist)) * 5.0 * sin(time * 0.5);
    if (dist < 0.5) {
        uv = mouse + (uv - mouse) * rot(swirl);
    }

    // Domain Warping (FBM style)
    var p = uv * 3.0;
    var amp = 1.0;
    var warp_accum = 0.0; // Track cumulative warp for thickness

    for (var i = 0; i < layers; i++) {
        let warp_val = vec2<f32>(
            sin(p.y * 2.0 + time * 0.2) * 1.0,
            cos(p.x * 2.0 - time * 0.3) * 1.0
        ) * warp_strength * amp;
        
        p = p + warp_val;
        warp_accum += length(warp_val);

        p = p * rot(1.0);
        p = p * (1.5 + turbulence);
        amp = amp * 0.5;
    }

    let distortion = (p * 0.1) - (uv_orig * 3.0 * 0.1);
    let final_uv = uv_orig + distortion * 0.2;
    let repeat_uv = fract(final_uv);

    // Sample the underlying image
    let color = textureSampleLevel(readTexture, u_sampler, repeat_uv, 0.0);
    
    // INK MARBLING ALPHA CALCULATION
    // Based on fluid dynamics and ink accumulation
    
    // Calculate ink thickness from warp accumulation
    // More warping = more ink mixed = thicker layer
    let ink_thickness = smoothstep(0.0, 2.0, warp_accum * (0.5 + ink_viscosity));
    
    // Pattern density affects local concentration
    let pattern_variation = hash12(uv_orig * 50.0 + time * 0.1);
    let local_density = mix(0.5, 1.0, pattern_density) * (0.7 + 0.3 * pattern_variation);
    
    // FLUID THICKNESS → ALPHA MAPPING
    // - Areas of high turbulence/convergence = ink accumulation = opaque
    // - Thin spread areas = transparent
    // - Water bath base = completely transparent (showing only substrate)
    
    // Base alpha from ink thickness
    var ink_alpha = ink_thickness * (0.3 + ink_viscosity * 0.6);
    
    // Ink concentration varies with local density
    ink_alpha *= local_density;
    
    // Marbling effect: bands of varying thickness
    let band_pattern = sin(warp_accum * 5.0 + time) * 0.5 + 0.5;
    let band_thickness = mix(0.4, 1.0, band_pattern);
    ink_alpha *= band_thickness;
    
    // Edge feathering for fluid look
    let edge_feather = smoothstep(0.0, 0.2, ink_thickness);
    ink_alpha *= edge_feather;
    
    // Clamp alpha
    ink_alpha = clamp(ink_alpha, 0.0, 0.95);
    
    // COLOR MODIFICATION based on ink properties
    // Thicker ink = deeper, richer color
    // Thinner ink = lighter, more transparent
    var final_rgb = color.rgb;
    
    // Darken thicker areas (more pigment)
    let pigment_darkening = mix(1.0, 0.7, ink_thickness * ink_viscosity);
    final_rgb *= pigment_darkening;
    
    // Add slight color shift based on thickness (optical properties)
    let color_shift = vec3<f32>(
        1.0,
        0.95 + 0.05 * ink_thickness,
        0.9 + 0.1 * ink_thickness
    );
    final_rgb *= color_shift;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_rgb, ink_alpha));
    
    // Store thickness in depth for potential multi-pass effects
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(ink_thickness, 0.0, 0.0, ink_alpha));
}
