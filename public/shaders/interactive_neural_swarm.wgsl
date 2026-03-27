// ═══════════════════════════════════════════════════════════════════════════════
//  interactive_neural_swarm.wgsl - Neural Network Swarm Visualization
//  
//  Agent: Interactivist + Visualist + Algorithmist
//  Techniques:
//    - Agent-based neural swarm (particles = neurons)
//    - Connection weights based on proximity
//    - Signal propagation through network
//    - Mouse = stimulus source, Audio = activation energy
//  
//  Target: 4.8★ rating
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
const NUM_NEURONS: i32 = 40;
const CONNECTION_RADIUS: f32 = 0.15;

// Hash function
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Smooth falloff
fn smoothFalloff(d: f32, radius: f32) -> f32 {
    let x = d / radius;
    return pow(max(1.0 - x * x, 0.0), 2.0);
}

// Generate neuron positions
fn getNeuronPos(i: i32, time: f32, mousePos: vec2<f32>) -> vec2<f32> {
    let fi = f32(i);
    let hash1 = hash2(vec2<f32>(fi * 1.618, fi * 2.718));
    let hash2 = hash2(vec2<f32>(fi * 3.142, fi * 1.414));
    
    // Base position with organic movement
    let baseX = hash1 * 0.8 + 0.1;
    let baseY = hash2 * 0.8 + 0.1;
    
    // Slow organic drift
    let drift = vec2<f32>(
        sin(time * 0.3 + fi * 0.5) * 0.05,
        cos(time * 0.4 + fi * 0.3) * 0.05
    );
    
    // Mouse attraction (neurons cluster near mouse)
    let toMouse = mousePos - vec2<f32>(baseX, baseY);
    let attraction = toMouse * 0.2 * smoothstep(0.5, 0.0, length(toMouse));
    
    return vec2<f32>(baseX, baseY) + drift + attraction;
}

// Calculate connection strength
fn connectionStrength(p1: vec2<f32>, p2: vec2<f32>, time: f32) -> f32 {
    let dist = length(p1 - p2);
    if (dist > CONNECTION_RADIUS || dist < 0.001) {
        return 0.0;
    }
    
    // Dynamic weight
    let baseStrength = 1.0 - dist / CONNECTION_RADIUS;
    let modulation = sin(time * 2.0 + dist * 20.0) * 0.3 + 0.7;
    
    return baseStrength * modulation;
}

// Signal propagation visualization
fn signalWave(uv: vec2<f32>, source: vec2<f32>, time: f32, speed: f32) -> f32 {
    let dist = length(uv - source);
    let wave = sin(dist * 30.0 - time * speed * 5.0);
    let envelope = smoothstep(0.4, 0.0, dist) * smoothstep(0.0, 0.05, dist);
    return wave * envelope;
}

// Glow effect
fn glow(uv: vec2<f32>, center: vec2<f32>, intensity: f32, radius: f32) -> f32 {
    let dist = length(uv - center);
    return intensity / (1.0 + dist * dist * 100.0 / (radius * radius));
}

// Neon color based on activation
fn activationColor(activation: f32, baseHue: f32) -> vec3<f32> {
    let hue = baseHue + activation * 0.2;
    let sat = 0.8 + activation * 0.2;
    let val = 0.5 + activation * 0.5;
    
    // HSV to RGB
    let c = val * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = val - c;
    
    var rgb: vec3<f32>;
    if (hue < 1.0 / 6.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (hue < 2.0 / 6.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (hue < 3.0 / 6.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (hue < 4.0 / 6.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (hue < 5.0 / 6.0) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }
    
    return rgb + m;
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
    let connectionThreshold = u.zoom_params.x;        // 0-1
    let signalSpeed = 0.5 + u.zoom_params.y * 2.0;    // 0.5-2.5
    let glowRadius = 0.02 + u.zoom_params.z * 0.03;   // 0.02-0.05
    let networkDensity = u.zoom_params.w;             // 0-1
    
    // Inputs
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Background
    var color = vec3<f32>(0.02, 0.02, 0.04);
    
    // Mouse signal wave
    let mouseSignal = signalWave(uv, mousePos, time, signalSpeed);
    color += vec3<f32>(0.3, 0.6, 1.0) * abs(mouseSignal) * (0.5 + audioPulse);
    
    // Process neurons
    for (var i: i32 = 0; i < NUM_NEURONS; i = i + 1) {
        let pos = getNeuronPos(i, time, mousePos);
        let neuronGlow = glow(uv, pos, 1.0, glowRadius);
        
        // Neuron activation from mouse proximity and audio
        let toMouse = length(pos - mousePos);
        let baseActivation = smoothstep(0.3, 0.0, toMouse);
        let activation = baseActivation + audioPulse * hash2(vec2<f32>(f32(i), time));
        
        // Add neuron glow
        let neuronColor = activationColor(activation, f32(i) / f32(NUM_NEURONS));
        color += neuronColor * neuronGlow * (0.5 + activation);
        
        // Draw connections to nearby neurons
        for (var j: i32 = i + 1; j < NUM_NEURONS; j = j + 1) {
            let pos2 = getNeuronPos(j, time, mousePos);
            let strength = connectionStrength(pos, pos2, time);
            
            if (strength > connectionThreshold * 0.5) {
                // Distance to line segment
                let pa = uv - pos;
                let ba = pos2 - pos;
                let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
                let dist = length(pa - ba * h);
                
                // Connection glow
                let connectionGlow = smoothstep(0.005, 0.0, dist) * strength;
                
                // Signal traveling along connection
                let alongLine = h;
                let signal = sin(alongLine * 10.0 - time * signalSpeed * 3.0 + f32(i));
                let signalGlow = smoothstep(0.1, 0.0, abs(signal - alongLine)) * strength;
                
                let connectionColor = mix(
                    vec3<f32>(0.3, 0.5, 0.8),
                    vec3<f32>(0.8, 0.3, 0.6),
                    activation
                );
                
                color += connectionColor * connectionGlow * 0.3;
                color += vec3<f32>(1.0, 0.9, 0.7) * signalGlow * 0.5 * (0.5 + audioPulse);
            }
        }
    }
    
    // Global network pulse
    let networkPulse = sin(time * 0.5) * 0.5 + 0.5;
    color *= 1.0 + networkPulse * networkDensity * 0.3;
    
    // Tone mapping
    color = color / (1.0 + color);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    
    // Store for feedback
    textureStore(dataTextureA, coord, vec4<f32>(color, 1.0));
}
