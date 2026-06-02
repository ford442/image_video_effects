// ═══════════════════════════════════════════════════════════════════
//  Lenticular Holographic Shift
//  Category: image
//  Features: lenticular, holographic, moire, perspective-shift, audio-beat, mouse-view, semantic-alpha
//  Complexity: Medium-High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — holographic lenticular print that shifts color and perspective with mouse and audio rhythm)
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
  zoom_params: vec4<f32>,  // x=Shift, y=Frequency, z=Color, w=Beat
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let shiftAmt = u.zoom_params.x * (0.8 + bass * 0.5);
    let freq = u.zoom_params.y * 22.0 + 6.0;
    let colorShift = u.zoom_params.z;
    let beat = u.zoom_params.w * (0.7 + treble * 0.9);

    let mouse = u.zoom_config.yz;
    let viewAngle = (mouse.x - 0.5) * 1.6 + sin(time * 0.3) * 0.1;

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Lenticular slicing — vertical strips that shift with view
    let strip = fract(uv.x * freq + viewAngle * shiftAmt * 1.8);
    let band = smoothstep(0.0, 0.18, strip) - smoothstep(0.82, 1.0, strip);

    // Three color channels offset by view angle (holographic)
    let rUV = uv + vec2<f32>(viewAngle * shiftAmt * 0.012, 0.0);
    let gUV = uv + vec2<f32>(viewAngle * shiftAmt * 0.003, 0.0);
    let bUV = uv + vec2<f32>(viewAngle * shiftAmt * -0.009, 0.0);

    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var col = vec3<f32>(r, g, b);

    // Strong moiré interference when view + audio align
    let moire = sin(strip * 38.0 + viewAngle * 14.0 + time * beat * 4.0) * 0.5 + 0.5;
    let moireMask = pow(moire * band, 1.6) * (0.4 + mids * 0.5);

    // Holographic color cycling
    let hue = fract(uv.y * 0.6 + viewAngle * 0.4 + time * 0.08 + colorShift);
    let holo = vec3<f32>(
        0.5 + 0.5 * sin(hue * 6.28318),
        0.5 + 0.5 * sin(hue * 6.28318 + 2.094),
        0.5 + 0.5 * sin(hue * 6.28318 + 4.188)
    );

    col = mix(col, col * holo, moireMask * 0.85);

    // Audio beat pulses the interference
    col += holo * moireMask * beat * 0.35;

    // Subtle vignette for print feel
    let vign = smoothstep(0.72, 0.38, length(uv - 0.5));
    col *= 0.7 + vign * 0.3;

    // Semantic alpha — higher on strong holographic bands
    let semantic_alpha = clamp(0.68 + moireMask * 0.55, 0.55, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Depth from holographic energy
    let d = clamp(0.28 + moireMask * 0.5, 0.0, 0.94);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    textureStore(dataTextureA, global_id.xy, vec4<f32>(strip, moire, viewAngle, semantic_alpha));
}
