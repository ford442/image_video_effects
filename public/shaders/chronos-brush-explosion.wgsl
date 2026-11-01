// ═══════════════════════════════════════════════════════════════════
//  chronos-brush-explosion
//  Category: advanced-hybrid
//  Features: time-freeze, chromatic-explosion, mouse-driven, temporal, upgraded-rgba
//  Complexity: High
//  Chunks From: chronos-brush.wgsl, mouse-chromatic-explosion.wgsl
//  Upgraded: 2026-11-01
//  Ideas: rim prism on the thawing edge; rim thaw after Decay
//  A packing: raw freeze RGBA (rgb frozen photo, a coverage). ACES on writeTexture only.
// ═══════════════════════════════════════════════════════════════════
//  A time-freeze painting brush where frozen regions explode with
//  chromatic dispersion. The frozen canvas becomes a prism: RGB
//  channels separate based on distance from the frozen edge,
//  creating spectral halos around painted strokes. Click ripples
//  launch chromatic shockwaves through the time-frozen canvas.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn frozenAt(sampleUV: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
  let maxTexel = max(vec2<i32>(i32(res.x) - 1, i32(res.y) - 1), vec2<i32>(0));
  let texel = clamp(vec2<i32>(i32(sampleUV.x * res.x), i32(sampleUV.y * res.y)), vec2<i32>(0), maxTexel);
  return textureLoad(dataTextureC, texel, 0);
}

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
    let toMouse = uv - mousePos;
    let dist = length(toMouse);
    let prismAngle = atan2(toMouse.y, toMouse.x);
    let deflection = wavelengthOffset * strength / max(dist, 0.02);
    let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
    return uv + perpendicular * deflection;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // ═══ Chronos Brush Parameters ═══
    let brushSize = max(0.01, u.zoom_params.x * 0.2);
    let decay = u.zoom_params.y;
    let prismStrength = mix(0.02, 0.12, u.zoom_params.z);
    let dispersion = mix(0.5, 3.0, u.zoom_params.w);

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var canvasState = textureLoad(dataTextureC, coord, 0);

    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    let brushSoftness = smoothstep(brushSize, brushSize * 0.5, dist) * select(0.0, 1.0, mouseDown) * step(dist, brushSize);
    canvasState = mix(canvasState, vec4<f32>(currentFrame.rgb, 1.0), brushSoftness);

    let heldAlpha = canvasState.a * mix(0.9, 1.0, decay);
    // ── Idea 2: the rim thaws first. Decay still holds the stroke.
    let rim = 1.0 - abs(clamp(heldAlpha, 0.0, 1.0) * 2.0 - 1.0);
    canvasState = vec4<f32>(canvasState.rgb, heldAlpha * mix(1.0, 0.90, rim));

    textureStore(dataTextureA, coord, canvasState);

    let mixFactor = smoothstep(0.0, 1.0, canvasState.a);
    let edgeMask = rim;

    // ── Idea 1: prism follows the thawing rim. The frozen interior keeps a smaller share.
    let prismAmt = prismStrength * mix(mixFactor * 0.22, 1.0, rim);
    let rUV = prismDisplace(uv, mouse, -1.0 * dispersion, prismAmt);
    let gUV = prismDisplace(uv, mouse, 0.0, prismAmt);
    let bUV = prismDisplace(uv, mouse, 1.0 * dispersion, prismAmt);

    // Ripple chromatic shockwaves through frozen canvas
    let rippleCount = min(u32(u.config.y), 50u);
    var rOffset = vec2<f32>(0.0);
    var gOffset = vec2<f32>(0.0);
    var bOffset = vec2<f32>(0.0);

    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.5) {
            let rPos = ripple.xy;
            let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
            let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
            let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
            let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
            let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
            rOffset += dir * rWave * mixFactor * 0.05;
            gOffset += dir * wave * mixFactor * 0.05;
            bOffset += dir * bWave * mixFactor * 0.05;
        }
    }

    let intensity = select(1.0, 2.5, mouseDown);

    let frozenR = frozenAt(clamp(rUV + rOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), res).r;
    let frozenG = frozenAt(clamp(gUV + gOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), res).g;
    let frozenB = frozenAt(clamp(bUV + bOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), res).b;

    let liveR = textureSampleLevel(readTexture, u_sampler, clamp(rUV + rOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let liveG = textureSampleLevel(readTexture, u_sampler, clamp(gUV + gOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let liveB = textureSampleLevel(readTexture, u_sampler, clamp(bUV + bOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var color = mix(vec3<f32>(liveR, liveG, liveB), vec3<f32>(frozenR, frozenG, frozenB), mixFactor);

    // Saturation boost on frozen edges
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(lum), color, 1.0 + edgeMask * 0.5);

    // Spectral glow near mouse on frozen regions
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0 * mixFactor;
    color = color + vec3<f32>(0.5, 0.3, 0.8) * glow;

    // Alpha = chromatic displacement magnitude scaled by freeze amount
    let totalDisp = length(rUV - gUV) + length(gUV - bUV);
    let alpha = clamp(totalDisp * 5.0 * mixFactor + mixFactor * 0.5, 0.0, 1.0);

    let display = acesToneMap(max(color, vec3<f32>(0.0)));
    textureStore(writeTexture, coord, vec4<f32>(display, alpha));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
