// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Reveal
//  Category: lighting-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + mids * 0.3;

    // Params
    let revealRadius = (0.2 + u.zoom_params.x * 0.3) * (1.0 + bass * 0.4);
    let edgeBoost = u.zoom_params.y * 2.0 * (1.0 + treble * 0.3);
    let glowIntensity = u.zoom_params.z * 2.0;
    let occlusionBalance = u.zoom_params.w;

    let stepX = 1.0 / max(resolution.x, 1.0);
    let stepY = 1.0 / max(resolution.y, 1.0);

    // Sample neighbors as full vec4 (preserve alpha)
    let s_tl = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_tc = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_tr = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_ml = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_mc = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let s_mr = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_bl = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_bc = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_br = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Sobel on luminance
    let gx = -getLuminance(s_tl.rgb) - 2.0 * getLuminance(s_ml.rgb) - getLuminance(s_bl.rgb)
           + getLuminance(s_tr.rgb) + 2.0 * getLuminance(s_mr.rgb) + getLuminance(s_br.rgb);
    let gy = -getLuminance(s_tl.rgb) - 2.0 * getLuminance(s_tc.rgb) - getLuminance(s_tr.rgb)
           + getLuminance(s_bl.rgb) + 2.0 * getLuminance(s_bc.rgb) + getLuminance(s_br.rgb);
    let edgeStrength = sqrt(gx * gx + gy * gy);

    // Mouse flashlight
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / resolution.y;
    let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mousePos.x * aspect, mousePos.y));
    let revealFalloff = 1.0 - smoothstep(0.0, max(revealRadius, 0.0001), distToMouse);

    // Neon color cycling (mids drives hue speed)
    let neonColor1 = vec3<f32>(1.0, 0.0, 0.8);
    let neonColor2 = vec3<f32>(0.0, 1.0, 1.0);
    let mixFactor = 0.5 + 0.5 * sin(time * 2.0 * audioReactivity + uv.x * 3.0);
    let neonColor = mix(neonColor1, neonColor2, mixFactor);

    // Emission (branchless)
    let edge = smoothstep(0.05, 0.3, edgeStrength);
    let glow = 0.3 + (2.0 + bass * 1.5) * revealFalloff;
    let emission = neonColor * glow * edge * edgeBoost * glowIntensity;

    let glowStrength = length(emission);

    // Meaningful alpha: edge strength + reveal + source alpha + audio sparkle
    let baseAlpha = s_mc.a;
    let alpha = clamp(edge * 0.5 + revealFalloff * 0.3 + baseAlpha * 0.2 + glowStrength * 0.1 * occlusionBalance + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(emission, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(emission, alpha));
}
