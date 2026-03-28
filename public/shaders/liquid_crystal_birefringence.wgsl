// ═══════════════════════════════════════════════════════════════════════════════
//  liquid_crystal_birefringence.wgsl - Liquid Crystal Optical Effects
//  
//  RGBA Focus: Alpha = polarization rotation amount
//  Techniques:
//    - Birefringent double refraction
//    - Polarization rotation through twisted nematic
//    - Color shifting based on cell thickness
//    - Electric field response (mouse-driven)
//    - Schlieren texture visualization
//  
//  Target: 4.7★ rating
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

// Schlieren texture (liquid crystal director field)
fn schlierenTexture(uv: vec2<f32>, time: f32) -> vec2<f32> {
    let scale = 8.0;
    let x = uv.x * scale;
    let y = uv.y * scale;
    
    // Twisted nematic pattern
    let twist = sin(x + time * 0.5) * cos(y + time * 0.3);
    let angle = twist * PI * 0.5;
    
    return vec2<f32>(cos(angle), sin(angle));
}

// Director field with defects
fn directorField(uv: vec2<f32>, time: f32, mouse: vec2<f32>) -> vec2<f32> {
    var dir = vec2<f32>(0.0);
    
    // Base twist
    let baseAngle = uv.x * PI * 2.0 + time * 0.2;
    dir = vec2<f32>(cos(baseAngle), sin(baseAngle));
    
    // Mouse creates defect
    let toMouse = uv - mouse;
    let dist = length(toMouse);
    let defectStrength = smoothstep(0.3, 0.0, dist);
    let defectAngle = atan2(toMouse.y, toMouse.x) * 0.5;
    let defectDir = vec2<f32>(cos(defectAngle), sin(defectAngle));
    
    dir = mix(dir, defectDir, defectStrength);
    
    // Add turbulence
    let turb = schlierenTexture(uv * 2.0, time);
    dir = normalize(dir + turb * 0.3);
    
    return dir;
}

// Birefringent phase retardation
fn phaseRetardation(thickness: f32, birefringence: f32, wavelength: f32) -> f32 {
    return 2.0 * PI * thickness * birefringence / wavelength;
}

// Apply polarization rotation
fn rotatePolarization(color: vec3<f32>, angle: f32, retardation: vec3<f32>) -> vec3<f32> {
    // Simplified Mueller matrix for twisted nematic
    let cosA = cos(angle);
    let sinA = sin(angle);
    
    // Each channel gets different retardation
    var result: vec3<f32>;
    result.r = color.r * cosA * cosA + color.g * sinA * sinA * cos(retardation.r);
    result.g = color.r * sinA * sinA + color.g * cosA * cosA * cos(retardation.g);
    result.b = color.b * cos(retardation.b);
    
    return result;
}

// Color from birefringence
fn birefringenceColor(phase: f32) -> vec3<f32> {
    // Newton's rings color sequence
    let hue = fract(phase / (2.0 * PI));
    return vec3<f32>(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.19) * 0.5 + 0.5
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let cellThickness = 0.5 + u.zoom_params.x; // 0.5-1.5
    let twistAngle = u.zoom_params.y * PI * 2.0; // 0-2π twist
    let birefringence = 0.1 + u.zoom_params.z * 0.2; // 0.1-0.3
    let voltage = u.zoom_params.w; // Electric field effect
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Director field
    let director = directorField(uv, time, mousePos);
    
    // Effective thickness varies with voltage (Frederiks transition)
    let effectiveThickness = cellThickness * (1.0 - voltage * 0.7);
    
    // Phase retardation for RGB (different wavelengths)
    let wavelengthR = 650.0;
    let wavelengthG = 530.0;
    let wavelengthB = 460.0;
    
    let retardation = vec3<f32>(
        phaseRetardation(effectiveThickness, birefringence, wavelengthR * 0.001),
        phaseRetardation(effectiveThickness, birefringence, wavelengthG * 0.001),
        phaseRetardation(effectiveThickness, birefringence, wavelengthB * 0.001)
    );
    
    // Twist angle varies across cell
    let localTwist = twistAngle * uv.x + audioPulse * sin(time * 5.0 + uv.y * 10.0);
    
    // Sample background
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Apply polarization effect
    var color = rotatePolarization(bg, localTwist, retardation);
    
    // Add birefringence interference colors
    let interference = birefringenceColor(retardation.g + time * 0.5);
    color = mix(color, interference, 0.3 * (1.0 - voltage * 0.5));
    
    // Schlieren texture overlay
    let schlieren = length(schlierenTexture(uv, time));
    color += vec3<f32>(0.1, 0.15, 0.2) * schlieren * 0.5;
    
    // Alpha based on polarization rotation amount
    let rotationAmount = abs(sin(localTwist)) * (1.0 + birefringence);
    let finalAlpha = rotationAmount * 0.7 + 0.3;
    
    // Tone mapping
    color = color / (1.0 + color * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    textureStore(writeTexture, coord, vec4<f32>(color * vignette, finalAlpha * vignette));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
