// ═══════════════════════════════════════════════════════════════════
//  alucinate-hdr
//  Category: advanced-hybrid
//  Features: ai-vj-conductor, music-reactive-glyphs, living-spectrogram, hdr-atmosphere, meta-visualizer
//  Complexity: Medium-High
//  Chunks From: alucinate.wgsl, alpha-hdr-bloom-chain.wgsl + new glyph/spectrogram system
//  Created: 2026-04-18
//  Updated: 2026-05-31
//  By: Grok (AI VJ conductor's baton + living spectrogram upgrade)
// ═══════════════════════════════════════════════════════════════════
//  When Alucinate (AI VJ) mode is active, this acts as a visual "conductor's
//  baton" — elegant, minimal music-reactive glyphs and spectrogram elements
//  that represent the current vibe stack. The psychedelic warp + HDR bloom
//  provides a rich atmospheric underlayer.
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Living Spectrogram / Conductor Glyphs (AI VJ meta layer) ═══
fn vibeGlyphs(uv: vec2<f32>, bass: f32, mids: f32, treble: f32, mouse: vec2<f32>, mouseDown: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    let centerY = 0.5;
    let conductor = smoothstep(0.25, 0.0, distance(uv, mouse)) * (0.6 + mouseDown * 0.8);

    // 6 elegant vertical bands (stylized frequency response)
    for (var i = 0; i < 6; i++) {
        let fi = f32(i);
        let bandX = 0.18 + fi * 0.13;
        let distX = abs(uv.x - bandX);
        let width = 0.018 + conductor * 0.012;

        // Heights driven by different plasma bands with musical feel
        let h = select(bass, mids, i > 1);
        let hh = select(h, treble, i > 3);
        let height = 0.08 + hh * (0.28 + fi * 0.015);

        let inBar = smoothstep(width, 0.0, distX) * smoothstep(height, 0.0, abs(uv.y - centerY));
        
        // Elegant gold-to-cyan gradient per band, stronger on conductor
        let bandCol = mix(vec3<f32>(0.95, 0.75, 0.35), vec3<f32>(0.3, 0.85, 0.95), fi / 5.5);
        col += bandCol * inBar * (0.7 + conductor * 1.2);
    }

    // Subtle horizontal "beat line" that pulses with bass
    let beatLine = smoothstep(0.012, 0.0, abs(uv.y - centerY)) * bass * 1.4;
    col += vec3<f32>(0.6, 0.9, 1.0) * beatLine;

    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.5;

    let mouse_uv = u.zoom_config.yz;
    let mouse_active = u.zoom_config.w > 0.0;
    let dist_to_mouse = distance(uv, mouse_uv);
    let mouse_effect = smoothstep(0.3, 0.0, dist_to_mouse) * f32(mouse_active);

    // ═══ Alucinate Warp ═══
    let warp_freq = mix(4.0, 10.0, mouse_effect);
    let warp_amp = mix(0.02, 0.1, mouse_effect);
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let radius = distance(uv, vec2<f32>(0.5));
    let warp_offset_x = sin(uv.y * warp_freq - time) * cos(radius * 10.0 + time) * warp_amp;
    let warp_offset_y = cos(uv.x * warp_freq + time) * sin(radius * 10.0 - time) * warp_amp;
    let warped_uv = uv + vec2<f32>(warp_offset_x, warp_offset_y);

    let shift_amount = mix(0.005, 0.02, mouse_effect) * sin(time * 2.0);
    let r = textureSampleLevel(readTexture, u_sampler, warped_uv + vec2<f32>(shift_amount, shift_amount), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, warped_uv - vec2<f32>(shift_amount, shift_amount), 0.0).b;
    var warpedColor = vec3<f32>(r, g, b);

    // ═══ HDR Bloom Chain ═══
    let bloomRadius = mix(0.01, 0.08, u.zoom_params.x);
    let bloomIntensity = u.zoom_params.y * 2.0;
    let bloomSamples = 16;

    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let a = f32(i) * 6.283185307 / f32(bloomSamples);
        let rad = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(a), sin(a)) * rad;
        let sampleUV = clamp(warped_uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
        let neighborExposure = max(0.0, neighborMax - 1.0);
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * neighborExposure * weight;
        totalWeight += neighborExposure * weight;
    }

    if (totalWeight > 0.001) {
        bloom /= totalWeight;
    }
    bloom *= bloomIntensity;

    // Mouse bloom boost
    let mouseGlow = smoothstep(0.2, 0.0, dist_to_mouse) * u.zoom_config.w * 2.0;
    bloom += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    // Ripple flash
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time * 2.0 - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            bloom += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    let hdrColor = warpedColor + bloom;
    let toneMapExp = mix(0.5, 2.0, u.zoom_params.z);
    let ldrColor = toneMapACES(hdrColor * toneMapExp);

    // === AI VJ CONDUCTOR LAYER (the high-signal meta upgrade) ===
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouseDown = u.zoom_config.w;

    let glyphs = vibeGlyphs(uv, bass, mids, treble, mouse_uv, mouseDown);

    // Blend the atmospheric HDR warp/bloom underneath elegant glyphs
    let atmosphere = ldrColor * (0.65 + mouse_effect * 0.25);
    let finalColor = atmosphere + glyphs * (0.85 + mouseDown * 0.4);

    // Meaningful alpha: higher when glyphs are prominent or during strong musical moments
    let glyphStrength = length(glyphs);
    let musicalEnergy = bass * 0.3 + mids * 0.4 + treble * 0.5;
    let alpha = clamp(0.55 + glyphStrength * 0.9 + musicalEnergy * 0.6 + mouseDown * 0.25, 0.0, 1.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalAlpha = mix(alpha * 0.75, alpha, depth);

    // Premultiplied for clean layering over the actual AI VJ output
    let a = clamp(finalAlpha, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalColor * a, a));

    // Store HDR for downstream use if needed
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, max(0.0, max(hdrColor.r, max(hdrColor.g, hdrColor.b)) - 1.0)));

    let depthOut = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
