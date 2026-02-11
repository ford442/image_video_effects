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

// Kimi Fractal Dreams - Multi-layer fractal with orbit traps

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Complex number operations
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = b.x * b.x + b.y * b.y;
    return vec2<f32>((a.x * b.x + a.y * b.y) / denom, (a.y * b.x - a.x * b.y) / denom);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.1;
    
    // Mouse interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Aspect correct coordinates
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    // Mouse controls Julia set constant
    let mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;
    let c = mix(vec2<f32>(-0.8, 0.156), mousePos, 0.5);
    
    // Parameters
    let zoom = u.zoom_params.x * 3.0 + 0.5;
    let iterations = i32(u.zoom_params.y * 100.0) + 50;
    let colorCycles = u.zoom_params.z * 5.0 + 1.0;
    let complexity = u.zoom_params.w * 2.0 + 0.5;
    
    // Zoom towards mouse
    p = (p - mousePos) / zoom + mousePos;
    
    // Multiple fractal layers
    var col = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    let layers = 3;
    for (var layer = 0; layer < layers; layer++) {
        let fi = f32(layer);
        let layerC = c + vec2<f32>(cos(time + fi), sin(time + fi)) * 0.1;
        var z = p;
        
        var orbitTrap = 1000.0;
        var minRadius = 1000.0;
        
        let layerIter = iterations + layer * 20;
        
        for (var i = 0; i < layerIter; i++) {
            // Burning Ship variant with Julia
            z = vec2<f32>(abs(z.x), abs(z.y));
            z = cmul(z, z) + layerC;
            
            // Additional complexity
            if (complexity > 1.5) {
                z = z + cdiv(vec2<f32>(0.1, 0.0), z + vec2<f32>(0.01));
            }
            
            // Orbit traps
            let r = length(z);
            orbitTrap = min(orbitTrap, abs(r - 0.5));
            minRadius = min(minRadius, r);
            
            if (r > 4.0) {
                // Smooth coloring
                let smoothIter = f32(i) - log2(log2(r)) + 4.0;
                
                // Color based on escape time and orbit trap
                let hue = fract(smoothIter * 0.01 * colorCycles + fi * 0.33);
                let sat = 0.8;
                let light = 0.5 + orbitTrap * 2.0;
                
                // HSL to RGB
                let c1 = (1.0 - abs(2.0 * light - 1.0)) * sat;
                let x = c1 * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
                let m = light - c1 * 0.5;
                
                var layerCol: vec3<f32>;
                if (hue < 1.0 / 6.0) { layerCol = vec3<f32>(c1, x, 0.0); }
                else if (hue < 2.0 / 6.0) { layerCol = vec3<f32>(x, c1, 0.0); }
                else if (hue < 3.0 / 6.0) { layerCol = vec3<f32>(0.0, c1, x); }
                else if (hue < 4.0 / 6.0) { layerCol = vec3<f32>(0.0, x, c1); }
                else if (hue < 5.0 / 6.0) { layerCol = vec3<f32>(x, 0.0, c1); }
                else { layerCol = vec3<f32>(c1, 0.0, x); }
                layerCol += vec3<f32>(m);
                
                // Glow from orbit trap
                layerCol += vec3<f32>(1.0, 0.8, 0.6) * orbitTrap * 2.0;
                
                let weight = 1.0 / (1.0 + fi);
                col += layerCol * weight;
                totalWeight += weight;
                break;
            }
        }
        
        // Rotation for next layer
        let rot = vec2<f32>(
            p.x * cos(1.047) - p.y * sin(1.047),
            p.x * sin(1.047) + p.y * cos(1.047)
        );
        p = rot * 0.8;
    }
    
    if (totalWeight > 0.0) {
        col /= totalWeight;
    } else {
        col = vec3<f32>(0.02, 0.0, 0.05);
    }
    
    // Mouse glow
    let dist = length(uv - mouse);
    col += vec3<f32>(1.0, 0.9, 0.7) * smoothstep(0.3, 0.0, dist) * mouseDown * 0.5;
    
    // Post-processing
    col = pow(col, vec3<f32>(0.9));
    col *= 1.2;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
