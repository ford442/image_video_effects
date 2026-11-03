// ═══════════════════════════════════════════════════════════════════════════════
//  gen-cyber-terminal.wgsl - Retro Terminal & Digital Rain
//  
//  Category: generative
//  Features: audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-27, 2026-11-01 (was 2026-09-21, Batch 42)
//  Ideas: 3x5 segment glyph font; white-hot flickering leader at each drop head; column gaps; bottom restart flash; barrel scanlines; corner misconvergence
//  A packing: raw HDR display RGBA history (C read back as the same)
//  Techniques:
//    - Falling digital rain (Matrix-style)
//    - Audio-reactive data stream speed and brightness
//    - CRT emulation (scanlines, phosphor decay, slight curvature)
//    - Temporal accumulation trails via dataTextureC
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// Idea 1 — segment glyph font: a random subset of nine strokes on a 3x5 skeleton
// (7-segment frame + centre stem + one diagonal) so each cell reads as a character.
fn segmentGlyph(cellUV: vec2<f32>, bits: f32, halfWidth: f32) -> f32 {
    let mask = u32(bits * 511.0) | (1u << (u32(bits * 97.0) % 9u));
    let l = -0.26; let r = 0.26; let t = -0.38; let m = 0.0; let b = 0.38;
    var d = 10.0;
    if ((mask & 1u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(l, t), vec2<f32>(r, t))); }
    if ((mask & 2u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(l, m), vec2<f32>(r, m))); }
    if ((mask & 4u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(l, b), vec2<f32>(r, b))); }
    if ((mask & 8u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(l, t), vec2<f32>(l, m))); }
    if ((mask & 16u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(l, m), vec2<f32>(l, b))); }
    if ((mask & 32u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(r, t), vec2<f32>(r, m))); }
    if ((mask & 64u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(r, m), vec2<f32>(r, b))); }
    if ((mask & 128u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(0.0, t), vec2<f32>(0.0, b))); }
    if ((mask & 256u) != 0u) { d = min(d, sdSegment(cellUV, vec2<f32>(r, t), vec2<f32>(l, b))); }
    return 1.0 - smoothstep(halfWidth, halfWidth + 0.035, d);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }
    
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let audio = plasmaBuffer[0].xyz;
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let gridDensity = clamp(u.zoom_params.x, 0.1, 5.0);
    let glyphSharpness = clamp(u.zoom_params.y, 0.0, 1.0);
    let characterBrightness = clamp(u.zoom_params.z, 0.5, 2.0);
    let scanlineBloom = clamp(u.zoom_params.w, 0.0, 2.0);
    
    // CRT Curvature
    var uv = uvFull * 2.0 - 1.0;
    uv = uv * (1.0 + dot(uv, uv) * 0.1);
    uv = uv * 0.5 + 0.5;
    
    var col = vec3<f32>(0.0);
    
    if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
        // Digital Rain
        let cols = 32.0 + gridDensity * 38.0;
        let rows = cols * resolution.y / max(resolution.x, 1.0) * 0.9;
        let gridUV = vec2<f32>(floor(uv.x * cols), floor(uv.y * rows));
        let cellUV = fract(uv * vec2<f32>(cols, rows)) - 0.5;
        
        let speed = 2.0 + hash12(vec2<f32>(gridUV.x, 0.0)) * 5.0 + bass * 5.0;
        let columnSeed = hash12(vec2<f32>(gridUV.x, 1.0));
        let dropPos = fract(time * speed + columnSeed);
        // Head at dropPos, tail trailing up the column (HEAD had the bright end trailing behind the motion).
        let trail = fract(dropPos - uv.y);
        let wrapGen = floor(time * speed + columnSeed);
        
        // Idea 2 — white-hot leader: the cell at the drop head burns near-white and re-rolls its glyph every frame.
        let leader = 1.0 - smoothstep(0.6 / rows, 1.6 / rows, trail);
        let dataBit = hash12(gridUV + wrapGen * 0.37 + floor(time * (7.0 + treble * 8.0)));
        let leaderBit = hash12(gridUV + floor(time * 30.0) * 1.37 + 17.0);
        let bit = mix(dataBit, leaderBit, step(0.5, leader));
        let strokeWidth = mix(0.22, 0.055, glyphSharpness);
        // ── Idea 2: corner misconvergence ────────────────────────────
        // The CRT bulge already warps uv. Corners shift the red and blue
        // glyph taps apart; where the taps still agree, the fringe is zero.
        let bulge = dot(uvFull * 2.0 - 1.0, uvFull * 2.0 - 1.0);
        let shift = bulge * 0.045;
        let glyph = segmentGlyph(cellUV, bit, strokeWidth * 0.5);
        let glyphR = segmentGlyph(cellUV + vec2<f32>(shift, 0.0), bit, strokeWidth * 0.5);
        let glyphB = segmentGlyph(cellUV - vec2<f32>(shift, 0.0), bit, strokeWidth * 0.5);
        // Column gaps: seeded blanks so the trail is glyph blocks, not a solid streak.
        let gap = step(0.64, hash12(vec2<f32>(gridUV.x, floor(trail * 7.0) + wrapGen)));
        let intensity = (1.0 - trail) * step(trail, 0.34) * glyph * (1.0 - gap);
        let phosphor = mix(vec3<f32>(0.03, 0.72, 0.16), vec3<f32>(0.12, 1.0, 0.68), mids);
        col = phosphor * intensity * characterBrightness * (1.0 + bass * 2.0 + treble * bit);
        let fringe = smoothstep(0.2, 0.9, bulge);
        let body = characterBrightness * (1.0 + bass * 2.0 + treble * bit) * (1.0 - gap) * step(trail, 0.34);
        col += vec3<f32>(0.5, 0.04, 0.06) * max(glyphR - glyph, 0.0) * body * fringe;
        col += vec3<f32>(0.04, 0.06, 0.45) * max(glyphB - glyph, 0.0) * body * fringe;
        col += vec3<f32>(0.78, 1.0, 0.86) * glyph * leader * (1.0 - gap) * characterBrightness * 1.6;
        // Bottom restart: one cold-green frame where the column wraps, then the new seed.
        let wrapFlash = smoothstep(0.9, 1.0, uv.y) * (1.0 - smoothstep(0.0, 0.04, dropPos));
        col += vec3<f32>(0.16, 0.48, 0.28) * wrapFlash * glyph * characterBrightness * 1.5;
        
        // ── Idea 1: barrel scanlines ────────────────────────────────────
        // The mask follows the curved glass uv, not the flat frame.
        // Scanline Bloom still scales the bloom below.
        let scan = 0.78 + 0.22 * sin(uv.y * resolution.y * 3.14159);
        col *= scan;
        col += phosphor * pow(max(scan, 0.0), 10.0) * scanlineBloom * intensity * 0.18;
    }
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = mix(inputColor.rgb, col, 0.8);
    
    // Temporal Phosphor Trails
    let prevColor = textureLoad(dataTextureC, vec2<i32>(coord), 0).rgb;
    let hdrColor = clamp(mix(finalRGB, prevColor, 0.62 + scanlineBloom * 0.07), vec3<f32>(0.0), vec3<f32>(5.0));
    let mappedColor = acesToneMap(hdrColor * 1.12);
    let phosphorEnergy = dot(mappedColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(phosphorEnergy * 1.35 + length(col) * 0.18, 0.03, 0.98);
    
    textureStore(writeTexture, coord, vec4<f32>(mappedColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(phosphorEnergy, 0.0, 1.0), 0.0, 0.0, 0.0));
}
