// ═══════════════════════════════════════════════════════════════════
//  Scanline Cyberpunk
//  Category: image
//  Features: audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Chunks From: noise.wgsl
//  Created: 2026-05-30
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════
//  CRT scanline grid layered with a cyberpunk colour grading pass.
//  Horizontal scanlines dim every other row; vertical phosphor
//  columns add a subtle RGB triad mask. Bass drives a glitch-roll
//  offset; treble flickers brightness. The colour grade pushes
//  shadows toward teal and highlights toward magenta/amber.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=ScanlineIntensity, y=PhosphorMask, z=GlitchAmount, w=ColorGrade
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash3 (from noise.wgsl) ═══
fn hash3(p: vec2f) -> vec3f {
  let q = vec3f(dot(p, vec2f(127.1, 311.7)),
                dot(p, vec2f(269.5, 183.3)),
                dot(p, vec2f(419.2, 371.9)));
  return fract(sin(q) * 43758.5453);
}
// ════════════════════════════════════════

// Teal-shadow / amber-highlight colour grade (cinematic LUT-style)
fn colorGrade(col: vec3<f32>, strength: f32) -> vec3<f32> {
    // ═══ CHUNK: luma (from color.wgsl) ═══
    const kLuma = vec3f(0.2126, 0.7152, 0.0722);
    let luma = saturate(dot(col, kLuma));
    // ══════════════════════════════════════

    // Shadow teal: push low luma toward (0.05, 0.12, 0.15) teal
    let shadowTint   = vec3<f32>(0.05, 0.12, 0.15);
    // Highlight amber: push high luma toward (0.15, 0.08, 0.02)
    let highlightTint = vec3<f32>(0.15, 0.08, 0.02);

    let shadowBlend    = (1.0 - luma) * (1.0 - luma);
    let highlightBlend = luma * luma;

    let graded = col
        + shadowTint    * shadowBlend    * strength
        - highlightTint * highlightBlend * strength * 0.5
        + highlightTint * highlightBlend * strength;

    return graded;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio — read from plasmaBuffer[0].xyz as vec3f(bass, mids, treble)
    let audio = plasmaBuffer[0].xyz;
    let bass   = audio.x;
    let mid    = audio.y;
    let treble = audio.z;

    // Params
    let scanlineStr  = mix(0.0, 0.7,  u.zoom_params.x);
    let phosphorStr  = mix(0.0, 0.5,  u.zoom_params.y);
    let glitchAmt    = mix(0.0, 0.04, u.zoom_params.z) * (1.0 + bass * 2.0);
    let gradeStr     = mix(0.0, 1.0,  u.zoom_params.w);

    // Glitch roll: bass-driven horizontal displacement bands
    let glitchBand   = floor(uv.y * 20.0 + time * 3.0);
    let glitchOffset = (hash3(vec2f(glitchBand + floor(time * 8.0), 0.0)).x * 2.0 - 1.0) * glitchAmt * bass;
    var sampleUV     = clamp(vec2<f32>(uv.x + glitchOffset, uv.y), vec2<f32>(0.0), vec2<f32>(1.0));

    let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    var col = src.rgb;

    // Scanline mask: darken every other line
    let scanlineRow  = gid.y % 2u;
    let scanlineMask = select(1.0 - scanlineStr, 1.0, scanlineRow == 0u);
    col *= scanlineMask;

    // Phosphor RGB triad: three sub-pixel columns per 3-pixel group — branchless
    let triadCol = gid.x % 3u;
    let pDim = select(1.0, 1.0 - phosphorStr * 0.5, phosphorStr > 0.0);
    let isR = triadCol == 0u;
    let isG = triadCol == 1u;
    let isB = triadCol == 2u;
    let r = select(pDim, 1.0, isR);
    let g = select(pDim, 1.0, isG);
    let b = select(pDim, 1.0, isB);
    let phosphor = vec3f(r, g, b);
    col *= phosphor;

    // Treble flicker
    let flicker = 1.0 + treble * 0.08 * sin(time * 60.0);
    col *= flicker;

    // Neon bloom: add a faint neon haze proportional to brightness
    // ═══ CHUNK: luma (from color.wgsl) ═══
    const kLuma = vec3f(0.2126, 0.7152, 0.0722);
    let lumaOrig    = dot(src.rgb, kLuma);
    // ══════════════════════════════════════
    let neonOverlay = vec3<f32>(0.0, 0.9, 0.8) * lumaOrig * 0.08 * (1.0 + mid);
    col += neonOverlay;

    // Cinematic colour grade
    col = colorGrade(col, gradeStr);

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.4));

    // Semantic alpha — use saturate for [0,1] clamping
    let alpha = saturate(src.a);

    let outColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(lumaOrig, scanlineMask, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(bass, mid, treble, glitchOffset));
}
