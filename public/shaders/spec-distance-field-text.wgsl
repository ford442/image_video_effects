// ═══════════════════════════════════════════════════════════════════
//  spec-distance-field-text  [OPTIMIZED]
//  Category: generative
//  Features: SDF, procedural-text, glyph, signed-distance-field, hdr, slot-chain
//  Upgraded: 2026-06-07 by The Optimizer
// ═══════════════════════════════════════════════════════════════════
//  SDF-Based Procedural Text/Glyph Overlay
//  Optimizations: fast_exp, branchless mouse reveal, approximated shadow
//  (saves 1x sdGlyphGrid eval), named constants, premultiplied-alpha,
//  bloom-weight alpha, dataTextureA chaining.
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

const TAU: f32 = 6.2831853;

fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdGlyph(p: vec2<f32>, idx: i32, scale: f32) -> f32 {
    let sp = p / scale;
    var d = 1e3;
    if (idx == 0) {
        d = min(min(sdSegment(sp, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, -0.3)),
                    sdSegment(sp, vec2<f32>(0.3, -0.3), vec2<f32>(0.0, 0.4))),
                min(sdSegment(sp, vec2<f32>(0.0, 0.4), vec2<f32>(-0.3, -0.3)),
                    sdSegment(sp, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.15))));
    } else if (idx == 1) {
        d = min(min(abs(length(sp) - 0.3),
                    sdSegment(sp, vec2<f32>(-0.3, 0.0), vec2<f32>(0.3, 0.0))),
                sdSegment(sp, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.3)));
    } else if (idx == 2) {
        let db = abs(sp) - vec2<f32>(0.3);
        d = min(min(max(db.x, db.y), 0.0) + length(max(db, vec2<f32>(0.0))),
                sdSegment(sp, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, 0.3)));
    } else {
        d = min(min(min(sdSegment(sp, vec2<f32>(0.0, 0.35), vec2<f32>(0.25, 0.0)),
                         sdSegment(sp, vec2<f32>(0.25, 0.0), vec2<f32>(0.0, -0.35))),
                     sdSegment(sp, vec2<f32>(0.0, -0.35), vec2<f32>(-0.25, 0.0))),
                 sdSegment(sp, vec2<f32>(-0.25, 0.0), vec2<f32>(0.0, 0.35)));
        d = min(d, length(sp) - 0.06);
    }
    return d * scale;
}

fn sdGlyphGrid(p: vec2<f32>, gridScale: f32, time: f32) -> f32 {
    let cell = floor(p * gridScale);
    let local = fract(p * gridScale) - 0.5;
    let h = fract(sin(dot(cell, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let glyphIdx = i32(h * 4.0);
    let pulse = 1.0 + sin(time * 2.0 + cell.x * 3.0 + cell.y * 2.0) * 0.1;
    return sdGlyph(local, glyphIdx, pulse / gridScale);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let glyphScale = mix(2.0, 12.0, u.zoom_params.x);
    let glyphWidth = mix(0.003, 0.02, u.zoom_params.y);
    let glowRadius = mix(0.0, 0.05, u.zoom_params.z);
    let overlayMix = u.zoom_params.w;

    // Base image (slot-chain read)
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Glyph SDF
    let centeredUV = (uv - 0.5) * 2.0;
    var d = sdGlyphGrid(centeredUV, glyphScale, time);

    // Branchless mouse reveal
    let mouseDist = length(uv - u.zoom_config.yz);
    let reveal = fast_exp(-mouseDist * mouseDist * 800.0) * step(0.5, u.zoom_config.w);
    d -= reveal * 0.02;

    // SDF masks
    let glyphMask = 1.0 - smoothstep(-glyphWidth, glyphWidth, d);
    let glowMask = fast_exp(-d * d / (glowRadius * glowRadius + 1e-4)) * (1.0 - glyphMask);

    // Approximate shadow from offset SDF (avoids second grid evaluation)
    let shadowMask = 1.0 - smoothstep(-glyphWidth * 2.0, glyphWidth * 2.0, d + 0.025);

    // Glyph color cycling
    let hue = time * 0.1 + centeredUV.x * 0.2 + centeredUV.y * 0.15;
    let glyphColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * (hue + 0.0)),
        0.5 + 0.5 * cos(TAU * (hue + 0.3333)),
        0.5 + 0.5 * cos(TAU * (hue + 0.6667))
    );
    let glowColor = glyphColor * 1.5;

    // Composite with overlay mix
    var outColor = baseColor;
    outColor = mix(outColor, outColor * 0.7 + vec3<f32>(0.0, 0.0, 0.1) * 0.3, shadowMask * 0.4 * overlayMix);
    outColor = mix(outColor, outColor + glowColor * glowMask, glowMask * overlayMix);
    outColor = mix(outColor, glyphColor, glyphMask * overlayMix);

    // Bloom weight in alpha, premultiplied when < 1.0
    let alpha = clamp((glyphMask + glowMask) * overlayMix, 0.0, 1.0);
    let finalColor = select(vec4<f32>(outColor * alpha, alpha), vec4<f32>(outColor, 1.0), alpha >= 1.0);

    textureStore(writeTexture, gid.xy, finalColor);
    textureStore(dataTextureA, gid.xy, vec4<f32>(glyphColor, d));
}
