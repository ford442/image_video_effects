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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Hash functions for procedural generation
fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Neon palette
fn neonColor(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

fn neonColor2(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.1, 0.2);
    return a + b * cos(TAU * (c * t + d));
}

// Smooth minimum for soft blob blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Node structure - we place nodes procedurally
fn getNodePos(layer: i32, idx: i32, totalLayers: i32, time: f32) -> vec2<f32> {
    let fi = f32(idx);
    let fl = f32(layer);
    let nodesInLayer = 4 + layer * 2;
    let fx = hash1(fl * 37.0 + fi * 13.0 + 0.5);
    let fy = hash1(fl * 71.0 + fi * 29.0 + 1.3);
    
    let x = -0.75 + fl / f32(totalLayers - 1) * 1.5;
    let y = (fi / f32(nodesInLayer - 1) - 0.5) * 1.2;
    
    // Breathing animation
    let breathe = sin(time * 2.0 + fl * 1.5 + fi * 0.7) * 0.03;
    let drift = sin(time * 0.5 + fl + fi * 2.0) * 0.02;
    
    return vec2<f32>(x + drift + breathe, y + sin(time + fi) * 0.015);
}

// SDF for a line segment with glow
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Signal pulse along an edge
fn signalPulse(edgeLen: f32, edgeIdx: f32, time: f32, speed: f32) -> f32 {
    let pulsePos = fract(time * speed * 0.3 + edgeIdx * 0.17);
    let pulseWidth = 0.08;
    let d = abs(pulsePos * edgeLen - 0.5 * edgeLen);
    return exp(-d * d / (pulseWidth * pulseWidth));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    
    let time = u.config.x;
    let mousePos = (u.zoom_config.yz - res * 0.5) / min(res.x, res.y);
    let mouseDown = u.zoom_config.w > 0.5;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    
    let baseScale = 0.5 + scale * 1.5;
    let p = uv * baseScale;
    
    var col = vec3<f32>(0.02, 0.01, 0.03);
    
    // Mouse cursor node
    var cursorPos = mousePos * baseScale;
    let cursorPulse = sin(time * 4.0) * 0.5 + 0.5;
    let cursorRadius = 0.04 * (0.8 + cursorPulse * 0.3);
    
    // Background grid glow
    let gridDist = min(
        abs(fract(p.x * 6.0) - 0.5) * 2.0,
        abs(fract(p.y * 6.0) - 0.5) * 2.0
    );
    let gridLine = exp(-gridDist * gridDist * 300.0) * 0.06;
    col += vec3<f32>(0.05, 0.02, 0.08) * gridLine;
    
    // Neural network layers
    let totalLayers = 6;
    let totalNodes = 40;
    
    var nodeField: f32 = 1e6;
    var edgeGlow: f32 = 0.0;
    var signalGlow: vec3<f32> = vec3<f32>(0.0);
    var nodeGlow: vec3<f32> = vec3<f32>(0.0);
    
    var edgeIndex: f32 = 0.0;
    
    // Process all nodes and connections
    for (var layer = 0; layer < totalLayers; layer++) {
        let nodesInThisLayer = 4 + layer * 2;
        let nextLayerNodes = 4 + (layer + 1) * 2;
        
        for (var ni = 0; ni < nodesInThisLayer; ni++) {
            let nodePos = getNodePos(layer, ni, totalLayers, time);
            
            // Distance to this node
            let d = length(p - nodePos);
            nodeField = smin(nodeField, d, 0.08);
            
            // Node glow
            let nodeSize = 0.018 + 0.005 * sin(time * 3.0 + f32(layer) * 1.2 + f32(ni) * 0.9);
            let nGlow = exp(-d * d / (nodeSize * nodeSize * 4.0));
            let nodeHue = f32(layer) / f32(totalLayers) + colorShift;
            let nodeCol = neonColor(nodeHue + time * 0.05);
            nodeGlow += nodeCol * nGlow * (0.6 + 0.4 * sin(time * 4.0 + f32(ni) * 1.7));
            
            // Connections to next layer
            if (layer < totalLayers - 1) {
                for (var nj = 0; nj < nextLayerNodes; nj++) {
                    // Only connect some nodes for visual clarity
                    let connectionHash = hash1(f32(layer) * 100.0 + f32(ni) * 17.0 + f32(nj) * 31.0);
                    if (connectionHash > 0.55) {
                        let nextNodePos = getNodePos(layer + 1, nj, totalLayers, time);
                        let edgeDist = sdSegment(p, nodePos, nextNodePos);
                        let edgeWidth = 0.004 * (0.8 + 0.2 * sin(time * 2.0 + f32(layer) * 0.8));
                        
                        // Base edge glow
                        let eGlow = exp(-edgeDist * edgeDist / (edgeWidth * edgeWidth * 12.0));
                        let edgeHue = (f32(layer) / f32(totalLayers) + colorShift) * 0.7;
                        let edgeCol = neonColor2(edgeHue + time * 0.03);
                        edgeGlow += eGlow * 0.25 * intensity;
                        
                        // Signal pulses traveling along edges
                        let edgeLen = length(nextNodePos - nodePos);
                        let pulse = signalPulse(edgeLen, edgeIndex, time, speed * 2.0 + 0.5);
                        let pulseGlow = exp(-edgeDist * edgeDist / (edgeWidth * edgeWidth * 6.0)) * pulse;
                        let sigHue = fract(edgeIndex * 0.15 + time * 0.08 + colorShift);
                        signalGlow += neonColor(sigHue) * pulseGlow * intensity * 2.5;
                        
                        edgeIndex += 1.0;
                    }
                }
            }
            
            // Check proximity to mouse cursor
            if (mouseDown || u.zoom_config.w > 0.5) {
                let toCursor = length(cursorPos - nodePos);
                if (toCursor < 0.35) {
                    let connDist = sdSegment(p, nodePos, cursorPos);
                    let connWidth = 0.006;
                    let connGlow = exp(-connDist * connDist / (connWidth * connWidth * 8.0));
                    let connHue = fract(f32(ni) * 0.1 + time * 0.1 + colorShift);
                    signalGlow += neonColor(connHue) * connGlow * 1.5 * (1.0 - toCursor / 0.35);
                }
            }
        }
    }
    
    // Apply edge glow color
    col += vec3<f32>(0.15, 0.25, 0.4) * edgeGlow;
    
    // Apply signal glow
    col += signalGlow;
    
    // Apply node glow
    col += nodeGlow;
    
    // Central bright core on nodes
    let coreGlow = exp(-nodeField * nodeField * 500.0) * 0.8;
    col += vec3<f32>(0.9, 0.95, 1.0) * coreGlow * intensity;
    
    // Cursor node
    let cursorDist = length(p - cursorPos);
    let cursorGlow = exp(-cursorDist * cursorDist / (cursorRadius * cursorRadius * 4.0));
    let cursorCol = neonColor(0.0 + colorShift + time * 0.05);
    col += cursorCol * cursorGlow * 1.5;
    
    // Vignette
    let vignette = 1.0 - dot(uv, uv) * 0.4;
    col *= vignette;
    
    // Tone mapping and boost
    col = col / (1.0 + col * 0.3);
    col = pow(col, vec3<f32>(0.9, 0.95, 1.1));
    
    // Final output
    textureStore(writeTexture, pixel, vec4<f32>(col * (1.0 + intensity), 1.0));
}