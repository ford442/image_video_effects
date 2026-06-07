// ═══════════════════════════════════════════════════════════════════
//  spec-distance-field-text
//  Category: generative
//  Features: SDF, procedural-text, glyph, signed-distance-field
//  Complexity: Medium
//  Chunks From: none
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  SDF-Based Procedural Text/Glyph Overlay
//  Generates symbolic glyphs as Signed Distance Fields directly in
//  the shader. Enables infinitely smooth scaling, glowing edges,
//  drop shadows, and outline effects from a single distance value.
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

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdCircle(p: vec2<f32>, c: vec2<f32>, r: f32) -> f32 {
    return length(p - c) - r;
}

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Procedural glyph: abstract rune/symbol composed of geometric primitives
fn sdGlyph(p: vec2<f32>, glyphIndex: i32, scale: f32) -> f32 {
    let sp = p / scale;
    var d = 1000.0;

    if (glyphIndex == 0) {
        // Triangle with internal line
        d = min(d, sdSegment(sp, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, -0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(0.3, -0.3), vec2<f32>(0.0, 0.4)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, 0.4), vec2<f32>(-0.3, -0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.15)));
    } else if (glyphIndex == 1) {
        // Circle with cross
        d = min(d, abs(sdCircle(sp, vec2<f32>(0.0), 0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(-0.3, 0.0), vec2<f32>(0.3, 0.0)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.3)));
    } else if (glyphIndex == 2) {
        // Square with diagonal
        d = min(d, sdBox(sp, vec2<f32>(0.3)));
        d = min(d, sdSegment(sp, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, 0.3)));
    } else if (glyphIndex == 3) {
        // Hexagon approximation
        for (var i = 0; i < 6; i = i + 1) {
            let a1 = f32(i) * 1.0472;
            let a2 = f32(i + 1) * 1.0472;
            let p1 = vec2<f32>(cos(a1), sin(a1)) * 0.3;
            let p2 = vec2<f32>(cos(a2), sin(a2)) * 0.3;
            d = min(d, sdSegment(sp, p1, p2));
        }
        d = min(d, sdCircle(sp, vec2<f32>(0.0), 0.1));
    } else {
        // Diamond with dot
        d = min(d, sdSegment(sp, vec2<f32>(0.0, 0.35), vec2<f32>(0.25, 0.0)));
        d = min(d, sdSegment(sp, vec2<f32>(0.25, 0.0), vec2<f32>(0.0, -0.35)));
        d = min(d, sdSegment(sp, vec2<f32>(0.0, -0.35), vec2<f32>(-0.25, 0.0)));
        d = min(d, sdSegment(sp, vec2<f32>(-0.25, 0.0), vec2<f32>(0.0, 0.35)));
        d = min(d, sdCircle(sp, vec2<f32>(0.0), 0.06));
    }

    return d * scale;
}

// Grid of glyphs
fn sdGlyphGrid(p: vec2<f32>, gridScale: f32, time: f32) -> f32 {
    let cell = floor(p * gridScale);
    let local = fract(p * gridScale) - 0.5;
    let glyphIdx = i32(fract(sin(dot(cell, vec2<f32>(12.9898, 78.233))) * 43758.5453) * 5.0);
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
    let overlayMix = mix(0.0, 1.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Base image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Glyph SDF
    let centeredUV = (uv - 0.5) * 2.0;
    var d = sdGlyphGrid(centeredUV, glyphScale, time);

    // Mouse reveals glyphs
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let reveal = exp(-mouseDist * mouseDist * 800.0);
        d -= reveal * 0.02; // Bring glyphs closer near mouse
    }

    // SDF rendering: smooth anti-aliased glyph
    let glyphMask = 1.0 - smoothstep(-glyphWidth, glyphWidth, d);

    // Outer glow
    let outerGlow = exp(-d * d / (glowRadius * glowRadius + 0.0001)) * (1.0 - glyphMask);

    // Drop shadow offset
    let shadowD = sdGlyphGrid(centeredUV - vec2<f32>(0.01, 0.015), glyphScale, time);
    let shadowMask = 1.0 - smoothstep(-glyphWidth * 2.0, glyphWidth * 2.0, shadowD);

    // Glyph color cycling
    let hue = time * 0.1 + centeredUV.x * 0.2 + centeredUV.y * 0.15;
    let glyphColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    let glowColor = glyphColor * 1.5;
    let shadowColor = vec3<f32>(0.0, 0.0, 0.1);

    // Composite
    var outColor = baseColor;
    outColor = mix(outColor, outColor * 0.7 + shadowColor * 0.3, shadowMask * 0.4 * overlayMix);
    outColor = mix(outColor, outColor + glowColor * outerGlow, outerGlow * overlayMix);
    outColor = mix(outColor, glyphColor, glyphMask * overlayMix);

    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, glyphMask + outerGlow));
    textureStore(dataTextureA, gid.xy, vec4<f32>(glyphColor, d));
}
