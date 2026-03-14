// ═══════════════════════════════════════════════════════════════
//  Bismuth Crystallizer - Physical Light Transmission with Alpha
//  Category: image
//  Features: hopper crystals, iridescence, metallic transmission
//  Simulates bismuth crystals with thin-film interference
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

const IOR_BISMUTH: f32 = 1.8; // Approximate for oxide layer

fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(shift);
    return vec3<f32>(color * cos_angle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cos_angle));
}

// Fresnel for metals (complex IOR approximation)
fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: steps_param (crystal depth/complexity)
    // y: offset_param (hopper offset)
    // z: color_freq (iridescence frequency)
    // w: mix_amt + metallic/purity
    // ═══════════════════════════════════════════════════════════════
    
    let steps_param = u.zoom_params.x * 20.0 + 5.0;
    let offset_param = u.zoom_params.y * 0.8;
    let color_freq = u.zoom_params.z * 10.0 + 2.0;
    let mix_amt = u.zoom_params.w;
    let metallic = 0.8 + u.zoom_params.w * 0.2;
    let oxidePurity = 1.0 - u.zoom_params.x * 0.3; // More steps = more oxide variation

    var mouse = u.zoom_config.yz * vec2<f32>(aspect, 1.0);
    var p = uv * vec2<f32>(aspect, 1.0) - mouse;

    // Rotate slightly over time
    let time = u.config.x * 0.2;
    let s = sin(time);
    let c = cos(time);
    p = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);

    var height = 0.0;
    var size = 1.0;
    var current_offset = vec2<f32>(0.0);

    // Iterative box SDF-like approach for hopper crystals
    for (var i = 0.0; i < steps_param; i = i + 1.0) {
        let d = max(abs(p.x - current_offset.x), abs(p.y - current_offset.y));

        if (d < size) {
            height = i;
            let shrink = 0.1;
            size = size - shrink;

            let mod_i = i % 4.0;
            var dir = vec2<f32>(0.0);
            if (mod_i < 1.0) { dir = vec2<f32>(1.0, 1.0); }
            else if (mod_i < 2.0) { dir = vec2<f32>(-1.0, 1.0); }
            else if (mod_i < 3.0) { dir = vec2<f32>(-1.0, -1.0); }
            else { dir = vec2<f32>(1.0, -1.0); }

            current_offset = current_offset + dir * offset_param * shrink;
        }

        if (size <= 0.0) { break; }
    }

    // ═══════════════════════════════════════════════════════════════
    // Iridescence / Thin-film interference
    // ═══════════════════════════════════════════════════════════════
    
    let phase = height * 0.5 + u.config.x;
    // Bismuth oxide iridescence: magenta, gold, cyan, blue
    let irid = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.0, 4.0) + phase * color_freq);

    // Sample texture
    let img_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Displace UV based on crystal structure
    let refraction_scale = 0.01;
    let uv_refracted = uv + vec2<f32>(sin(height), cos(height)) * refraction_scale;
    let refracted_color = textureSampleLevel(readTexture, u_sampler, uv_refracted, 0.0).rgb;

    // ═══════════════════════════════════════════════════════════════
    // Metallic Reflection & Transmission
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate angle for Fresnel
    let distFromCenter = length(uv - vec2<f32>(0.5));
    let cosTheta = 1.0 - distFromCenter;
    
    // Bismuth metal F0 (approximate)
    let F0_bismuth = vec3<f32>(0.8, 0.85, 0.9); // Slightly bluish metal
    let fresnel = fresnelMetal(max(cosTheta, 0.0), F0_bismuth * metallic);
    
    // Oxide layer thickness varies with height and purity
    let oxideThickness = height * 0.1 * oxidePurity;
    
    // Thin-film interference color shift
    let interferencePhase = oxideThickness * color_freq + time * 0.1;
    let interferenceColor = vec3<f32>(
        0.5 + 0.5 * cos(interferencePhase),
        0.5 + 0.5 * cos(interferencePhase + 2.0),
        0.5 + 0.5 * cos(interferencePhase + 4.0)
    );
    
    // Mix iridescence with refracted image
    let crystal_look = mix(refracted_color, irid * interferenceColor, 0.6);
    
    // Apply metallic reflection
    let reflected = img_color * fresnel * metallic;
    let transmitted = crystal_look * (vec3<f32>(1.0) - fresnel) * oxidePurity;
    
    var final_color = mix(img_color, reflected + transmitted, mix_amt);

    // ═══════════════════════════════════════════════════════════════
    // Transmission Alpha
    // ═══════════════════════════════════════════════════════════════
    
    // Metallic bismuth is mostly reflective, but thin oxide layers transmit
    let transmission = (1.0 - metallic * 0.7) * oxidePurity * (1.0 - distFromCenter * 0.5);
    let alpha = clamp(transmission, 0.4, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));
    
    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
