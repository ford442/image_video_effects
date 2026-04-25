// ═══════════════════════════════════════════════════════════════════
//  Bilateral Dream
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: bilateral
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Accumulated weighted color (HDR, unclamped during accumulation)
//    Alpha: Accumulated weight normalization factor — storing the running
//           sum of Gaussian weights allows deferred normalization, which is
//           numerically more stable than normalizing per-sample in low-
//           precision formats.
//
//  MOUSE INTERACTIVITY:
//    Mouse position controls a varying-radius bilateral region.
//    Near mouse = sharp (small sigma), far from mouse = dreamy smooth (large sigma).
//    Ripples trigger "shockwaves" of sharpness radiating outward.
//
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    var d = q.x - min(q.w, q.y);
    let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
    return vec3<f32>(h, d, q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - 3.0);
    return c.z * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Parameters
    let spatialSigmaBase = mix(0.1, 1.0, u.zoom_params.x);
    let colorSigma = mix(0.05, 1.0, u.zoom_params.y);
    let hueShiftAmt = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse distance modulation
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
    let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);
    
    // Ripple shockwaves
    var rippleSharpness = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
            rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
        }
    }
    let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);
    
    // Bilateral filter core
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let radius = i32(ceil(finalSigma * 2.5));
    let maxRadius = min(radius, 7);
    
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
            
            let colorDist = length(neighbor.rgb - center.rgb);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
            
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
        }
    }
    
    // Deferred normalization
    var result = vec3<f32>(0.0);
    if (accumWeight > 0.001) {
        result = accumColor / accumWeight;
    } else {
        result = center.rgb;
    }
    
    // Psychedelic hue shift post-processing
    if (hueShiftAmt > 0.0) {
        let hsv = rgb2hsv(result);
        let newHue = fract(hsv.x + hueShiftAmt + mouseDist * 0.3 + time * 0.05);
        result = hsv2rgb(vec3<f32>(newHue, hsv.y, hsv.z));
    }
    
    // Store raw accumulation — alpha = weight sum for deferred normalization
    textureStore(writeTexture, global_id.xy, vec4<f32>(result, accumWeight));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
