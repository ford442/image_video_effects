// ═══════════════════════════════════════════════════════════════════
//  Klein Bottle Walk
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-09-13
//  Ideas: orientation-reversing glide seam; walker footprint trail from C
//  A packing: ACES display RGBA (C read back as colour history)
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        val = val + amp * noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return val;
}

// Klein bottle parametric with UV mapping
fn kleinBottlePoint(u: f32, v: f32, r: f32) -> vec3<f32> {
    let cu = cos(u);
    let su = sin(u);
    let cv = cos(v);
    let sv = sin(v);
    let x = (r + cu * 0.5) * cv;
    let y = (r + cu * 0.5) * sv;
    let z = su * 0.5;
    return vec3<f32>(x, y, z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let resolution = vec2<f32>(u.config.zw);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    
    // Slider roles follow the JSON: x Walk Speed, y Texture Density, z Light Intensity, w Color Shift
    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;
    
    // Walk position on Klein bottle surface
    let walkSpeed = mix(0.1, 0.5, param1);
    let walkU = time * walkSpeed + uv.x * 6.283185;
    let walkV = time * walkSpeed * 0.7 + uv.y * 6.283185;
    
    let kb = kleinBottlePoint(walkU, walkV, 1.0 + bass * 0.3);
    
    // Idea 1: orientation-reversing seam — each wrap of v returns the surface mirror-flipped
    let loopV = walkV / 6.283185;
    let flipped = (floor(loopV) % 2.0 + 2.0) % 2.0;
    let orient = 1.0 - 2.0 * flipped;
    let seamDist = abs(fract(loopV + 0.5) - 0.5);
    let seamGlow = exp(-seamDist * mix(90.0, 55.0, bass)) * (0.8 + treble * 0.6);
    
    // Surface texture from FBM (texture u mirrored on the flipped sheet)
    let texCoord = vec2<f32>(orient * walkU / 6.283185, loopV);
    let surfaceNoise = fbm(texCoord * mix(4.0, 16.0, param2) + vec2<f32>(time * 0.05), 4);
    
    // Curvature approximation for lighting
    let kb_u = kleinBottlePoint(walkU + 0.01, walkV, 1.0);
    let kb_v = kleinBottlePoint(walkU, walkV + 0.01, 1.0);
    let du = kb_u - kb;
    let dv = kb_v - kb;
    // Idea 1: normal inverted on the flipped sheet — the lit side becomes the far side
    let normal = normalize(cross(du, dv)) * orient;
    
    let lightGain = mix(0.4, 1.6, param3);
    let lightDir = normalize(vec3<f32>(sin(time * 0.2), cos(time * 0.15), 0.8));
    let diffuse = max(dot(normal, lightDir), 0.0) * lightGain;
    let specular = pow(max(dot(normal, normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0))), 0.0), 32.0) * lightGain;
    
    // Audio-driven color
    let hue = fract(kb.z * 0.3 + surfaceNoise * 0.4 + time * 0.02 + mids * 0.1);
    let sat = mix(0.3, 0.85, param4 + treble * 0.2);
    let val = mix(0.2, 1.0, diffuse + surfaceNoise * 0.3 + bass * 0.2);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    let specColor = vec3<f32>(1.0, 0.9, 0.7) * specular * (1.0 + treble);
    let seamColor = mix(vec3<f32>(1.0, 0.55, 0.2), hue2rgb(hue + 0.5), 0.35) * seamGlow * 1.5;
    
    let finalRGB = rgb * val + specColor + seamColor;
    let displayRGB = acesToneMap(finalRGB * 1.1);
    
    // Idea 2: walker footprint trail — highlights from last frame lag behind the scrolling walk
    let coord = vec2<i32>(global_id.xy);
    let scrollDir = normalize(vec2<f32>(1.0, 0.7));
    let trailLen = mix(2.0, 6.0, param1) * (1.0 + bass * 0.5);
    let trailCoord = clamp(vec2<i32>(vec2<f32>(coord) + scrollDir * trailLen),
                           vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, trailCoord, 0);
    let prevLum = dot(prev.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let trailMask = smoothstep(0.55, 0.9, prevLum);
    let trailRGB = max(displayRGB, prev.rgb * 0.88 * trailMask);
    let trailAmt = max(max(trailRGB.r, trailRGB.g), trailRGB.b) - max(max(displayRGB.r, displayRGB.g), displayRGB.b);
    
    let alpha = clamp(diffuse * 0.5 + surfaceNoise * 0.3 + specular * 0.2 + seamGlow * 0.3 + trailAmt * 0.5 + 0.15, 0.0, 1.0);
    let finalColor = vec4<f32>(trailRGB, alpha);
    
    let depth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
