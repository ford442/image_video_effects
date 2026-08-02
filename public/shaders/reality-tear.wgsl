// ═══════════════════════════════════════════════════════════════════
//  Reality Tear
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Swarm upgrade 2026-08-02: spring-damped tear center, click rifts,
//  angular FFT sector voices + per-sector treble burn flicker.
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i + vec2<f32>(0.0, 0.0));
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params with audio modulation
    let radiusBase = u.zoom_params.x * 0.5 * (1.0 + bass * 0.4);
    let jaggedness = u.zoom_params.y * (1.0 + mids * 0.5);
    let borderWidth = u.zoom_params.z * 0.05 * (1.0 + treble * 0.6);
    let staticAmt = u.zoom_params.w;

    // ── Spring-damper tear center (extraBuffer[133..136]) ─────────────
    // [0..4] reserved, [5..132] engine FFT — shader state lives at 133+.
    // [133..134] = eased position (uv space), [135..136] = velocity,
    // [137] = initialized flag.
    // Raw mouse stays the spring target; the tear drifts with menace
    // instead of snapping to the cursor.
    let rawMouse = u.zoom_config.yz;
    var tearPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var tearVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    // The explicit flag keeps the valid top-left pointer distinct from an
    // uninitialized buffer.
    let springInitialized = extraBuffer[137] > 0.5;
    if (!springInitialized) {
        tearPos = rawMouse;
        tearVel = vec2<f32>(0.0);
    }
    // Critically damped spring (fixed 60 Hz step, ~2.5 Hz settle).
    let springDt = 1.0 / 60.0;
    let springOmega = 2.0 * PI * 2.5;
    let springExp = exp(-springOmega * springDt);
    let springX = tearPos - rawMouse;
    let springTemp = (tearVel + springOmega * springX) * springDt;
    tearPos = rawMouse + (springX + springTemp) * springExp;
    tearVel = (tearVel - springOmega * springTemp) * springExp;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = tearPos.x;
        extraBuffer[134] = tearPos.y;
        extraBuffer[135] = tearVel.x;
        extraBuffer[136] = tearVel.y;
        extraBuffer[137] = 1.0;
    }

    let aspectRatio = resolution.x / resolution.y;
    let uv_c = vec2<f32>(uv.x * aspectRatio, uv.y);
    let mouse_c = vec2<f32>(tearPos.x * aspectRatio, tearPos.y);

    let dist = distance(uv_c, mouse_c);
    let angle = atan2(uv_c.y - mouse_c.y, uv_c.x - mouse_c.x);

    // ── Angular FFT voices ────────────────────────────────────────────
    // 8 angular sectors around the tear edge, each voiced by its own
    // FFT bin so different wedges of the rim writhe to different
    // frequencies.
    let sector = u32((angle + PI) / TAU * 8.0) % 8u;
    let sectorVoice = plasmaBuffer[sector + 1u].x * 0.3;
    // Treble bins 5-8 flicker the burn color per sector.
    let sectorTreble = plasmaBuffer[5u + (sector % 4u)].x;

    let noiseBase = valueNoise2D(vec2<f32>(angle * 3.0, time * 0.5)) * 0.5 +
                    valueNoise2D(vec2<f32>(angle * 10.0, time * 2.0)) * 0.5;
    let noiseVal = noiseBase * (1.0 + sectorVoice);

    let currentRadius = radiusBase + (noiseVal - 0.5) * jaggedness * radiusBase;

    // Base sample (full vec4 to preserve alpha)
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseRGB = baseSample.rgb;
    let baseA = baseSample.a;

    // Void region
    let staticNoise = hash21(uv * 100.0 + time);
    let distUV = clamp(uv + vec2<f32>(staticNoise * 0.05), vec2<f32>(0.0), vec2<f32>(1.0));
    let distortedSample = textureSampleLevel(readTexture, u_sampler, distUV, 0.0);
    let voidStatic = vec3<f32>(staticNoise * staticAmt);
    let inverted = vec3<f32>(1.0) - distortedSample.rgb;
    let voidColor = mix(inverted, voidStatic, 0.5);

    // Border region (burning edge with per-sector treble flicker)
    let borderFactor = clamp((dist - currentRadius) / max(borderWidth, 0.0001), 0.0, 1.0);
    let burnColor = vec3<f32>(1.0, 0.4, 0.1) * (2.0 + treble * 1.5) * (0.6 + sectorTreble * 0.9);
    let borderColor = mix(burnColor, baseRGB, borderFactor);

    let inVoid = dist < currentRadius;
    let inBorder = (dist < currentRadius + borderWidth) && !inVoid;

    var finalRGB = baseRGB;
    finalRGB = select(finalRGB, borderColor, inBorder);
    finalRGB = select(finalRGB, voidColor, inVoid);

    // ── Click rifts ───────────────────────────────────────────────────
    // Each live ripple opens a small secondary tear at its click point:
    // the same void/border/select pipeline evaluated against a radius
    // that grows then collapses over ~1.5s (max ~0.15). Composition
    // with the main tear is fully branchless.
    var riftVoidMask = 0.0;
    var riftBorderMask = 0.0;
    var riftEdgeProx = 0.0;
    var riftBorderColor = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age <= 0.0 || age > 1.5) { continue; }
        let life = age / 1.5;
        // Sine profile: grows to 0.15 at mid-life, collapses back to 0.
        let riftRadius = 0.15 * sin(life * PI);
        let rift_c = vec2<f32>(rp.x * aspectRatio, rp.y);
        let riftDist = distance(uv_c, rift_c);
        let riftInVoid = riftDist < riftRadius;
        let riftInBorder = (riftDist < riftRadius + borderWidth) && !riftInVoid;
        let riftBorderFactor = clamp((riftDist - riftRadius) / max(borderWidth, 0.0001), 0.0, 1.0);
        let riftBurn = mix(burnColor, baseRGB, riftBorderFactor);
        riftBorderColor = select(riftBorderColor, riftBurn, riftInBorder);
        riftVoidMask = max(riftVoidMask, select(0.0, 1.0, riftInVoid));
        riftBorderMask = max(riftBorderMask, select(0.0, 1.0, riftInBorder));
        riftEdgeProx = max(riftEdgeProx, 1.0 - smoothstep(0.0, borderWidth * 2.0, abs(riftDist - riftRadius)));
    }
    // Branchless composition: rift border under rift void, over main tear.
    finalRGB = select(finalRGB, riftBorderColor, riftBorderMask > 0.5);
    finalRGB = select(finalRGB, voidColor, riftVoidMask > 0.5);

    // Meaningful alpha: encodes whether pixel is torn, plus base alpha
    let edgeProx = max(1.0 - smoothstep(0.0, borderWidth * 2.0, abs(dist - currentRadius)), riftEdgeProx);
    let voidMask = max(select(0.0, 1.0, inVoid), riftVoidMask);
    let borderMask = max(select(0.0, 1.0, inBorder), riftBorderMask);
    let alpha = clamp(baseA * 0.4 + voidMask * 0.4 + borderMask * 0.6 + edgeProx * 0.3 + bass * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
