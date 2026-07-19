// ═══════════════════════════════════════════════════════════════════
//  Spectral Smear
//  Category: image
//  Features: mouse-driven, history, upgraded-rgba, audio-reactive, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Upgraded by: kimi-swarm 2026-07-19
//  upgraded-rgba
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
  zoom_params: vec4<f32>,  // x=TrailDecay, y=BrushSize, z=ShiftSpeed, w=Intensity
  ripples: array<vec4<f32>, 50>,
};

// ── Hashes & Noise (canonical forms) ─────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                         hash21(i + vec2<f32>(1.0, 0.0)), uu.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)),   hash21(i + vec2<f32>(1.0, 1.0)), uu.x),
        uu.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum  += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp  *= 0.5;
    }
    return sum;
}

// ── IQ cosine palette: richer spectral rainbow than the naive 3-cos ──
// t in cycles; d offsets chosen for vivid magenta->cyan->gold spread.
fn spectralPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params (mids speeds hue shift, treble lifts smear intensity)
    // Clamps follow the definition-JSON ranges so labels stay truthful.
    let trailDecay = clamp(u.zoom_params.x, 0.0, 1.0);
    let brushSize = clamp(u.zoom_params.y, 0.0, 0.5) * (1.0 + bass * 0.2);
    let shiftSpeed = clamp(u.zoom_params.z, 0.0, 2.0) * (1.0 + mids * 0.8);
    let intensity = clamp(u.zoom_params.w, 0.0, 1.0) * (1.0 + treble * 0.5);

    // Aspect-corrected positions
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    // Organic brush edge: fbm wobble breaks the perfect circle so the
    // smear looks painted, not stamped. Bass adds a live pulse to the edge.
    let edgeNoise = fbm(uvCorrected * 7.0 + vec2<f32>(time * 0.35, -time * 0.22), 3);
    let noisyDist = dist * (0.80 + 0.40 * edgeNoise) - bass * 0.015;

    let inBrush = smoothstep(brushSize, brushSize * 0.8, noisyDist);

    // Get current video frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Smear flow field: sample history at a slowly drifting offset so
    // trails crawl organically instead of fading in place. Offset is
    // tightly bounded (<= ~0.014 uv) and clamped to the frame.
    let flowP = uvCorrected * 3.0;
    let flow = vec2<f32>(
        fbm(flowP + vec2<f32>(time * 0.11, 0.0), 2),
        fbm(flowP + vec2<f32>(5.2, 1.3) - vec2<f32>(0.0, time * 0.08), 2)
    ) - vec2<f32>(0.5);
    let flowOffset = flow * (0.020 + mids * 0.008);
    let historyUv = clamp(uv - flowOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Get history (previous output), advected by the flow
    let history = textureSampleLevel(dataTextureC, u_sampler, historyUv, 0.0);

    // Spectral paint color: hue cycles with time (shiftSpeed), plus a
    // radial fringe so the smear splits into rainbow bands around the
    // cursor, plus a slow spatial drift from the edge noise field.
    let hue = fract(time * shiftSpeed);
    let fringe = clamp(dist * 1.6, 0.0, 1.5);
    let driftHue = (edgeNoise - 0.5) * 0.25;
    let shiftColor = clamp(spectralPalette(hue + fringe + driftHue), vec3<f32>(0.0), vec3<f32>(1.0));

    // Blend the live video luma into the paint so strokes feel lit by
    // the underlying frame rather than flat neon.
    let paint = mix(current.rgb, shiftColor, 0.65);

    let historyDecayed = history.rgb * (0.9 + 0.09 * trailDecay);

    var newHistory = historyDecayed;
    if (inBrush > 0.01) {
        newHistory = mix(newHistory, paint * 2.0, inBrush * intensity);
    }

    newHistory = clamp(newHistory, vec3<f32>(0.0), vec3<f32>(2.0));

    // Final composite: Video + History, with a soft knee on the
    // highlights so stacked strokes roll off instead of clipping.
    var finalColor = current.rgb + newHistory * 0.5;
    let over = max(finalColor - vec3<f32>(1.0), vec3<f32>(0.0));
    finalColor = min(finalColor, vec3<f32>(1.0)) + over / (vec3<f32>(1.0) + over * 0.5);
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(3.0));

    // Alpha: preserve input transparency while blending smear intensity
    let finalAlpha = mix(current.a, 1.0, inBrush * intensity * 0.7);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0, 0, 1));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));
}
