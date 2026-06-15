// ═══ spec-distance-field-text ═══════════════════════════════════════════
//  Category: generative
//  Features: SDF, procedural-text, glyph, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, chromatic-aberration,
//            signed-distance-field, slot-chain
//  Complexity: Medium

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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Core math ─────────────────────────────────────────────────────────
fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}

fn domainWarp(p: vec2<f32>, strength: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + strength * q;
}

// ── SDF primitives ────────────────────────────────────────────────────
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdGlyph0(p: vec2<f32>) -> f32 {
    return min(min(sdSegment(p, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, -0.3)),
                   sdSegment(p, vec2<f32>(0.3, -0.3), vec2<f32>(0.0, 0.4))),
               min(sdSegment(p, vec2<f32>(0.0, 0.4), vec2<f32>(-0.3, -0.3)),
                   sdSegment(p, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.15))));
}

fn sdGlyph1(p: vec2<f32>) -> f32 {
    return min(min(abs(length(p) - 0.3),
                   sdSegment(p, vec2<f32>(-0.3, 0.0), vec2<f32>(0.3, 0.0))),
               sdSegment(p, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.3)));
}

fn sdGlyph2(p: vec2<f32>) -> f32 {
    let db = abs(p) - vec2<f32>(0.3);
    return min(min(max(db.x, db.y), 0.0) + length(max(db, vec2<f32>(0.0))),
               sdSegment(p, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, 0.3)));
}

fn sdGlyph3(p: vec2<f32>) -> f32 {
    let d = min(min(min(sdSegment(p, vec2<f32>(0.0, 0.35), vec2<f32>(0.25, 0.0)),
                        sdSegment(p, vec2<f32>(0.25, 0.0), vec2<f32>(0.0, -0.35))),
                    sdSegment(p, vec2<f32>(0.0, -0.35), vec2<f32>(-0.25, 0.0))),
                sdSegment(p, vec2<f32>(-0.25, 0.0), vec2<f32>(0.0, 0.35)));
    return min(d, length(p) - 0.06);
}

// Branchless glyph selection — computes all four distances and selects by index.
fn sdGlyph(p: vec2<f32>, idx: i32, scale: f32) -> f32 {
    let sp = p / scale;
    let d0 = sdGlyph0(sp); let d1 = sdGlyph1(sp);
    let d2 = sdGlyph2(sp); let d3 = sdGlyph3(sp);
    let d = select(select(select(d3, d2, idx == 2), d1, idx == 1), d0, idx == 0);
    return d * scale;
}

fn sdGlyphGrid(p: vec2<f32>, gridScale: f32, time: f32) -> f32 {
    let cell = floor(p * gridScale);
    let local = fract(p * gridScale) - 0.5;
    let h = hash21(cell);
    let glyphIdx = i32(h * 4.0);
    let pulse = 1.0 + sin(time * 2.0 + cell.x * 3.0 + cell.y * 2.0) * 0.1;
    return sdGlyph(local, glyphIdx, pulse / gridScale);
}

// ── Color utilities ───────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Entry point ───────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (uv01 - 0.5) * 2.0;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Parameter mapping
    let glyphScale = mix(2.0, 12.0, p1);
    let glyphWidth = mix(0.003, 0.02, p2);
    let glowRadius = mix(0.0, 0.05, p3);
    let overlayMix = p4;

    // Base image from slot chain
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;

    // Domain-warp the glyph coordinate for organic audio-reactive motion
    let warpStr = 0.02 + bass * 0.03;
    let warpedUV = domainWarp(uv, warpStr);

    // Glyph SDF
    var d = sdGlyphGrid(warpedUV, glyphScale, time);

    // Branchless mouse reveal
    let mouseDist = length(uv01 - mouse);
    let reveal = fast_exp(-mouseDist * mouseDist * 800.0) * step(0.5, u.zoom_config.w);
    d -= reveal * 0.02;

    // SDF masks
    let glyphMask = 1.0 - smoothstep(-glyphWidth, glyphWidth, d);
    let glowMask = fast_exp(-d * d / (glowRadius * glowRadius + 1e-4)) * (1.0 - glyphMask);
    let shadowMask = 1.0 - smoothstep(-glyphWidth * 2.0, glyphWidth * 2.0, d + 0.025);

    // Glyph color cycling with audio-driven hue shift
    let hue = time * 0.1 + uv.x * 0.2 + uv.y * 0.15 + mids * 0.3 + treble * 0.1;
    let glyphColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * (hue + 0.0)),
        0.5 + 0.5 * cos(TAU * (hue + 0.3333)),
        0.5 + 0.5 * cos(TAU * (hue + 0.6667))
    );
    let glowColor = glyphColor * (1.5 + bass);

    // Composite with depth-aware shadow
    let depthMod = 0.5 + depth * 0.5;
    var outColor = baseColor;
    outColor = mix(outColor, outColor * 0.7 + vec3<f32>(0.0, 0.0, 0.1) * 0.3,
                   shadowMask * 0.4 * overlayMix * depthMod);
    outColor = mix(outColor, outColor + glowColor * glowMask, glowMask * overlayMix);
    outColor = mix(outColor, glyphColor, glyphMask * overlayMix);

    // Generative chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    let dir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    outColor = vec3<f32>(
        outColor.r + dir.x * caStr,
        outColor.g,
        outColor.b - dir.y * caStr * 0.5
    );

    // ACES tone map and semantic alpha
    outColor = acesToneMap(outColor * (0.9 + mids * 0.2));
    let alpha = clamp(luma(outColor) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);

    // Temporal feedback trail
    let decay = 0.97 - p4 * 0.02;
    let trail = mix(prev.rgb * decay, outColor, 0.2 + bass * 0.1);

    textureStore(writeTexture, pixel, vec4<f32>(outColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(glyphColor, d));
}
