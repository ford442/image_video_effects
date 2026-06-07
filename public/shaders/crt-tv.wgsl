// ═══════════════════════════════════════════════════════════════
//  CRT TV - Authentic Phosphor Physics Simulation
//  Category: retro-glitch
//  
//  Scientific Features:
//  - Phosphor persistence with per-channel decay (R>G>B)
//  - Aperture grille shadow mask (Trinitron-style)
//  - Halation glow (light scattering in glass)
//  - Barrel distortion with curvature
//  - Authentic scanline phosphor gaps
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, 
  zoom_params: vec4<f32>,  // x=ScanlineIntensity, y=PhosphorGlow, z=Halation, w=BarrelDistortion
  ripples: array<vec4<f32>, 50>,
};

// Barrel distortion for CRT curvature
fn curve_uv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
    var centered = uv * 2.0 - 1.0;
    let dist_sq = dot(centered, centered);
    centered = centered * (1.0 + curvature * dist_sq);
    return centered * 0.5 + 0.5;
}

// Inverse barrel for halation sampling
fn inverse_curve_uv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
    var centered = uv * 2.0 - 1.0;
    let dist_sq = dot(centered, centered);
    centered = centered / (1.0 + curvature * dist_sq * 0.8);
    return centered * 0.5 + 0.5;
}

// Aperture grille shadow mask (Trinitron-style)
// Creates RGB vertical stripes with black gaps
fn aperture_grille(uv: vec2<f32>, resolution: vec2<f32>) -> vec3<f32> {
    let pixel_x = uv.x * resolution.x;
    // Subpixel position within a triad
    let subpixel = fract(pixel_x / 3.0) * 3.0;
    
    var mask = vec3<f32>(0.0);
    // Each RGB phosphor occupies ~0.85 of its slot
    let slot_width = 0.85;
    
    if (subpixel < slot_width) {
        mask.r = 1.0;
    } else if (subpixel < 1.0 + slot_width) {
        mask.g = 1.0;
    } else if (subpixel < 2.0 + slot_width) {
        mask.b = 1.0;
    }
    
    return mask;
}

// Phosphor decay simulation with per-channel persistence
// Red: ~50ms (slowest), Green: ~20ms (medium), Blue: ~10ms (fastest)
fn phosphor_decay(base_color: vec3<f32>, time: f32, flicker: f32) -> vec3<f32> {
    // Decay rates (higher = faster fade)
    let decay_rates = vec3<f32>(2.5, 5.0, 10.0);
    
    // 60Hz refresh flicker + subtle hum bar simulation
    let refresh_flicker = 1.0 - flicker * 0.03 * sin(time * 377.0); // 60Hz * 2pi
    let hum_bar = 1.0 - flicker * 0.02 * sin(time * 6.28 * 0.5); // 0.5Hz hum bar
    
    // Apply per-channel decay characteristics
    var decayed = base_color;
    decayed.r = pow(decayed.r, 1.0 / decay_rates.r) * refresh_flicker * hum_bar;
    decayed.g = pow(decayed.g, 1.0 / decay_rates.g) * refresh_flicker * hum_bar;
    decayed.b = pow(decayed.b, 1.0 / decay_rates.b) * refresh_flicker * hum_bar;
    
    return decayed;
}

// Halation glow - light scattering in CRT glass
// Creates bloom around bright objects
fn halation_glow(uv: vec2<f32>, base_color: vec3<f32>, strength: f32, 
                 curvature: f32, resolution: vec2<f32>) -> vec3<f32> {
    if (strength < 0.01) {
        return vec3<f32>(0.0);
    }
    
    // Sample pattern for bloom (small kernel)
    let inv_res = 1.0 / resolution;
    var glow = vec3<f32>(0.0);
    var total_weight = 0.0;
    
    // 5-tap Gaussian-ish sampling
    let offsets = array<vec2<f32>, 5>(
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 0.0) * inv_res * 2.0,
        vec2<f32>(-1.0, 0.0) * inv_res * 2.0,
        vec2<f32>(0.0, 1.0) * inv_res * 2.0,
        vec2<f32>(0.0, -1.0) * inv_res * 2.0
    );
    let weights = array<f32, 5>(0.4, 0.15, 0.15, 0.15, 0.15);
    
    for (var i = 0; i < 5; i = i + 1) {
        let sample_uv = uv + offsets[i];
        // Apply inverse curve to sample from flat space
        let flat_sample_uv = inverse_curve_uv(sample_uv, curvature);
        
        if (flat_sample_uv.x >= 0.0 && flat_sample_uv.x <= 1.0 &&
            flat_sample_uv.y >= 0.0 && flat_sample_uv.y <= 1.0) {
            let sample = textureSampleLevel(readTexture, u_sampler, flat_sample_uv, 0.0).rgb;
            // Only bright areas contribute to halation
            let brightness = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            let bright_contrib = smoothstep(0.3, 0.8, brightness) * sample;
            glow += bright_contrib * weights[i];
            total_weight += weights[i];
        }
    }
    
    if (total_weight > 0.0) {
        glow /= total_weight;
    }
    
    // Red-tinted halation (characteristic of CRT glass)
    glow = glow * vec3<f32>(1.1, 0.95, 0.9);
    
    return glow * strength * 2.0;
}

// Scanline simulation with phosphor gaps
fn scanlines(uv: vec2<f32>, resolution: vec2<f32>, intensity: f32, time: f32) -> f32 {
    // Scanline frequency based on resolution
    let scan_freq = resolution.y * 0.5;
    let scan_y = uv.y * scan_freq;
    
    // Base scanline pattern (phosphor row gaps)
    let scanline_phase = fract(scan_y) * 6.28318530718; // 2*pi
    let scan_profile = 0.5 + 0.5 * cos(scanline_phase);
    
    // Brightness boost between scanlines (phosphor excitation)
    let phosphor_bright = smoothstep(0.0, 0.3, fract(scan_y)) * 
                          smoothstep(1.0, 0.7, fract(scan_y));
    
    // Scanline thickness varies slightly (CRT vertical jitter)
    let jitter = sin(time * 10.0 + uv.y * 100.0) * 0.02;
    let thickness = 0.85 + jitter;
    
    // Darken scanline gaps, boost phosphor brightness
    let scan_darken = 1.0 - intensity * 0.4 * (1.0 - smoothstep(thickness, 1.0, scan_profile));
    let scan_boost = 1.0 + intensity * 0.15 * phosphor_bright;
    
    return scan_darken * scan_boost;
}

// Chromatic aberration from electron beam misalignment
fn chromatic_aberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(strength, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(strength, 0.0), 0.0).b;
    return vec3<f32>(r, g, b);
}

// Vignette with CRT-specific roll-off
fn crt_vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let centered = uv * 2.0 - 1.0;
    let dist = length(centered);
    
    // Softer vignette for CRT (corner darkening from curved glass)
    let vig = 1.0 - smoothstep(0.6, 1.4, dist * (0.8 + strength * 0.4));
    
    // Additional corner darkening
    let corner = abs(centered.x * centered.y);
    let corner_darken = 1.0 - corner * 0.15 * strength;
    
    return vig * corner_darken;
}

// Noise/grain for analog signal feel
fn film_grain(uv: vec2<f32>, time: f32) -> f32 {
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    return 0.95 + noise * 0.05; // Subtle 5% variation
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters from zoom_params
    let scanline_intensity = u.zoom_params.x;           // 0.0 - 1.0
    let phosphor_glow = u.zoom_params.y;                // 0.0 - 1.0
    let halation_strength = u.zoom_params.z;            // 0.0 - 1.0
    let barrel_amount = u.zoom_params.w;                // 0.0 - 1.0
    
    // Derived parameters
    let curvature = barrel_amount * 0.15;               // Barrel distortion strength
    let flicker_amount = 0.5 + barrel_amount * 0.5;     // More flicker with older CRTs
    let chromatic_str = 0.002 * barrel_amount;          // Aberration scales with age
    
    // Apply barrel distortion
    var crt_uv = uv;
    if (barrel_amount > 0.01) {
        crt_uv = curve_uv(uv, curvature);
    }
    
    // Bounds check - outside CRT screen is black
    if (crt_uv.x < 0.0 || crt_uv.x > 1.0 || crt_uv.y < 0.0 || crt_uv.y > 1.0) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 1: Base Color with Chromatic Aberration
    // ═══════════════════════════════════════════════════════════════
    var color = chromatic_aberration(crt_uv, chromatic_str);
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 2: Aperture Grille (Shadow Mask)
    // ═══════════════════════════════════════════════════════════════
    let mask = aperture_grille(crt_uv, resolution);
    color = color * mask;
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 3: Scanlines with Phosphor Gaps
    // ═══════════════════════════════════════════════════════════════
    let scan_mod = scanlines(crt_uv, resolution, scanline_intensity, time);
    color = color * scan_mod;
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 4: Halation Glow (Glass Scattering)
    // ═══════════════════════════════════════════════════════════════
    let halation = halation_glow(crt_uv, color, halation_strength, curvature, resolution);
    color = color + halation;
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 5: Phosphor Glow and Persistence
    // ═══════════════════════════════════════════════════════════════
    if (phosphor_glow > 0.01) {
        // Simulate phosphor bloom around bright areas
        let brightness = dot(color, vec3<f32>(0.299, 0.587, 0.114));
        let bloom = smoothstep(0.4, 0.9, brightness) * phosphor_glow * 0.4;
        
        // Per-channel phosphor saturation
        color = mix(color, pow(color, vec3<f32>(0.7)), phosphor_glow * 0.3);
        color = color + color * bloom;
    }
    
    // Apply phosphor decay characteristics with flicker
    color = phosphor_decay(color, time, flicker_amount);
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 6: Vignette and Film Grain
    // ═══════════════════════════════════════════════════════════════
    let vignette = crt_vignette(uv, 0.5 + barrel_amount * 0.5);
    color = color * vignette;
    
    // Subtle analog noise
    let grain = film_grain(uv, time);
    color = color * grain;
    
    // ═══════════════════════════════════════════════════════════════
    // STAGE 7: Color Grading (CRT-specific)
    // ═══════════════════════════════════════════════════════════════
    // Slight warm tint typical of CRT phosphors
    let warm_tint = vec3<f32>(1.05, 1.02, 0.98);
    color = color * warm_tint;
    
    // Gamma correction for CRT display characteristic
    let gamma = 1.0 / 2.2;
    color = pow(color, vec3<f32>(gamma));
    
    // Clamp and output
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
