// ═══════════════════════════════════════════════════════════════════
//  Cyber Halftone Scanner
//  Category: image
//  Features: rotated screens, scanline, audio-reactive, plasma-tint,
//            mouse-driven, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: AM circular cells on 15/75/0/45 screens; scanline hard-dot
//  A packing: ACES display RGBA
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DotScale, y=ScanSpeed, z=Separation, w=Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
// (PHI removed — was unused)

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1: AM circular cells under the existing rotated screens (keep angles).
fn amCell(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
    let s = sin(angle);
    let c = cos(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let st = (rot * uv) * scale;
    let cell = fract(st) - 0.5;
    return length(cell) * 1.41421356;
}

// Small 1D value hash -> [0, 1), used to pick burst sweep directions.
fn hash11(p: f32) -> f32 {
    return fract(sin(p * 127.1) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass amplifies dot density and scan speed, treble boosts brightness
    let dotScale   = mix(50.0, 400.0, u.zoom_params.x) * (1.0 + bass * 0.2);
    let scanSpeed  = u.zoom_params.y * 2.0 * (1.0 + bass * 0.4);
    let sep        = u.zoom_params.z * 0.05;
    let brightness = u.zoom_params.w * 2.0 * (1.0 + treble * 0.2);

    // Scanline
    let scanY = fract(time * scanSpeed * 0.5);
    let scanDist = abs(uv.y - scanY);
    let scanIntensity = exp(-scanDist * scanDist * 90.0);

    // Cyber glitch skip — every couple of seconds the sweep can stutter-
    // jump to a new row, driven by a hash of the quantized clock and
    // gated by treble so the glitch follows the music's transients.
    let glitchSlot = floor(time * 0.5);
    let glitchGate = step(0.7, hash11(glitchSlot * 7.31)) * step(0.25, treble);
    let glitchY = fract(scanY + hash11(glitchSlot * 3.77) * 0.5) ;
    let scanYGlitch = mix(scanY, glitchY, glitchGate);
    let scanGlitchDist = abs(uv.y - scanYGlitch);
    let scanGlitch = exp(-scanGlitchDist * scanGlitchDist * 90.0) * glitchGate;

    // Modulate the sweep by the live FFT band under its vertical position.
    // scanY in [0,1) -> bins 1-8, always real audio data.
    let scanBand = plasmaBuffer[u32(scanY * 8.0) + 1u].x;
    let scanLive = scanIntensity * (0.6 + scanBand * 0.8);

    // Click scan bursts — each live ripple fires a secondary horizontal
    // scanline that sweeps away from its click row. Same exp(-d^2 * 90)
    // profile as the primary scanline, vertical velocity +-0.5 rows/s with
    // direction chosen by a hash of the click position, ~1.5s fade.
    var burstIntensity = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age <= 0.0 || age > 1.5) { continue; }
        let dir = select(-0.5, 0.5, hash11(rp.x * 57.0 + rp.y * 113.0) >= 0.5);
        let burstY = fract(rp.y + dir * age);
        // Wrap-aware row distance so the sweep slides across the screen
        // edge without a visible pop when fract() wraps around.
        let burstRaw = abs(uv.y - burstY);
        let burstDist = min(burstRaw, 1.0 - burstRaw);
        let fade = 1.0 - age / 1.5;
        burstIntensity = burstIntensity + exp(-burstDist * burstDist * 90.0) * fade * fade;
    }
    burstIntensity = min(burstIntensity, 1.0);

    // Pointer bloom — near the cursor the dots swell like a magnifying
    // lamp: +0.15 threshold boost with a smoothstep falloff of ~0.25 radius.
    let mouse = u.zoom_config.yz;
    let mouseDist = distance(uv, mouse);
    let mouseBloom = (1.0 - smoothstep(0.0, 0.25, mouseDist)) * 0.15;

    // Combined excitation feeding the halftone thresholds below.
    let boost = scanLive * 0.4 + scanGlitch * 0.3 + burstIntensity * 0.4 + mouseBloom;

    // Sample texture with chromatic separation
    let texR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( sep,  sep), 0.0).r;
    let texG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let texB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>( sep,  sep), 0.0).b;

    // Canonical CMYK screen angles — AM cells, not sin×sin.
    let patR = amCell(uv, 15.0  * PI / 180.0, dotScale);
    let patG = amCell(uv, 75.0  * PI / 180.0, dotScale);
    let patB = amCell(uv,  0.0,                dotScale);
    let patK = amCell(uv, 45.0  * PI / 180.0, dotScale * 1.05);

    let thrR = texR * brightness + boost;
    let thrG = texG * brightness + boost;
    let thrB = texB * brightness + boost;
    let thrK = dot(vec3<f32>(texR, texG, texB), vec3<f32>(0.299, 0.587, 0.114)) * brightness + boost;

    // Idea 2: scan hard-dot — under the scanline the AM threshold goes binary.
    let hardAmt = clamp(scanLive + scanGlitch + burstIntensity * 0.5, 0.0, 1.0);
    let softR = 1.0 - smoothstep(thrR - 0.07, thrR + 0.07, patR);
    let softG = 1.0 - smoothstep(thrG - 0.07, thrG + 0.07, patG);
    let softB = 1.0 - smoothstep(thrB - 0.07, thrB + 0.07, patB);
    let softK = 1.0 - smoothstep(thrK - 0.07, thrK + 0.07, patK);
    let r = mix(softR, step(patR, thrR), hardAmt);
    let g = mix(softG, step(patG, thrG), hardAmt);
    let b = mix(softB, step(patB, thrB), hardAmt);
    let k = mix(softK, step(patK, thrK), hardAmt);

    // Cyber-tinted
    let cyan    = vec3<f32>(0.0, 0.85, 1.0) * r;
    let magenta = vec3<f32>(1.0, 0.0, 0.7)  * g;
    let yellow  = vec3<f32>(1.0, 0.85, 0.0) * b;
    let halftone = (cyan + magenta + yellow) * (1.0 - k * 0.4);

    // Plasma palette tint along scan stripe.
    // GUARDED: wrap the palette index into the live FFT bins 1-8 — the old
    // `palIdx % 256u` read past the real bin count and returned zeros
    // (dead black tint). mids nudges the palette drift for extra life.
    let palIdx = (u32(clamp((scanY + time * 0.05 + mids * 0.1) * 255.0, 0.0, 255.0)) % 8u) + 1u;
    let scanTint = plasmaBuffer[palIdx].rgb;
    let tintAmt = scanLive * 0.4 + scanGlitch * 0.3 + burstIntensity * 0.4;
    let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
    let mapped = acesToneMap(halftone + scanTint * tintAmt);

    // Semantic alpha
    let coverage = (r + g + b) / 3.0;
    let alpha = clamp(coverage * 0.6 + scanIntensity * 0.3 + burstIntensity * 0.2 + srcA * 0.1, 0.0, 1.0);
    let outCol = vec4<f32>(mapped, alpha);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
