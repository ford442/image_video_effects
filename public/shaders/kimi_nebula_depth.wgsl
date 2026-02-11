@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Kimi Nebula Depth - Volumetric nebula with 3D noise and depth cues

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    return mix(mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), u.x),
                   mix(hash3(vec3<f32>(n + 57.0)), hash3(vec3<f32>(n + 58.0)), u.x), u.y),
               mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), u.x),
                   mix(hash3(vec3<f32>(n + 170.0)), hash3(vec3<f32>(n + 171.0)), u.x), u.y), u.z);
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        value += amp * noise3(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return value;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.05;
    
    // Mouse interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Ray march setup
    var ro = vec3<f32>(uv * 2.0 - 1.0, -1.0);
    ro.x *= resolution.x / resolution.y;
    
    // Mouse affects ray origin
    let mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= resolution.x / resolution.y;
    ro.xy += mousePos * 0.3;
    
    let rd = normalize(vec3<f32>(0.0, 0.0, 1.0));
    
    // Volumetric accumulation
    var col = vec3<f32>(0.0);
    var transmittance = 1.0;
    
    let steps = 32;
    for (var i = 0; i < steps; i++) {
        let t = 0.1 + f32(i) * 0.05;
        let pos = ro + rd * t;
        
        // Animated nebula density
        var noisePos = pos + vec3<f32>(0.0, 0.0, time);
        
        // Turbulence layers
        let d1 = fbm3(noisePos * 1.5, 4);
        let d2 = fbm3(noisePos * 3.0 + vec3<f32>(100.0), 3);
        let d3 = fbm3(noisePos * 6.0 + vec3<f32>(200.0), 2);
        
        let density = max(0.0, d1 * 0.6 + d2 * 0.3 + d3 * 0.1 - 0.3);
        
        // Color based on depth and density
        let depthColor = mix(
            vec3<f32>(0.1, 0.05, 0.2),  // Deep purple
            vec3<f32>(0.8, 0.3, 0.6),   // Pink
            d1
        );
        
        let highlight = vec3<f32>(0.4, 0.8, 1.0) * d2;  // Cyan highlights
        let warm = vec3<f32>(1.0, 0.6, 0.2) * d3;       // Orange accents
        
        let localCol = depthColor + highlight * 0.5 + warm * 0.3;
        
        // Accumulate with Beer-Lambert law
        let stepSize = 0.05;
        let absorption = density * 2.0;
        let tr = exp(-absorption * stepSize);
        
        col += localCol * density * transmittance * stepSize;
        transmittance *= tr;
        
        if (transmittance < 0.01) { break; }
    }
    
    // Add stars in background
    let starNoise = hash3(vec3<f32>(floor(uv * 200.0), 0.0));
    let star = select(0.0, 1.0, starNoise > 0.998);
    col += vec3<f32>(star);
    
    // Mouse creates stellar wind glow
    let dist = length(uv - mouse);
    let windGlow = smoothstep(0.3, 0.0, dist) * mouseDown * 0.5;
    col += vec3<f32>(0.6, 0.9, 1.0) * windGlow;
    
    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.9)) * 1.2;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
