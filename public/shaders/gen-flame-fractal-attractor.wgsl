// ═══════════════════════════════════════════════════════════════════
//  Flame Fractal Attractor
//  Category: generative
//  Features: fractal, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-15
//  Ideas: orbit-capture contour filaments (smooth iteration count at which the orbit falls inside a trap radius, drawn as thin contour lines); rising-ember advection (history read from the pixel below with a curl wobble so filaments leave upward ember trails); kept: abs-fold crease specular; even/odd iteration ember bands; log-density flame display with vibrancy (Draves, native); blackbody cooling of rising embers + ember persistence (§12.2F)
//  A packing: log-density display-linear HDR RGBA, <= 8 (fed back through C as colour; ACES on writeTexture only)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Attractor Strength, y=Orbit Speed, z=Curl, w=Ember Bloom

const COOL_GAIN: f32 = 2.5;   // Idea 4: cooling ramp strength (per frame)
const EMBER_KEEP: f32 = 0.92; // Idea 4: fraction of the cooled ember history that survives a frame

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.0, 0.16, 0.42)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let strength = mix(0.72, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
    let orbitSpeed = mix(0.1, 1.8, clamp(u.zoom_params.y, 0.0, 1.0));
    let curl = mix(0.15, 1.25, clamp(u.zoom_params.z, 0.0, 1.0));
    let emberBloom = mix(0.25, 2.8, clamp(u.zoom_params.w, 0.0, 1.0));
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseDelta = p - mouse;
    p = rot(-time * orbitSpeed * 0.08) * p;
    p += normalize(mouseDelta + vec2<f32>(0.0001)) * sin(length(mouseDelta) * 10.0 - time * 3.0) * held * 0.09;

    var z = p * (1.15 + strength * 0.35);
    var orbitDensity = 0.0;
    var lineTrap = 0.0;
    var hueMoment = 0.0;
    var evenDen = 0.0;
    var oddDen = 0.0;
    var creaseAcc = 0.0;
    var capture = 0.0;
    var captured = false;
    for (var i = 0; i < 36; i++) {
        let fi = f32(i);
        let r2 = max(dot(z, z), 0.0005);
        let swirlAngle = curl * r2 + time * orbitSpeed * 0.025 + audio.y * 0.18;
        let swirled = rot(swirlAngle) * z;
        let folded = abs(swirled) - vec2<f32>(0.42 + audio.x * 0.08, 0.26);
        let crease = exp(-min(abs(folded.x), abs(folded.y)) * (22.0 + audio.z * 10.0));
        creaseAcc += crease / (1.0 + fi * 0.09);
        z = rot(0.72 + sin(time * 0.11) * 0.08) * folded * (0.84 + strength * 0.045) +
            vec2<f32>(-0.16, 0.09 + sin(fi * 1.7) * 0.025);
        let centerTrap = exp(-length(z) * (4.5 + audio.x * 2.0));
        // Idea 1 - orbit-capture time: first iteration the orbit falls inside the trap radius (smoothed)
        if (!captured && length(z) < 0.9) {
            capture = fi + clamp((0.9 - length(z)) / 0.4, 0.0, 1.0);
            captured = true;
        }
        let filament = exp(-abs(z.x * z.y) * (24.0 + audio.z * 16.0)) / (1.0 + r2 * 1.8);
        let evenW = select(0.0, 1.0, (u32(i) & 1u) == 0u);
        evenDen += centerTrap * evenW / (1.0 + fi * 0.08);
        oddDen += centerTrap * (1.0 - evenW) / (1.0 + fi * 0.08);
        orbitDensity += centerTrap / (1.0 + fi * 0.08);
        lineTrap += filament * 0.035;
        hueMoment += (centerTrap + filament * 0.03) * fi;
    }

    var clickEmber = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickEmber += exp(-abs(distance(p, center) - age * 0.24) * 70.0) * exp(-age * 1.45);
        }
    }

    let density = min(orbitDensity * 0.38 + lineTrap, 5.0);
    let hue = hueMoment / max(orbitDensity + lineTrap, 0.001) * 0.012 + time * 0.02 + audio.y * 0.13;
    let flameColor = mix(vec3<f32>(1.25, 0.12, 0.015), palette(hue), 0.35 + audio.z * 0.2);
    let innerCurl = vec3<f32>(1.35, 0.22, 0.04);
    let outerCurl = palette(hue + 0.18);
    var hdrColor = vec3<f32>(0.008, 0.003, 0.012) + flameColor * density * (0.55 + emberBloom + audio.x * 0.65);
    hdrColor += innerCurl * evenDen * emberBloom * 0.55;
    hdrColor += outerCurl * oddDen * emberBloom * 0.45;
    hdrColor += vec3<f32>(1.2, 0.42 + audio.y * 0.25, 0.06 + audio.z * 0.25) * lineTrap * emberBloom;
    hdrColor += vec3<f32>(1.45, 0.95, 0.35) * creaseAcc * (0.28 + emberBloom * 0.12);
    hdrColor += vec3<f32>(1.0, 0.24, 0.65 + audio.z * 0.5) * clickEmber * 0.42;
    // Idea 1 - contour filaments at integer-ish capture counts
    let contour = select(0.0, smoothstep(0.1, 0.0, abs(fract(capture * 0.5) - 0.5)), captured);
    hdrColor += vec3<f32>(1.5, 0.55, 0.12) * contour * emberBloom * 0.16 * (1.0 + audio.z * 0.4);
    // ── Idea 3: log-density flame display with vibrancy (native — Draves flame, 2026-11-15) ──
    // The orbit map is contractive, so after ~15 iterations every pixel sits on the same attractor and the
    // late iterations add a pixel-independent plateau: HEAD summed to ≈(12,4,1.5) everywhere and ACES made
    // the frame white. A flame fractal is shown as a LOG of the density with a vibrancy mix between
    // per-channel log (cores whiten) and a luminance-preserving log (cores keep their hue).
    let flameK = 4.0;
    let flameNorm = 1.0 / log(1.0 + flameK * 30.0);
    let dens = clamp(hdrColor, vec3<f32>(0.0), vec3<f32>(24.0));
    let densLum = dot(dens, vec3<f32>(0.2126, 0.7152, 0.0722));
    let logLum = log(1.0 + flameK * densLum) * flameNorm;
    let logChan = log(vec3<f32>(1.0) + flameK * dens) * flameNorm;
    hdrColor = mix(logChan, dens * (logLum / max(densLum, 1.0e-4)), 0.75);
    // Idea 2 - rising embers: read C from the pixel below with a curl wobble (exact load, clamped)
    // Rise distance is resolution-relative: 2 px/frame at 192 px (HEAD's value, unchanged there), 6 at 576, 11 at 1080 —
    // HEAD's fixed 2 px was ~0.2 % of the frame height per frame at 1080p, i.e. no visible rise.
    let riseK = max(res.y / 96.0, 2.0);
    let wobble = i32(round(sin(f32(coord.y) * 0.045 + time * 1.3) * 0.75 * riseK));
    let riseCoord = clamp(coord + vec2<i32>(wobble, i32(round(riseK))), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, riseCoord, 0);
    // ── Idea 4: blackbody cooling of rising embers (§12.2F blackbody) ──
    // An ember loses blue first, then green, as it cools: the history is redshifted a little every frame.
    let emberCool = exp(-vec3<f32>(0.004, 0.022, 0.07) * COOL_GAIN);
    let cooledHist = history.rgb * emberCool;
    hdrColor = mix(hdrColor, cooledHist, (0.055 + audio.x * 0.07) * (0.8 + 0.25 * emberBloom));
    // A hot ember outlives the frame it was born in. The 5–12 % mix above leaves a trail only 2–3 px long, so the
    // cooling would be invisible; this lets a bright filament keep rising, reddening and dimming for ~10 frames.
    hdrColor = clamp(max(hdrColor, cooledHist * EMBER_KEEP), vec3<f32>(0.0), vec3<f32>(8.0));
    let mapped = acesToneMap(hdrColor);
    let alpha = clamp(density * 0.42 + lineTrap * 0.25 + creaseAcc * 0.12 + contour * 0.06 + clickEmber * 0.1, 0.02, 0.98);
    let depth = clamp(density * 0.22 + orbitDensity * 0.035 + creaseAcc * 0.08, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
