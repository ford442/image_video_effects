// ────────────────────────────────────────────────────────────────────────────────
//  Cyber Rain Interactive — Layered Glyph Downpour
//  Category: retro-glitch
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-column-fft, dot-matrix-glyphs, depth-parallax-layers,
//            chromatic-aberration, temporal-trails, upgraded-rgba,
//            semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 56 — Turbulent Vortex)
// ────────────────────────────────────────────────────────────────────────────────
//  The original rain was a single flat sheet: one head per column, brightness
//  drawn as an untextured block, opaque alpha, and a glitch term that only ever
//  blanked pixels. Two structures replace that:
//
//    1. Depth-parallax layers — three rain sheets are composited, each with its
//       own column pitch, fall rate and brightness. The scene depth at the pixel
//       decides how much of each layer survives, so near glyphs sweep past fast
//       and far ones drift, and the rain sits INSIDE the image instead of on top
//       of it. Each layer also carries two drops per column at different phases.
//
//    2. Dot-matrix glyphs — columns render real characters from a packed 4x6
//       glyph ROM that re-rolls as the drop falls, instead of solid brightness
//       blocks. Glyph choice is hashed per (column, character step, layer).
//
//  Audio: every column owns one of the 8 FFT bins (plasmaBuffer[1..8]) which
//  sets its fall rate and head brightness, so the downpour reads as a spectrum.
//  Interaction: the pointer pushes drops aside and boosts nearby glyphs (held =
//  stronger), and clicks emit bounded EMP rings that scramble and flare the rain.
// ────────────────────────────────────────────────────────────────────────────────

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,  // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Speed, y=Density, z=Glitch, w=TrailLength
  ripples:     array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Glyph ROM: 4x6 dot matrix, bit = row * 4 + col (col 0 left, row 0 top) ───
var<private> GLYPHS: array<u32, 8> = array<u32, 8>(
    0x69F996u,  // boxed
    0x9F6F69u,  // angular
    0x6F9F96u,  // stacked
    0xF69F6Fu,  // barred
    0x996FF9u,  // split
    0x9F99F6u,  // hooked
    0x6996F9u,  // hollow
    0xF9F669u   // dense
);

fn glyphInk(index: u32, cellUV: vec2<f32>, softness: f32) -> f32 {
    let bits = GLYPHS[index & 7u];
    let g = cellUV * vec2<f32>(4.0, 6.0);
    let cell = clamp(floor(g), vec2<f32>(0.0), vec2<f32>(3.0, 5.0));
    let bit = u32(cell.y) * 4u + u32(cell.x);
    let on = f32((bits >> bit) & 1u);
    let d = length(fract(g) - vec2<f32>(0.5));
    return on * smoothstep(0.55, 0.55 - softness, d);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// One rain sheet. Returns (ink, headProximity) for the pixel.
fn rainLayer(
    uv: vec2<f32>,
    aspect: f32,
    time: f32,
    cols: f32,
    speed: f32,
    trailLen: f32,
    layerSeed: f32,
    scramble: f32
) -> vec2<f32> {
    let rows = max(cols / aspect, 1.0);
    let cellX = floor(uv.x * cols);
    let colRand = hash12(vec2<f32>(cellX, layerSeed));

    // Column owns one FFT bin: faster and brighter when its band is loud.
    let bandIdx = u32(colRand * 8.0) % 8u;
    let band = plasmaBuffer[bandIdx + 1u].x;
    let fallSpeed = speed * (0.5 + colRand * 1.5) * (1.0 + band * 0.6);

    var ink = 0.0;
    var headAmt = 0.0;

    // Two drops per column, half a cycle apart.
    for (var k = 0u; k < 2u; k = k + 1u) {
        let phase = colRand * 10.0 + f32(k) * 0.5 + layerSeed * 3.7;
        let headY = fract(time * fallSpeed + phase);
        var d = headY - uv.y;
        if (d < 0.0) { d += 1.0; }               // wrap: drops fall downward

        let trail = smoothstep(1.0 / trailLen, 0.0, d);
        if (trail <= 0.001) { continue; }

        // Glyph cell along the column, re-rolled as the drop advances.
        let cellY = floor(uv.y * rows);
        let charStep = floor(time * fallSpeed * 12.0 + colRand * 32.0);
        let gIdx = u32(hash12(vec2<f32>(cellX + layerSeed * 91.0, cellY + charStep)) * 8.0
                     + scramble * 5.0);
        let localUV = vec2<f32>(fract(uv.x * cols), fract(uv.y * rows));
        let ig = glyphInk(gIdx, localUV, 0.28);

        ink = max(ink, ig * trail);
        headAmt = max(headAmt, smoothstep(0.03, 0.0, d) * ig);
    }

    return vec2<f32>(ink, headAmt);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(gid.xy);
    let dims = vec2<f32>(dimsI);
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let speed = u.zoom_params.x * 2.0 + 0.2;
    let density = clamp(u.zoom_params.y, 0.0, 1.0);
    let glitch = clamp(u.zoom_params.z, 0.0, 1.0);
    let trailLen = u.zoom_params.w * 5.0 + 1.0;

    let mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);

    // ── Bounded click EMP rings ──────────────────────────────────────────────
    var emp = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.0) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let front = rDist - age * 0.7;
            emp += exp(-front * front * 140.0) * exp(-age * 1.8);
        }
    }
    emp = min(emp, 1.5);

    // ── Pointer field: drops bend around the cursor ──────────────────────────
    let mouseDist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let mouseField = smoothstep(0.24, 0.0, mouseDist) * (0.5 + held * 0.9);
    let pushDir = normalize((uv - mouse) * vec2<f32>(aspect, 1.0) + vec2<f32>(1e-6));
    let rainUV = uv + pushDir * mouseField * 0.05 / vec2<f32>(aspect, 1.0);

    // ── Structure 1: three parallax sheets, selected by scene depth ──────────
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let baseCols = 40.0 + density * 110.0;
    let scramble = glitch * (0.4 + emp) + mouseField * 0.5;

    let near = rainLayer(rainUV, aspect, time, baseCols * 0.6, speed * 1.6, trailLen * 0.8, 1.0, scramble);
    let midL = rainLayer(rainUV, aspect, time, baseCols, speed, trailLen, 2.0, scramble);
    let far  = rainLayer(rainUV, aspect, time, baseCols * 1.7, speed * 0.55, trailLen * 1.4, 3.0, scramble);

    // Depth 0 = near plane: near sheet dominates foreground, far sheet the back.
    let wNear = smoothstep(0.55, 0.0, depth);
    let wFar = smoothstep(0.45, 1.0, depth);
    let wMid = 1.0 - max(wNear, wFar) * 0.6;

    let ink = near.x * wNear * 1.15 + midL.x * wMid + far.x * wFar * 0.7;
    let head = near.y * wNear + midL.y * wMid + far.y * wFar * 0.6;
    var brightness = clamp(ink + head * 1.6, 0.0, 2.4);

    // ── Underlying image ─────────────────────────────────────────────────────
    // Chromatic split on the drop heads only — the phosphor bleeds sideways.
    let ca = (0.0012 + treble * 0.004) * (head + emp);
    let iR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(ca, 0.0), 0.0).r;
    let iG = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let iB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(ca, 0.0), 0.0).b;
    let imgColor = vec3<f32>(iR, iG.g, iB);
    let lumaImg = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Bright parts of the image are "wet": glyphs cling to them and pale out.
    let wetness = smoothstep(0.35, 0.85, lumaImg);
    brightness *= 0.55 + wetness * 0.9;

    // Dropout glitch, now analytic and column-coherent rather than per-pixel.
    let dropout = step(1.0 - glitch * 0.12,
                       hash12(vec2<f32>(floor(uv.x * baseCols), floor(time * 9.0))));
    brightness *= 1.0 - dropout;

    // ── Colour ───────────────────────────────────────────────────────────────
    let coolGreen = vec3<f32>(0.05, 1.0, 0.28);
    let paleGreen = vec3<f32>(0.78, 1.0, 0.82);
    var rainColor = mix(coolGreen, paleGreen, wetness) * brightness;
    rainColor += vec3<f32>(0.85, 1.0, 0.95) * head * (1.2 + bass * 0.8);
    rainColor += vec3<f32>(0.35, 0.75, 1.0) * mouseField * (0.8 + mids * 0.6);
    rainColor += vec3<f32>(0.6, 1.0, 0.85) * emp * 1.1;

    var color = mix(imgColor * (0.12 + wetness * 0.28), rainColor, clamp(brightness, 0.0, 1.0));

    // ── Temporal trails ──────────────────────────────────────────────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    color = max(color, prev.rgb * (0.80 + trailLen * 0.02));

    color = acesFilm(color);

    // ── Semantic alpha (was hardcoded 1.0) ───────────────────────────────────
    // Glyphs and heads are the content; the dimmed plate behind them stays
    // mostly transparent so the rain composites over other layers.
    let presence = clamp(brightness * 0.8 + head + emp * 0.6, 0.0, 1.0);
    let alpha = clamp(mix(iG.a * 0.25 + 0.1, 1.0, presence), 0.0, 1.0);

    let outColor = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: near glyphs pull the surface toward the viewer.
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(depth * (1.0 - near.y * 0.12), 0.0, 0.0, 0.0));
}
