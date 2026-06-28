// ═══════════════════════════════════════════════════════════════════
//  Brush Strokes
//  Category: interactive-mouse
//  Features: mouse-driven, paint-brush, trail, organic, audio-reactive, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (integrated + upgraded)
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

const PI: f32 = 3.141592653589793;

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

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var a = 0.5;
    var s = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        s = s + noise(p) * a;
        p = p * 2.08 + vec2<f32>(13.7, 5.9);
        a = a * 0.5;
    }
    return s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse = u.zoom_config.yz;
    let isPress = u.zoom_config.w;

    let brushSize = u.zoom_params.x;
    let textureAmount = u.zoom_params.y;
    let colorIntensity = u.zoom_params.z;
    let speed = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    let dist = length(uv - mouse);
    let activeBrush = smoothstep(brushSize * 0.9, brushSize * 0.15, dist) * (0.5 + isPress * 1.3);

    let angle = atan2(uv.y - mouse.y, uv.x - mouse.x);
    let bristleNoise = fbm(uv * vec2<f32>(36.0, 120.0) + vec2<f32>(time * 0.18, -time * 0.07));
    let stroke = sin(angle * 5.0 + time * speed * 4.0 + bristleNoise * 3.2) * 0.5 + 0.5;

    let hue = fract(time * 0.05 + colorIntensity * 0.3 + mids * 0.2);
    let tint = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.283 + 0.0),
        0.5 + 0.5 * cos(hue * 6.283 + 2.094),
        0.5 + 0.5 * cos(hue * 6.283 + 4.189)
    );

    let warmGlaze = mix(tint, vec3<f32>(1.0, 0.72, 0.42), bass * 0.35);
    let activeColor = mix(baseColor, baseColor * warmGlaze * 1.45, colorIntensity * 0.42);

    let brushMask = activeBrush * (0.4 + stroke * 0.6) * (0.8 + bass * 0.4);
    let impasto = pow(brushMask, 2.4) * (0.35 + bristleNoise * 0.75);
    let wetEdge = smoothstep(brushSize * 0.88, brushSize * 0.45, dist) * smoothstep(brushSize * 0.12, brushSize * 0.55, dist);
    var hdr = mix(baseColor, activeColor, brushMask);
    hdr = hdr + tint * impasto * (0.65 + mids * 0.55);
    hdr = hdr + vec3<f32>(1.0, 0.86, 0.62) * wetEdge * treble * 0.35;

    // Add paper grain texture
    let grain = noise(uv * 500.0 + time * 0.3) * 0.045 * (0.5 + treble * 0.5);
    hdr = hdr * (1.0 - grain) + vec3<f32>(grain * 0.48);
    let vignette = mix(1.0, 0.72, smoothstep(0.45, 1.0, length(uv - vec2<f32>(0.5)) * 1.414));
    hdr = hdr * vignette;
    let dither = (ign(vec2<f32>(global_id.xy) + time * 17.0) - 0.5) / 255.0;
    let finalWithGrain = clamp(aces(hdr * (1.08 + colorIntensity * 0.18)) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Semantic alpha
    let hdrLuma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let semantic_alpha = clamp(0.24 + brushMask * 0.48 + pow(max(0.0, hdrLuma - 0.58), 2.0) * 2.5, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithGrain * semantic_alpha, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
