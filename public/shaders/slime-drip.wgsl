// ═══════════════════════════════════════════════════════════════
//  Slime Drip - Image Effect with Mucus Material Properties
//  Category: image
//  Features: Viscous slime, light transmission, surface wetness alpha
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Speed, y=Viscosity, z=Amount, w=Tint
  ripples: array<vec4<f32>, 50>,
};

// Mucus/Slime Material Properties
const MUCUS_DENSITY: f32 = 0.8;           // Slime is relatively transparent
const MUCUS_SCATTERING: f32 = 1.2;        // Moderate forward scattering
const THICK_SLIME_ALPHA: f32 = 0.75;      // Thick slime is more opaque
const THIN_SLIME_ALPHA: f32 = 0.35;       // Thin slime is very transparent

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(vec2<f32>(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(0.5, 0.0))), f - vec2<f32>(0.0, 0.0)),
                   dot(vec2<f32>(hash12(i + vec2<f32>(1.0, 0.0)), hash12(i + vec2<f32>(1.5, 0.0))), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(vec2<f32>(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(0.5, 1.0))), f - vec2<f32>(0.0, 1.0)),
                   dot(vec2<f32>(hash12(i + vec2<f32>(1.0, 1.0)), hash12(i + vec2<f32>(1.5, 1.0))), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Calculate slime thickness from drip amount
fn calculateSlimeThickness(dripAmount: f32, viscosity: f32) -> f32 {
    // Viscous slime is thicker
    // dripAmount represents the concentration/density of slime
    let baseThickness = dripAmount * 0.3;
    let viscousFactor = 1.0 + viscosity * 0.5;
    return baseThickness * viscousFactor;
}

// Mucus subsurface scattering (forward scattering dominant)
fn mucusSSS(viewDir: vec3<f32>, lightDir: vec3<f32>, thickness: f32, 
            baseColor: vec3<f32>) -> vec3<f32> {
    // Forward scattering through mucus
    let forwardDot = max(0.0, dot(viewDir, -lightDir));
    let forwardScatter = pow(forwardDot, 4.0) * MUCUS_SCATTERING;
    
    // Mucus has slight green/yellow tint
    let mucusTint = vec3<f32>(0.85, 0.95, 0.75);
    
    // Absorption through thickness
    let absorption = exp(-thickness * MUCUS_DENSITY);
    
    return baseColor * mucusTint * forwardScatter * absorption;
}

// Calculate alpha for slime based on thickness and wetness
fn calculateSlimeAlpha(dripAmount: f32, thickness: f32, viscosity: f32) -> f32 {
    // Thin drips are very transparent, thick globs are more opaque
    let thicknessAlpha = mix(THIN_SLIME_ALPHA, THICK_SLIME_ALPHA, thickness * 3.0);
    
    // Viscosity affects transparency (more viscous = more scattering)
    let viscousAlpha = mix(thicknessAlpha, thicknessAlpha * 1.15, viscosity * 0.3);
    
    // Beer-Lambert absorption for organic material
    let absorption = exp(-thickness * MUCUS_DENSITY * 0.5);
    let finalAlpha = mix(THIN_SLIME_ALPHA, viscousAlpha, absorption);
    
    return clamp(finalAlpha, 0.25, 0.85);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let speed = u.zoom_params.x * 2.0;
    let viscosity = u.zoom_params.y;
    let amount = u.zoom_params.z;
    let tint_str = u.zoom_params.w;

    // Drip Logic
    let noise_scale = mix(5.0, 20.0, viscosity);
    let flow = noise(vec2<f32>(uv.x * noise_scale, time * speed * 0.2));

    // Threshold flow to create "drips"
    let drip = smoothstep(0.4, 0.7, flow);

    // Distortion
    let y_offset = drip * 0.1 * amount;

    var sample_uv = uv + vec2<f32>(0.0, -y_offset);

    // Mouse Wipe
    let mouse_dist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    let wipe = smoothstep(0.2, 0.0, mouse_dist);
    sample_uv = mix(sample_uv, uv, wipe);

    // Sample base image
    var baseColor = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

    // Calculate slime properties
    let slimeThickness = calculateSlimeThickness(drip * amount, viscosity);
    
    // Slime Color (mucus green with organic tint)
    let tint_color = vec4<f32>(0.15, 0.85, 0.25, 1.0);
    let tint_mask = drip * amount * (1.0 - wipe);
    
    // Apply mucus SSS to tint color
    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let slimeSSS = mucusSSS(viewDir, lightDir, slimeThickness, tint_color.rgb);
    let tintedSlime = mix(tint_color.rgb, tint_color.rgb + slimeSSS, 0.5);

    // Mix with base image
    var finalColor = mix(baseColor.rgb, tintedSlime * baseColor.rgb, tint_mask * tint_str);

    // Add specular highlight to slime (wet surface)
    if (tint_mask > 0.1) {
        let specular = 0.3 * tint_mask * (0.5 + 0.5 * sin(uv.y * 100.0 + time * 2.0));
        finalColor += vec3<f32>(specular);
    }

    // Calculate final alpha
    let finalAlpha = calculateSlimeAlpha(drip, slimeThickness, viscosity);
    
    // Blend alpha with base image
    let blendedAlpha = mix(baseColor.a, finalAlpha, tint_mask * 0.8);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, blendedAlpha));
}
