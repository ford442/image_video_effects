// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Dissolve
//  Category: image
//  Features: audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Chunks From: noise.wgsl
//  Created: 2026-05-30
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════
//  Detects edges in the source, overlays glowing neon halos that
//  pulse with audio bass, and dissolves the image interior into
//  luminous colour noise driven by mid/treble frequencies.
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
  zoom_params: vec4<f32>, // x=GlowRadius, y=DissolveAmount, z=NeonSaturation, w=EdgeSharpness
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265358979;

// ═══ CHUNK: hash3 (from noise.wgsl) ═══
fn hash3(p: vec2f) -> vec3f {
  let q = vec3f(dot(p, vec2f(127.1, 311.7)),
                dot(p, vec2f(269.5, 183.3)),
                dot(p, vec2f(419.2, 371.9)));
  return fract(sin(q) * 43758.5453);
}
// ════════════════════════════════════════

fn sobel(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-ps.x,  ps.y), 0.0).rgb;
    let tc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,   ps.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( ps.x,  ps.y), 0.0).rgb;
    let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-ps.x,  0.0 ), 0.0).rgb;
    let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( ps.x,  0.0 ), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-ps.x, -ps.y), 0.0).rgb;
    let bc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,  -ps.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( ps.x, -ps.y), 0.0).rgb;

    // ═══ CHUNK: luma (from color.wgsl) ═══
    const kLuma = vec3f(0.2126, 0.7152, 0.0722);
    let lumaTL = saturate(dot(tl, kLuma));
    let lumaTC = saturate(dot(tc, kLuma));
    let lumaTR = saturate(dot(tr, kLuma));
    let lumaML = saturate(dot(ml, kLuma));
    let lumaMR = saturate(dot(mr, kLuma));
    let lumaBL = saturate(dot(bl, kLuma));
    let lumaBC = saturate(dot(bc, kLuma));
    let lumaBR = saturate(dot(br, kLuma));
    // ══════════════════════════════════════

    let gx = -lumaTL + lumaTR - 2.0*lumaML + 2.0*lumaMR - lumaBL + lumaBR;
    let gy =  lumaTL + 2.0*lumaTC + lumaTR - lumaBL - 2.0*lumaBC - lumaBR;
    return sqrt(gx*gx + gy*gy);
}

// Neon hue from angle — branchless HSV sector selection
fn neonColor(angle: f32, sat: f32) -> vec3<f32> {
    let h = fract(angle / (2.0 * PI));
    let h6 = h * 6.0;
    let c = sat;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    let i = u32(h6);
    // Branchless component selection via nested select()
    let r = select(select(select(0.0, x, i == 1u || i == 4u), c, i == 0u || i == 5u), 0.0, i == 2u || i == 3u);
    let g = select(select(select(0.0, x, i == 0u || i == 3u), c, i == 1u || i == 2u), 0.0, i == 4u || i == 5u);
    let b = select(select(0.0, x, i == 2u || i == 5u), c, i == 3u || i == 4u);
    return vec3f(r, g, b) + vec3f(1.0 - sat) * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv     = vec2<f32>(gid.xy) / dims;
    let coord  = vec2<i32>(gid.xy);
    let ps     = 1.0 / dims;
    let time   = u.config.x;

    // Audio — read from plasmaBuffer[0].xyz as vec3f(bass, mids, treble)
    let audio = plasmaBuffer[0].xyz;
    let bass    = audio.x;
    let mid     = audio.y;
    let treble  = audio.z;

    // Params
    let glowRadius     = mix(1.0, 6.0,  u.zoom_params.x);
    let dissolveAmt    = mix(0.0, 1.0,  u.zoom_params.y);
    let neonSat        = mix(0.6, 1.0,  u.zoom_params.z);
    let edgeSharpness  = mix(2.0, 20.0, u.zoom_params.w);

    // Source colour
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Edge magnitude
    var edge = sobel(uv, ps * glowRadius);
    edge = saturate(edge * edgeSharpness);
    edge = edge * (1.0 + bass * 2.0);

    // Neon edge colour cycles with position + time
    let angle     = atan2(uv.y - 0.5, uv.x - 0.5) + time * 0.5 + bass * PI;
    let neonCol   = neonColor(angle, neonSat);
    let neonGlow  = neonCol * edge * (1.0 + bass * 1.5);

    // Interior dissolve into colour noise
    let noiseUV   = uv * 4.0 + vec2<f32>(time * 0.3, time * 0.17);
    let n         = hash3(floor(noiseUV * 80.0)).x;
    let noiseCol  = neonColor(n * 2.0 * PI + time, neonSat * 0.7);
    let dissolve  = dissolveAmt * (mid * 0.5 + treble * 0.5) * (1.0 - edge);
    let interior  = mix(src.rgb, noiseCol, saturate(dissolve * 2.0));

    // Blend: edges overlay on interior
    var finalRGB = interior + neonGlow;
    finalRGB = clamp(finalRGB, vec3<f32>(0.0), vec3<f32>(1.5));

    // Semantic alpha: driven by edge + original alpha
    let alpha = saturate(src.a + edge * 0.8);

    let outColor = vec4<f32>(finalRGB, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(edge, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(edge, bass, mid, treble));
}
