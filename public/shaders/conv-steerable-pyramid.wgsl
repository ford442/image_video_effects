// ═══════════════════════════════════════════════════════════════════
//  Steerable Pyramid
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, depth-aware
//  Convolution Type: steerable-pyramid-decomposition
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-19
//  Ideas: H2 quadrature energy; source-tied reconstruction; local-phase line-vs-edge classing (quadrature phase hue); second a-trous octave (scale-competed underpainting)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn g2Basis(x: f32, y: f32, sigma: f32) -> vec3<f32> {
    let s2 = sigma * sigma;
    let gauss = exp(-(x*x + y*y) / (2.0 * s2 + 0.001));
    let g2a = (x*x / s2 - 1.0) * gauss / s2;
    let g2b = (x*y / s2) * gauss / s2;
    let g2c = (y*y / s2 - 1.0) * gauss / s2;
    return vec3<f32>(g2a, g2b, g2c);
}

fn h2Basis(x: f32, y: f32, sigma: f32) -> vec3<f32> {
    let s2 = sigma * sigma;
    let gauss = exp(-(x*x + y*y) / (2.0 * s2 + 0.001));
    let h2a = (x*x*x - 3.0*x*s2) / (s2*s2) * gauss / sigma;
    let h2b = (x*x*y - y*s2) / (s2*s2) * gauss / sigma;
    let h2c = (x*y*y - x*s2) / (s2*s2) * gauss / sigma;
    return vec3<f32>(h2a, h2b, h2c);
}

// One tap loop for the whole bank: the g2/h2 basis is evaluated once per tap and the
// four orientations (base + k*45 deg) are a vec4 lane each. HEAD called steerableFilter
// six times (b0/b45/b90/b135 + two CA bands) and re-fetched the same footprint every time.
struct Bank {
    fine: vec4<f32>,    // |quadrature response| at base + 0/45/90/135 deg (HEAD b0,b45,b90,b135 before scaling)
    evenF: vec4<f32>,   // signed even (line) response per orientation
    oddF: vec4<f32>,    // signed odd (edge) response per orientation
    coarse: vec4<f32>,  // |quadrature response| of the 2nd (2x tap spacing) octave
    caR: f32,           // orientation 0 band sampled at uv + caOff (HEAD b0_r)
    caB: f32,           // orientation 90 band sampled at uv - caOff (HEAD b90_b)
};

fn pyramidBank(uv: vec2<f32>, base: f32, sigma: f32, pixelSize: vec2<f32>, caOff: f32) -> Bank {
    var evenF = vec4<f32>(0.0);
    var oddF = vec4<f32>(0.0);
    var evenC = vec4<f32>(0.0);
    var oddC = vec4<f32>(0.0);
    var evenR = 0.0;
    var oddR = 0.0;
    var evenB = 0.0;
    var oddB = 0.0;
    let radius = i32(ceil(sigma * 3.0));
    let maxRadius = min(radius, 5);

    // cos/sin of 2*theta for theta = base + {0, 45, 90, 135} deg (HEAD's cos2T / sin2T)
    let ang2 = 2.0 * (base + vec4<f32>(0.0, 0.785398, 1.570796, 2.356194));
    let c2 = cos(ang2);
    let s2v = sin(ang2);
    let uvR = uv + vec2<f32>(caOff, 0.0);
    let uvB = uv - vec2<f32>(caOff, 0.0);
    let lumW = vec3<f32>(0.299, 0.587, 0.114);
    let lo = vec2<f32>(0.0);
    let hi = vec2<f32>(1.0);

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let x = f32(dx);
            let y = f32(dy);
            let g2 = g2Basis(x, y, sigma);
            let h2 = h2Basis(x, y, sigma);
            let kEven = (g2.x - g2.z) * c2 + g2.y * s2v;
            let kOdd = (h2.x - h2.z) * c2 + h2.y * s2v;

            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let lum = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, lo, hi), 0.0).rgb, lumW);
            let lumR = dot(textureSampleLevel(readTexture, u_sampler, clamp(uvR + offset, lo, hi), 0.0).rgb, lumW);
            let lumB = dot(textureSampleLevel(readTexture, u_sampler, clamp(uvB + offset, lo, hi), 0.0).rgb, lumW);
            // ── Idea 4: second a-trous octave — the same weights over taps spaced 2 px apart
            let lumK = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + offset * 2.0, lo, hi), 0.0).rgb, lumW);
            evenF += lum * kEven;
            oddF += lum * kOdd;
            evenC += lumK * kEven;
            oddC += lumK * kOdd;
            evenR += lumR * kEven.x;
            oddR += lumR * kOdd.x;
            evenB += lumB * kEven.z;
            oddB += lumB * kOdd.z;
        }
    }
    var o: Bank;
    o.fine = sqrt(evenF * evenF + oddF * oddF);
    o.evenF = evenF;
    o.oddF = oddF;
    o.coarse = sqrt(evenC * evenC + oddC * oddC);
    o.caR = sqrt(evenR * evenR + oddR * oddR);
    o.caB = sqrt(evenB * evenB + oddB * oddB);
    return o;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 0.5 + depth * 0.5;

    let sigma = mix(1.5, 4.0, u.zoom_params.x);
    let responseScale = mix(0.3, 2.0, u.zoom_params.y);
    let colorBoost = mix(0.5, 2.0, u.zoom_params.z);
    let mouseInfluence = u.zoom_params.w;

    // Bass-driven orientation steering
    let bassSteer = bass * 0.5;

    let mouseAngle = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 4.0) * mouseInfluence;
    let steerOffset = mouseAngle * mouseFactor + time * 0.15 + bassSteer;

    // Ripple orientation bursts
    var rippleSteer = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 2.5) {
            let rDist = length(uv - rPos);
            let rq = (rDist - rElapsed * 0.2) * 10.0;
            let wave = exp(-rq * rq);
            rippleSteer = rippleSteer + wave * (1.0 - rElapsed / 2.5) * 1.5;
        }
    }

    // Depth-based sigma (finer detail in foreground)
    let depthSigma = sigma * mix(0.7, 1.3, 1.0 - depth);

    let caStrength = 0.003 * (1.0 + bass);
    let bank = pyramidBank(uv, steerOffset + rippleSteer, depthSigma, pixelSize, caStrength);
    let bandScale = responseScale * depthFactor;
    let b0 = bank.fine.x * bandScale;
    let b45 = bank.fine.y * bandScale;
    let b90 = bank.fine.z * bandScale;
    let b135 = bank.fine.w * bandScale;

    // Chromatic aberration on pyramid bands
    let b0_r = bank.caR * bandScale;
    let b90_b = bank.caB * bandScale;

    // ── Idea 3: line-vs-edge phase classing. HEAD collapsed each quadrature (even, odd) pair
    // into |response|. The phase says what kind of feature the band found: odd/m = 0 is a
    // line/ridge (even-dominant), 1 is a step edge (odd-dominant). That ratio is sign-invariant
    // (HEAD's quadrupole kernel flips both signs 90 deg apart), so it is well defined per band
    // and rotates that band's palette index: bars and edges of equal contrast get different hues.
    let mF = bank.fine + vec4<f32>(0.0001);
    let edgeness = abs(bank.oddF) / mF;
    let phaseHue = 0.3 * (edgeness - vec4<f32>(0.5));

    // Artistic manipulation: boost and colorize
    let pal0 = palette(abs(b0) * 0.5 + 0.5 + phaseHue.x, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(abs(b45) * 0.5 + 0.5 + phaseHue.y, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(abs(b90) * 0.5 + 0.5 + phaseHue.z, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));

    let totalResponse = abs(b0) + abs(b45) + abs(b90) + 0.001;
    var color = (pal0 * abs(b0) + pal45 * abs(b45) + pal90 * abs(b90)) / totalResponse;

    // ── Idea 4: coarse octave competes with the fine one per pixel. Same three palettes,
    // index shifted +0.33 so the scale reads as a hue family; where broad oriented energy
    // beats fine energy it tints the underpainting, fine hatching keeps HEAD's colours.
    let bC = bank.coarse * bandScale;
    let totalC = bC.x + bC.y + bC.z;
    let palC0 = palette(bC.x * 0.5 + 0.83, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let palC45 = palette(bC.y * 0.5 + 0.83, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let palC90 = palette(bC.z * 0.5 + 0.83, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let coarseColor = (palC0 * bC.x + palC45 * bC.y + palC90 * bC.z) / (totalC + 0.001);
    color = mix(color, coarseColor, 0.6 * totalC / (totalC + totalResponse));

    // Apply chromatic aberration to color channels
    let caColorR = palette(abs(b0_r) * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67)) * abs(b0_r) / (abs(b0_r) + abs(b45) + abs(b90_b) + 0.001);
    let caColorB = palette(abs(b90_b) * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33)) * abs(b90_b) / (abs(b0_r) + abs(b45) + abs(b90_b) + 0.001);
    color.r = mix(color.r, caColorR.r, caStrength * 2.0);
    color.b = mix(color.b, caColorB.b, caStrength * 2.0);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    color = mix(color, src.rgb * (0.55 + totalResponse * 0.35), 0.28);
    color = color * colorBoost * (1.0 + treble * 0.3);

    // Temporal feedback: pyramid blending
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    color = mix(color, prev.rgb, 0.07 * (1.0 + mids));

    // ACES tone mapping
    color = acesToneMap(color * 1.2);

    // Depth boost
    color *= depthFactor;

    // Semantic alpha: 135° sub-band signed response modulated by depth and total energy
    let alpha = clamp(abs(b135) * depthFactor * (1.0 + bass) + src.a * 0.2, 0.0, 1.0);
    let packed = vec4<f32>(color, alpha);
    let pixel = vec2<i32>(global_id.xy);
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
