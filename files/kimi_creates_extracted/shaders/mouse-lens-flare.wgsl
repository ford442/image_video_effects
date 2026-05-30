// ═══════════════════════════════════════════════════════════════════
//  Mouse Lens Flare
//  Category: interactive-mouse
//  Features: mouse-driven, lens-flare, chromatic-aberration, anamorphic
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

fn flareGlow(uv: vec2<f32>, pos: vec2<f32>, size: f32, intensity: f32) -> f32 {
    let d = length((uv - pos));
    return exp(-d * d / (size * size)) * intensity;
}

fn anamorphicStreak(uv: vec2<f32>, pos: vec2<f32>, length: f32, width: f32, intensity: f32) -> f32 {
    let dx = uv.x - pos.x;
    let dy = uv.y - pos.y;
    let alongAxis = abs(dx);
    let perpAxis = abs(dy);
    let streak = exp(-alongAxis * alongAxis / (length * length)) * exp(-perpAxis * perpAxis / (width * width));
    return streak * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let flareIntensity = u.zoom_params.x * 2.0;
    let chromaticAmount = u.zoom_params.y * 0.03;
    let streakLength = u.zoom_params.z * 0.5 + 0.05;
    let hueShift = u.zoom_params.w;

    var mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Base image
    var baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Chromatic aberration near the flare center
    let mouseAspect = mouse * vec2<f32>(aspect, 1.0);
    let uvAspect = uv * vec2<f32>(aspect, 1.0);
    let centerDist = length(uvAspect - mouseAspect);

    var chromaticUV = (uv - mouse) * chromaticAmount * (1.0 / (centerDist + 0.1));
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + chromaticUV * 1.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + chromaticUV * 1.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + chromaticUV * 0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    baseColor = mix(baseColor, vec3<f32>(r, g, b), smoothstep(0.0, 0.3, chromaticAmount));

    // Lens flare elements
    var flare = vec3<f32>(0.0);

    // Main star burst
    let starBurst = flareGlow(uv, mouse, 0.02, flareIntensity);
    flare += vec3<f32>(1.0, 0.95, 0.85) * starBurst;

    // Anamorphic horizontal streak
    let streak = anamorphicStreak(uv, mouse, streakLength, 0.008, flareIntensity * 0.8);
    flare += vec3<f32>(0.8, 0.9, 1.0) * streak;

    // Secondary ghost orbs along the axis opposite to center
    let centerDir = normalize(mouse - vec2<f32>(0.5));
    for (var i: i32 = 1; i <= 5; i = i + 1) {
        let t = f32(i);
        let ghostPos = mouse - centerDir * t * 0.08;
        let ghostSize = 0.01 + t * 0.005;
        let ghostIntensity = flareIntensity * (0.3 / t);
        let ghost = flareGlow(uv, ghostPos, ghostSize, ghostIntensity);

        // Rainbow color for ghosts
        let hue = fract(hueShift + t * 0.15 + time * 0.02);
        let ghostColor = vec3<f32>(
            0.5 + 0.5 * cos(hue * 6.283 + 0.0),
            0.5 + 0.5 * cos(hue * 6.283 + 2.094),
            0.5 + 0.5 * cos(hue * 6.283 + 4.189)
        );
        flare += ghostColor * ghost;
    }

    // Halo ring
    let haloDist = abs(centerDist - 0.15);
    let halo = exp(-haloDist * haloDist * 400.0) * flareIntensity * 0.3;
    flare += vec3<f32>(0.6, 0.7, 0.9) * halo;

    // Composite
    let finalColor = baseColor + flare;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
