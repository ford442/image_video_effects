// ═══════════════════════════════════════════════════════════════════
//  Brush Strokes
//  Category: interactive-mouse
//  Features: mouse-driven, paint-brush, trail, organic
//  Complexity: Medium
//  Created: 2026-05-31
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
    let aspect = resolution.x / resolution.y;

    let brushSize = u.zoom_params.x * 0.15 + 0.02;
    let textureAmount = u.zoom_params.y;
    let wetness = u.zoom_params.z;
    let colorIntensity = u.zoom_params.w * 2.0;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Build brush trail from ripple history
    var brushMask = 0.0;
    var brushColor = vec3<f32>(0.0);
    let rippleCount = u32(u.config.y);

    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 3.0) {
            let age = elapsed / 3.0;
            let pos = ripple.xy;
            let dist = length((uv - pos) * vec2<f32>(aspect, 1.0));

            // Organic brush edge using noise
            let noiseEdge = noise(uv * 15.0 + f32(i) * 7.3) * 0.3;
            let brushRadius = brushSize * (1.0 - age * 0.3) * (1.0 + noiseEdge);

            let brushSoftness = wetness * 0.5 + 0.1;
            let brushShape = smoothstep(brushRadius, brushRadius * (1.0 - brushSoftness), dist);

            // Fade with age
            let fade = 1.0 - smoothstep(0.3, 1.0, age);

            if (brushShape > 0.01) {
                // Sample image at brush position for color
                let sampleUV = clamp(pos + (uv - pos) * (0.8 + wetness * 0.2), vec2<f32>(0.0), vec2<f32>(1.0));
                let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

                // Color shift based on brush index and time
                let hue = fract(f32(i) * 0.07 + time * 0.01);
                let tint = vec3<f32>(
                    0.5 + 0.3 * cos(hue * 6.283 + 0.0),
                    0.5 + 0.3 * cos(hue * 6.283 + 2.094),
                    0.5 + 0.3 * cos(hue * 6.283 + 4.189)
                );

                let mixedColor = mix(sampleColor, sampleColor * tint * 1.5, colorIntensity * 0.5);

                brushMask = max(brushMask, brushShape * fade);
                brushColor = mix(brushColor, mixedColor, brushShape * fade);
            }
        }
    }

    // Active brush when mouse is held
    if (mouseDown) {
        let activeDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
        let noiseEdge = noise(uv * 20.0 + time) * 0.25;
        let activeRadius = brushSize * (1.0 + noiseEdge);
        let activeBrush = smoothstep(activeRadius, activeRadius * 0.3, activeDist);

        if (activeBrush > 0.01) {
            let sampleColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
            let hue = fract(time * 0.05);
            let tint = vec3<f32>(
                0.5 + 0.5 * cos(hue * 6.283 + 0.0),
                0.5 + 0.5 * cos(hue * 6.283 + 2.094),
                0.5 + 0.5 * cos(hue * 6.283 + 4.189)
            );
            let activeColor = mix(sampleColor, sampleColor * tint * 1.3, colorIntensity * 0.3);
            brushMask = max(brushMask, activeBrush);
            brushColor = mix(brushColor, activeColor, activeBrush);
        }
    }

    // Composite brush over base
    let finalColor = mix(baseColor, brushColor, brushMask * (0.5 + textureAmount * 0.5));

    // Add paper grain texture
    let grain = noise(uv * 500.0) * 0.04;
    let finalWithGrain = finalColor * (1.0 - grain) + grain * 0.5;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithGrain, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
