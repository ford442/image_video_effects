// ═══════════════════════════════════════════════════════════════════
//  Cellular Automata 3D
//  Category: generative
//  Features: advanced-hybrid, 3d-ca, volume-raymarching, transfer-function
//  Complexity: Very High
//  Chunks From: gen-xeno-botanical-synth-flora.wgsl, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  3D Game of Life rendered with volume raymarching
//  Glowing 3D structures that evolve frame-by-frame
// ═══════════════════════════════════════════════════════════════════

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

const MAX_STEPS: i32 = 96;
const VOLUME_SIZE: f32 = 32.0;

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ 3D CA STATE ═══
fn getCellState(pos: vec3<f32>, time: f32, density: f32) -> f32 {
    // Pseudo-random but deterministic based on position and time
    let seed = floor(pos * VOLUME_SIZE);
    let h = hash3(seed + vec3<f32>(time * 0.1 * audioReactivity));
    
    // Initial density
    if (time < 1.0) {
        return select(0.0, 1.0, h < density);
    }
    
    // 3D CA rule: Birth 4-5, Survival 5-6
    var neighbors = 0.0;
    for (var z: i32 = -1; z <= 1; z++) {
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                if (x == 0 && y == 0 && z == 0) { continue; }
                let npos = seed + vec3<f32>(f32(x), f32(y), f32(z));
                let nhash = hash3(npos + vec3<f32>((time - 1.0) * 0.1));
                neighbors += select(0.0, 1.0, nhash > 0.5);
            }
        }
    }
    
    let current = select(0.0, 1.0, h > 0.5);
    
    // Birth: 4-5 neighbors, Survival: 5-6 neighbors
    if (current > 0.5) {
        return select(0.0, 1.0, neighbors >= 5.0 && neighbors <= 6.0);
    } else {
        return select(0.0, 1.0, neighbors >= 4.0 && neighbors <= 5.0);
    }
}

// ═══ CELL AGE FOR COLORING ═══
fn getCellAge(pos: vec3<f32>, time: f32) -> f32 {
    // Approximate age by stability over time
    let seed = floor(pos * VOLUME_SIZE);
    var stability = 0.0;
    for (var t = 0; t < 5; t++) {
        let h = hash3(seed + vec3<f32>(f32(t) * 0.1));
        stability += h;
    }
    return stability / 5.0;
}

// ═══ TRANSFER FUNCTION ═══
fn transferFunction(age: f32) -> vec3<f32> {
    // Color based on cell age
    if (age < 0.2) {
        return vec3<f32>(1.0, 0.2, 0.1); // Young: red
    } else if (age < 0.4) {
        return vec3<f32>(1.0, 0.6, 0.1); // Young-adult: orange
    } else if (age < 0.6) {
        return vec3<f32>(0.2, 1.0, 0.3); // Adult: green
    } else if (age < 0.8) {
        return vec3<f32>(0.2, 0.6, 1.0); // Mature: blue
    } else {
        return vec3<f32>(0.8, 0.2, 1.0); // Old: purple
    }
}

// ═══ VOLUME RAYMARCHING ═══
fn raymarchCA(ro: vec3<f32>, rd: vec3<f32>, time: f32, density: f32) -> vec4<f32> {
    var t = 0.0;
    var color = vec3<f32>(0.0);
    var transmittance = 1.0;
    var hitDepth = 1.0;
    
    for (var i = 0; i < MAX_STEPS; i++) {
        let pos = ro + rd * t;
        
        // Map to volume space (-1 to 1)
        let volumePos = pos * 0.15;
        
        // Check if in volume bounds
        if (abs(volumePos.x) > 1.0 || abs(volumePos.y) > 1.0 || abs(volumePos.z) > 1.0) {
            t += 0.05;
            continue;
        }
        
        let cell = getCellState(volumePos, time, density);
        
        if (cell > 0.5) {
            let age = getCellAge(volumePos, time);
            let emission = transferFunction(age);
            
            // Volume rendering equation
            let densityVal = 0.15;
            color += transmittance * emission * densityVal;
            transmittance *= 1.0 - densityVal;
            
            if (hitDepth > 0.9) {
                hitDepth = t / 10.0;
            }
            
            if (transmittance < 0.01) { break; }
        }
        
        t += 0.05;
    }
    
    return vec4<f32>(color, 1.0 - transmittance);
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let evolutionSpeed = mix(0.1, 2.0, u.zoom_params.x); // x: Evolution speed
    let initialDensity = mix(0.1, 0.5, u.zoom_params.y); // y: Initial density
    let colorCycling = u.zoom_params.z;                   // z: Color cycling
    let cameraRotation = u.zoom_params.w * 6.28;         // w: Camera rotation
    
    // Camera setup
    let camDist = 4.0;
    let camAngle = time * 0.1 * audioReactivity * evolutionSpeed + cameraRotation;
    let ro = vec3<f32>(cos(camAngle) * camDist, sin(camAngle * 0.5) * 2.0, sin(camAngle) * camDist);
    
    // Ray direction
    let forward = normalize(-ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    let rd = normalize(forward + right * uv.x * aspect * 0.5 + up * uv.y * 0.5);
    
    // Raymarch through CA volume
    let caTime = time * evolutionSpeed * audioReactivity;
    let caResult = raymarchCA(ro, rd, caTime, initialDensity);
    let caColor = caResult.rgb;
    let caAlpha = caResult.a;
    
    // Background
    let bgUV = vec2<f32>(global_id.xy) / resolution;
    let bgColor = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb;
    
    // Color cycling
    let cycleShift = time * colorCycling * audioReactivity;
    let cycledColor = vec3<f32>(
        caColor.x * (0.5 + 0.5 * cos(cycleShift)),
        caColor.y * (0.5 + 0.5 * cos(cycleShift + 2.09)),
        caColor.z * (0.5 + 0.5 * cos(cycleShift + 4.18))
    );
    
    var color = mix(bgColor * 0.3, cycledColor, caAlpha);
    
    // Add glow around CA structure
    let glow = caAlpha * 0.3;
    color += vec3<f32>(glow * 0.5, glow * 0.7, glow);
    
    let depth = caResult.w;
    let alpha = mix(0.7, 1.0, caAlpha);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
