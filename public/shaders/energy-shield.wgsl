// ═══════════════════════════════════════════════════════════════════
//  Energy Shield — Batch 60
//  Category: interactive-mouse
//  Features: mouse-driven, hex-grid, impact-shockwaves, held-tighten,
//            audio-reactive, temporal-trail, fresnel-rim, oil-slick,
//            aces-tone-mapping, semantic-alpha
//  Complexity: Medium-High
//  Upgraded: 2026-08-23 Batch 60
//    - Cap click ripples at 50; exact textureLoad for C trail
//    - Held hex-grid tighten (scale up + edge sharpen)
//    - Real FFT: bass pulse, treble crackle on hex edges
//    - Oil-slick iridescent hex edges + stronger Fresnel rim
//    - ACES on writeTexture; semantic alpha from activation
//  A packing:
//    dataTextureA.r = trail activation (persistent shield energy)
//    dataTextureA.g = mouse intensity (debug / future)
//    dataTextureA.b = impact flare residual
//    dataTextureA.a = semantic activation mirror
//    dataTextureC is previous A (engine copy). Exact texel loads only.
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=hexScale, y=rippleSpeed, z=impactStrength, w=decay
  ripples: array<vec4<f32>, 50>,
};

fn hexDist(p: vec2<f32>) -> f32 {
    let p_abs = abs(p);
    return max(p_abs.x, p_abs.x * 0.5 + p_abs.y * 0.866025);
}

fn modulo(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(pixel) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let held = u.zoom_config.w > 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params (source contract ranges preserved)
    // Held tighten: denser hex grid + sharper edges under press
    let hexScale = (5.0 + u.zoom_params.x * 45.0) * select(1.0, 1.35, held);
    let rippleSpeed = u.zoom_params.y * 5.0;
    let impactStrength = u.zoom_params.z;
    let decay = u.zoom_params.w;

    // Hex Grid UVs — skewed grid
    let r = vec2<f32>(1.0, 1.73);
    let h = r * 0.5;

    var scaledUV = uv * hexScale;
    scaledUV.x = scaledUV.x * aspect;

    let a = modulo(scaledUV, r) - h;
    let b = modulo(scaledUV - h, r) - h;

    let gv = select(b, a, dot(a, a) < dot(b, b));

    let hexCenter = scaledUV - gv;
    var hexCenterUV = hexCenter / hexScale;
    hexCenterUV.x = hexCenterUV.x / aspect;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let distVec = (hexCenterUV - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Bass-pulsed standing wave on the shield surface
    let wave = sin(dist * 20.0 - time * rippleSpeed + bass * 2.5);
    let mouseIntensity = smoothstep(0.4, 0.0, dist) * (1.0 + bass * 0.35);

    // Discrete impact shockwaves — capped at 50 ripples
    let rippleCount = min(u32(u.config.y), 50u);
    var impactFlare = 0.0;
    var impactHue = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rd = length((hexCenterUV - rp.xy) * vec2<f32>(aspect, 1.0));
        let waveR = age * (0.25 + rippleSpeed * 0.08);
        let band = exp(-pow((rd - waveR) * 22.0, 2.0));
        let crackle = 0.6 + 0.4 * sin(dot(hexCenter, vec2<f32>(12.9, 7.3)) + time * 8.0);
        let fade = (1.0 - age / 3.0);
        impactFlare = impactFlare + band * crackle * fade * (0.6 + impactStrength);
        impactHue = impactHue + band * fade;
    }
    impactFlare = clamp(impactFlare, 0.0, 2.0);

    let activeHex = mouseIntensity + wave * 0.2 * impactStrength + impactFlare;

    // Hex Edges — held sharpens the rim threshold
    let hexD = hexDist(gv);
    let edgeLo = select(0.48, 0.485, held);
    let edgeHi = select(0.50, 0.498, held);
    let edge = smoothstep(edgeLo, edgeHi, hexD);
    let glowBase = select(0.40, 0.44, held);
    let glow = smoothstep(glowBase, edgeHi, hexD) * activeHex;

    // Treble crackle along hex edges
    let edgeCrackle = step(0.92 - treble * 0.08, hash21(hexCenter + time * 17.0))
                    * treble * edge * (0.5 + activeHex);

    // Distort UV based on active hex
    let distortAmt = activeHex * 0.05 * impactStrength;
    let distortedUV = uv + (gv / hexScale) * distortAmt;

    let color_sample = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
    let color = color_sample.rgb;

    // Oil-slick iridescent hex edges (not flat cyan)
    let filmPhase = hexD * 6.0 + dist * 8.0 - time * 0.7 + mids * 1.5;
    let oilSlick = 0.5 + 0.5 * cos(filmPhase + vec3<f32>(0.0, 2.094, 4.189));
    let gridColor = mix(vec3<f32>(0.05, 0.55, 0.95), oilSlick, 0.55 + treble * 0.25);

    var finalColor = mix(color, gridColor, glow * 0.85);
    finalColor = finalColor + gridColor * mouseIntensity * 0.2;
    finalColor = finalColor + oilSlick * edgeCrackle * 0.55;

    // Impact shockwave — hot white core fringing to iridescent edge
    let impactColor = mix(gridColor, vec3<f32>(0.95, 1.0, 1.0), clamp(impactHue, 0.0, 1.0));
    finalColor = finalColor + impactColor * impactFlare;

    // Stronger Fresnel sphere-shield rim
    let centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let fres = pow(clamp(length(centered) * 1.55, 0.0, 1.0), 2.2);
    let fresAmt = select(0.28, 0.38, held) * (0.6 + impactStrength + bass * 0.3);
    finalColor = finalColor + mix(gridColor, oilSlick, 0.4) * fres * fresAmt;

    // Exact trail history from previous A (.r = activation)
    let prev = textureLoad(dataTextureC, pixel, 0);
    let heldBoost = select(0.0, mouseIntensity * 0.35, held);
    let activation = mouseIntensity + heldBoost;
    let newTrail = max(prev.r * decay, activation);

    finalColor = finalColor + mix(vec3<f32>(0.0, 0.45, 1.0), oilSlick, 0.35) * newTrail * 0.5;
    // Bass pulse thickens the whole shield glow briefly
    finalColor = finalColor + gridColor * bass * 0.12 * (0.4 + fres);

    finalColor = acesToneMap(finalColor * (1.0 + mids * 0.12));

    // Semantic alpha from shield activation (trail + glow + fresnel + impact)
    let semantic_alpha = clamp(0.35 + newTrail * 0.45 + glow * 0.35 + fres * 0.2 + impactFlare * 0.15, 0.25, 1.0);

    textureStore(dataTextureA, pixel, vec4<f32>(newTrail, mouseIntensity, impactFlare * 0.5, semantic_alpha));
    textureStore(writeTexture, pixel, vec4<f32>(finalColor, semantic_alpha));

    let depth_in = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
