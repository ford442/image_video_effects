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
    let stroke = sin(angle * 3.0 + time * speed * 4.0) * 0.5 + 0.5;

    let hue = fract(time * 0.05 + colorIntensity * 0.3 + mids * 0.2);
    let tint = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.283 + 0.0),
        0.5 + 0.5 * cos(hue * 6.283 + 2.094),
        0.5 + 0.5 * cos(hue * 6.283 + 4.189)
    );

    let activeColor = mix(baseColor, baseColor * tint * 1.3, colorIntensity * 0.3);

    let brushMask = activeBrush * (0.4 + stroke * 0.6) * (0.8 + bass * 0.4);
    let brushColor = mix(baseColor, activeColor, brushMask);

    // Add paper grain texture
    let grain = noise(uv * 500.0 + time * 0.3) * 0.04 * (0.5 + treble * 0.5);
    let finalWithGrain = brushColor * (1.0 - grain) + grain * 0.5;

    // Semantic alpha
    let semantic_alpha = clamp(0.52 + brushMask * 0.7, 0.4, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithGrain, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}