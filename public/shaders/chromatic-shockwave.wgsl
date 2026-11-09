// ═══════════════════════════════════════════════════════════════════
//  Chromatic Shockwave
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17, 2026-11-01
//  Ideas: N-wave on the ring stack; crest-gated aberration
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Speed, y=Frequency, z=Aberration, w=RingCount

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════════
const WAVELENGTH_RED:   f32 = 650.0;  // nm
const WAVELENGTH_GREEN: f32 = 550.0;  // nm
const WAVELENGTH_BLUE:  f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA (Beer-Lambert law)
//  alpha = exp(-thickness * absorption)
//  Red (650nm): lowest absorption, highest transmission
//  Blue (450nm): highest absorption, lowest transmission
// ═══════════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption  = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv    = vec2<f32>(global_id.xy) / resolution;
    let time  = u.config.x;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass modulates speed, mids modulate frequency
    let speed = u.zoom_params.x * 10.0 * (1.0 + bass * 0.3);
    let freq  = (10.0 + u.zoom_params.y * 50.0) * (1.0 + mids * 0.2);
    let aberr = u.zoom_params.z * 0.1;
    let ringLayers = 1u + u32(floor(clamp(u.zoom_params.w, 0.0, 1.0) * 7.0));

    // Current-frame coherent spring center; the raw normalized mouse remains
    // the target and the explicit flag keeps top-left a valid position.
    let rawMouse = u.zoom_config.yz;
    var waveCenter = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var centerVelocity = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let centerInitialized = extraBuffer[137u] >= 0.5;
    if (!centerInitialized) {
        waveCenter = rawMouse;
        centerVelocity = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), centerInitialized);
    let springOmega = 10.0;
    let springAccel = springOmega * springOmega * (rawMouse - waveCenter)
        - 2.0 * springOmega * centerVelocity;
    centerVelocity += springAccel * springDt;
    waveCenter = clamp(waveCenter + centerVelocity * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133u] = waveCenter.x;
        extraBuffer[134u] = waveCenter.y;
        extraBuffer[135u] = centerVelocity.x;
        extraBuffer[136u] = centerVelocity.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    let diffAspect = (uv - waveCenter) * aspectVec;
    let dist = length(diffAspect);
    let dirAspect = diffAspect / max(dist, 0.0001);
    let dirUV = dirAspect / aspectVec;

    // Ring Count now genuinely controls a stack of closely spaced wave
    // harmonics rather than being an unread fourth slider.
    var wave = 0.0;
    for (var layer = 0u; layer < 8u; layer += 1u) {
        if (layer < ringLayers) {
            let layerF = f32(layer);
            wave += sin(dist * freq * (1.0 + layerF * 0.08) - time * speed - layerF * 0.45);
        }
    }
    wave /= f32(ringLayers);

    // ── Idea 1: N-wave. The crest steepens; the rarefaction is unchanged.
    let nwave = wave + max(wave, 0.0) * abs(wave) * 0.55;

    let sectorAngle = atan2(diffAspect.y, diffAspect.x);
    let sector = u32(clamp(floor((sectorAngle + 3.14159265) * 8.0 / 6.2831853), 0.0, 7.0));
    let sectorVoice = plasmaBuffer[(sector % 8u) + 1u].x;
    let heldGain = select(1.0, 1.25, u.zoom_config.w > 0.5);
    let waveDisp = dirUV * nwave * heldGain * (1.0 + sectorVoice * 0.25 + treble * 0.1);

    // Discrete clicks launch their own normalized, aspect-corrected shells.
    let rippleCount = min(u32(u.config.y), 50u);
    var clickDisp = vec2<f32>(0.0);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let clickVec = (uv - ripple.xy) * aspectVec;
            let clickDist = length(clickVec);
            let clickDir = (clickVec / max(clickDist, 0.0001)) / aspectVec;
            let shell = sin(clickDist * freq - age * speed * 1.2)
                * exp(-age * 1.6) * smoothstep(0.55, 0.0, clickDist);
            clickDisp += clickDir * shell * 0.8;
        }
    }

    let displacement = waveDisp + clickDisp;
    // ── Idea 2: aberration of the continuous wave peaks on the crest.
    let crestGate = smoothstep(0.08, 0.7, abs(nwave));
    let waveAberr = aberr * mix(0.15, 1.0, crestGate);
    let chromaVec = waveDisp * waveAberr + clickDisp * aberr;
    let offsetR = chromaVec;
    let offsetB = -chromaVec;
    let offsetG = chromaVec * 0.3;

    // Clamp displaced UVs before sampling
    let uvR = clamp(uv + offsetR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + offsetG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + offsetB, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Wavelength-dependent Beer-Lambert alpha
    let waveThickness      = min(length(displacement), 2.0) * aberr * 10.0;
    let dispersionThickness = waveThickness + dist * 0.5;

    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);

    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);

    let mapped = acesToneMap(max(vec3<f32>(r, g, b), vec3<f32>(0.0)));
    let finalColor = vec4<f32>(mapped.r * alphaR, mapped.g * alphaG, mapped.b * alphaB, finalAlpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
