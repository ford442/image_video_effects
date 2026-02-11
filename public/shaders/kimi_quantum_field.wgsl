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

// Kimi Quantum Field - Wave interference patterns with uncertainty visualization

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Wave function
fn psi(x: f32, y: f32, t: f32, k: f32, w: f32, sx: f32, sy: f32) -> f32 {
    let envelope = exp(-(x * x / (2.0 * sx * sx) + y * y / (2.0 * sy * sy)));
    let wave = cos(k * x - w * t);
    return envelope * wave;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Mouse position
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Aspect correct
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    // Mouse in world space
    let mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;
    
    // Parameters
    let waveCount = i32(u.zoom_params.x * 8.0) + 3;
    let coherence = u.zoom_params.y;
    let uncertainty = u.zoom_params.z * 0.5;
    let decayRate = u.zoom_params.w * 2.0 + 0.5;
    
    // Multi-source interference
    var amplitude = 0.0;
    var probability = 0.0;
    
    // Central source at mouse
    for (var i = 0; i < waveCount; i++) {
        let fi = f32(i);
        
        // Wave packet properties
        let k = 10.0 + fi * 5.0;
        let w = 2.0 + fi;
        let phase = fi * 0.7;
        
        // Uncertainty in position (Gaussian spread)
        let spread = 0.1 + uncertainty * (0.5 + 0.5 * sin(time * decayRate + fi));
        
        // Wave source with slight offset for interference
        let offset = vec2<f32>(
            cos(fi * 2.094) * 0.1 * coherence,
            sin(fi * 2.094) * 0.1 * coherence
        );
        let source = mousePos + offset;
        
        // Distance from source
        let diff = p - source;
        let dist = length(diff);
        let angle = atan2(diff.y, diff.x);
        
        // Radial wave with angular modulation
        let radial = sin(k * dist - w * time + phase);
        let angular = cos(angle * 3.0 + fi);
        
        // Wave packet envelope
        let envelope = exp(-dist * dist / (2.0 * spread * spread));
        
        // Add to total amplitude
        let wave = radial * angular * envelope;
        amplitude += wave;
        
        // Probability density (|ψ|²)
        probability += wave * wave;
    }
    
    // Normalize
    amplitude /= f32(waveCount);
    probability /= f32(waveCount);
    
    // Phase visualization
    let phaseColor = 0.5 + 0.5 * sin(amplitude * 10.0 + time);
    
    // Quantum color palette
    let lowEnergy = vec3<f32>(0.1, 0.0, 0.3);   // Deep purple
    let midEnergy = vec3<f32>(0.0, 0.5, 0.8);   // Cyan
    let highEnergy = vec3<f32>(0.9, 0.9, 1.0);  // White
    
    var col = mix(lowEnergy, midEnergy, smoothstep(0.0, 0.5, probability));
    col = mix(col, highEnergy, smoothstep(0.5, 1.0, probability));
    
    // Add phase-based hue shift
    col += vec3<f32>(0.3, 0.0, -0.3) * phaseColor * 0.5;
    
    // Uncertainty visualization (blur at edges)
    let edgeDist = 1.0 - length(p);
    let uncertaintyGlow = smoothstep(0.0, 0.3, edgeDist) * uncertainty;
    col += vec3<f32>(1.0, 0.3, 0.6) * uncertaintyGlow * 0.3;
    
    // Constructive interference nodes
    let nodes = pow(probability, 3.0) * 2.0;
    col += vec3<f32>(0.8, 1.0, 0.9) * nodes;
    
    // Particle measurement (collapse visualization)
    let measureProb = hash(uv + vec2<f32>(time * 0.1));
    let collapsed = select(0.0, 1.0, measureProb < probability * 0.1);
    col += vec3<f32>(1.0, 0.9, 0.7) * collapsed * mouseDown;
    
    // Vignette
    let vignette = 1.0 - length(p) * 0.3;
    col *= vignette;
    
    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.95));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
