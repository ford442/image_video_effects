// ═══════════════════════════════════════════════════════════════════
//  Depth Displacement
//  Category: hybrid
//  Features: depth-aware, parallax, spatial-displacement, mouse-driven
//  Complexity: High
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let displacement = u.zoom_params.x * 0.06;
    let depthScale = u.zoom_params.y * 2.0;
    let smoothing = u.zoom_params.z;
    let rippleStrength = u.zoom_params.w * 0.03;

    var mouse = u.zoom_config.yz;

    // Read depth for this pixel
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize depth: 0 = far, 1 = near
    let normalizedDepth = clamp(depth * depthScale, 0.0, 1.0);

    // Compute parallax offset based on mouse position and depth
    // Far objects move less, near objects move more
    let mouseOffset = mouse - vec2<f32>(0.5);
    let parallaxAmount = displacement * (1.0 - normalizedDepth);

    var displacedUV = uv - mouseOffset * parallaxAmount;

    // Add subtle ripple distortion that responds to depth
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 3.0) {
            let ripplePos = ripple.xy;
            let dist = length((uv - ripplePos) * vec2<f32>(aspect, 1.0));
            let rippleRadius = elapsed * 0.3;
            let rippleWidth = 0.03;
            let ripplePhase = dist * 20.0 - elapsed * 8.0;
            let rippleWave = sin(ripplePhase) * exp(-elapsed * 1.5);

            // Depth-aware ripple: stronger on foreground
            let depthRippleStrength = rippleStrength * (0.5 + (1.0 - normalizedDepth) * 0.5);
            let rippleMask = smoothstep(rippleRadius + rippleWidth, rippleRadius, dist);
            displacedUV += vec2<f32>(rippleWave) * rippleMask * depthRippleStrength;
        }
    }

    // Add wave distortion that varies by depth layer
    let waveX = sin(uv.y * 10.0 + time * 0.5 + normalizedDepth * PI) * displacement * 0.3;
    let waveY = cos(uv.x * 10.0 + time * 0.7 + normalizedDepth * PI) * displacement * 0.3;
    displacedUV += vec2<f32>(waveX, waveY) * smoothing;

    displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Depth-based color grading: tint far objects cooler
    let farTint = vec3<f32>(0.85, 0.9, 1.0);
    let nearTint = vec3<f32>(1.0, 1.0, 1.0);
    let depthTint = mix(farTint, nearTint, normalizedDepth);

    let finalColor = color * depthTint;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
