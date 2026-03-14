// ═══════════════════════════════════════════════════════════════════════════════
//  parallax_depth_layers.wgsl - Multi-Layer Parallax with Depth-Based Alpha
//  
//  RGBA Focus: Each layer has independent alpha (occlusion/fade)
//  Techniques:
//    - 5 depth layers with parallax displacement
//    - Alpha-based layer blending (front layers occlude)
//    - Depth of field blur based on layer distance
//    - Atmospheric perspective (alpha fade with distance)
//    - Mouse-controlled parallax intensity
//  
//  Target: 4.6★ rating
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
const NUM_LAYERS: i32 = 5;

// Hash
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Noise for layer patterns
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM for organic layer shapes
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amp * noise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// Layer color based on depth
fn layerColor(depth: i32, uv: vec2<f32>, time: f32) -> vec4<f32> {
    let fi = f32(depth);
    let layerUV = uv * (1.0 + fi * 0.3);
    
    // Different pattern per layer
    let pattern = fbm(layerUV + vec2<f32>(fi * 10.0, 0.0), 3 + depth);
    
    // Layer-specific color (atmospheric perspective)
    // Far layers = bluer/faded, near layers = warmer/vibrant
    let farColor = vec3<f32>(0.5, 0.6, 0.8); // Blue mist
    let nearColor = vec3<f32>(
        0.8 + sin(fi * 0.5) * 0.2,
        0.6 + cos(fi * 0.7) * 0.3,
        0.4 + sin(fi * 0.3) * 0.2
    );
    
    let t = fi / f32(NUM_LAYERS - 1);
    let baseColor = mix(nearColor, farColor, t);
    
    // Pattern creates holes/transparency
    let threshold = 0.3 + sin(time * 0.2 + fi) * 0.1;
    let alpha = smoothstep(threshold, threshold + 0.2, pattern);
    
    // Far layers more transparent (atmospheric)
    let atmosphericAlpha = alpha * (1.0 - t * 0.6);
    
    // Add some shimmer
    let shimmer = sin(time * 2.0 + pattern * 10.0) * 0.1 + 0.9;
    
    return vec4<f32>(baseColor * shimmer, atmosphericAlpha);
}

// Parallax offset for layer
fn parallaxOffset(layer: i32, mouse: vec2<f32>, intensity: f32) -> vec2<f32> {
    let depth = f32(layer) / f32(NUM_LAYERS);
    // Near layers move more, far layers move less
    return mouse * intensity * (1.0 - depth * 0.8);
}

// Blur for depth of field
fn sampleBlur(uv: vec2<f32>, radius: f32, tex: texture_2d<f32>) -> vec4<f32> {
    var accum = vec4<f32>(0.0);
    let samples = 8;
    
    for (var i: i32 = 0; i < samples; i = i + 1) {
        let fi = f32(i);
        let angle = fi * (2.0 * PI / f32(samples));
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius * 0.01;
        accum += textureSampleLevel(tex, u_sampler, uv + offset, 0.0);
    }
    
    return accum / f32(samples);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let parallaxIntensity = u.zoom_params.x * 0.3; // 0-0.3
    let layerDensity = u.zoom_params.y; // Affects pattern density
    let dofAmount = u.zoom_params.z * 0.05; // Depth of field blur
    let fogDensity = u.zoom_params.w; // Atmospheric fog
    
    // Mouse as view offset
    let mouse = (u.zoom_config.yz - 0.5) * 2.0;
    let audioPulse = u.zoom_config.w;
    
    // Start with background
    var accumRGBA = vec4<f32>(0.1, 0.12, 0.15, 1.0); // Deep background
    
    // Composite layers from back to front
    for (var layer: i32 = NUM_LAYERS - 1; layer >= 0; layer = layer - 1) {
        let fi = f32(layer);
        
        // Parallax offset
        let offset = parallaxOffset(layer, mouse, parallaxIntensity);
        let layerUV = uv + offset;
        
        // Sample layer
        var layerRGBA = layerColor(layer, layerUV * (1.0 + layerDensity), time);
        
        // Audio affects near layers more
        if (layer < 2) {
            layerRGBA.rgb *= 1.0 + audioPulse * 0.5;
            layerRGBA.a = min(layerRGBA.a * (1.0 + audioPulse), 1.0);
        }
        
        // Depth of field blur for far layers
        let blurRadius = dofAmount * fi;
        if (blurRadius > 0.001) {
            let blurred = sampleBlur(layerUV, blurRadius, readTexture);
            layerRGBA = mix(layerRGBA, blurred, fi / f32(NUM_LAYERS) * 0.5);
        }
        
        // Alpha compositing: C = Ca * Aa + Cb * Ab * (1 - Aa)
        let outAlpha = layerRGBA.a + accumRGBA.a * (1.0 - layerRGBA.a);
        let outRGB = layerRGBA.rgb * layerRGBA.a + accumRGBA.rgb * accumRGBA.a * (1.0 - layerRGBA.a);
        
        accumRGBA = vec4<f32>(outRGB / max(outAlpha, 0.001), outAlpha);
    }
    
    // Add atmospheric fog based on depth perception
    let fogColor = vec3<f32>(0.7, 0.8, 0.9);
    let fogFactor = fogDensity * (1.0 - length(mouse) * 0.3);
    accumRGBA.rgb = mix(accumRGBA.rgb, fogColor, fogFactor * 0.3);
    accumRGBA.a = min(accumRGBA.a + fogFactor * 0.1, 1.0);
    
    // HDR tone mapping
    accumRGBA.rgb = accumRGBA.rgb / (1.0 + accumRGBA.rgb * 0.3);
    
    // Vignette affects all layers
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    accumRGBA.rgb *= vignette;
    
    textureStore(writeTexture, coord, accumRGBA);
    textureStore(writeDepthTexture, coord, vec4<f32>(accumRGBA.a, 0.0, 0.0, 1.0));
    
    // Store for potential feedback effects
    textureStore(dataTextureA, coord, accumRGBA);
}
