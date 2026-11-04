// ═══════════════════════════════════════════════════════════════════
//  Holographic Interferometry
//  Category: advanced-hybrid
//  Features: advanced-hybrid, interference-patterns, holography,
//            phase-coloring, audio-reactive, mouse-driven, exact-feedback
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: equal-phase contours; coherence envelope versus path difference
//  A packing: pre-ACES linear display RGBA; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
//  Simulated optical hologram with physical interference fringes.
//  Reference and object laser wavefronts interfere across depth and
//  luma fields, creating iridescent diffraction fringes with laser
//  speckle coherence and parallax depth reconstruction.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=FringeDensity, y=Coherence, z=ReconAngle, w=Saturation

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn speckleNoise(uv: vec2<f32>, coherence: f32, time: f32) -> f32 {
    let scale = mix(60.0, 480.0, coherence);
    var s = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        let fi = f32(i);
        s = s + hash12(uv * scale + vec2<f32>(fi * 13.7 + time * 0.05, fi * 42.3 - time * 0.03));
    }
    return s * 0.25;
}

fn interferencePattern(uv: vec2<f32>, depth: f32, fringeDensity: f32, angle: f32, distortion: f32) -> vec2<f32> {
    let objectPhase = depth * fringeDensity * 12.0 + distortion;
    let refPhase = (uv.x * cos(angle) + uv.y * sin(angle)) * fringeDensity * 45.0;
    // x = the same cosine the plate always drew. y = object path minus reference path.
    return vec2<f32>(0.5 + 0.5 * cos(objectPhase + refPhase), objectPhase - refPhase);
}

fn spectralReconstruct(totalPhase: f32, intensity: f32, satVal: f32) -> vec3<f32> {
    let hue = fract(totalPhase / TAU);
    let sat = clamp(0.6 + intensity * 0.4, 0.0, 1.0) * satVal;
    let val = clamp(0.4 + intensity * 0.6, 0.0, 1.5);

    let c = val * sat;
    let h = hue * 6.0;
    let x = c * (1.0 - abs(fract(h * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);

    if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }

    return rgb + vec3<f32>(val - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let isMouseDown = u.zoom_config.w > 0.5;
    let mouseUV = u.zoom_config.yz;

    // Live pointer. The extraBuffer spring was cleared by the host every frame.
    let smoothMouse = mouseUV;
    let clickImpulse = select(0.0, 1.0, isMouseDown);

    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let fringeDensity = mix(15.0, 110.0, u.zoom_params.x);
    let coherence = clamp(u.zoom_params.y, 0.0, 1.0);
    let reconAngle = u.zoom_params.z * TAU + (smoothMouse.x - 0.5) * 1.5;
    let saturation = mix(0.4, 1.8, u.zoom_params.w);

    let distMouse = length((uv - smoothMouse) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distMouse) * select(0.3, 1.0, isMouseDown);

    let sourceSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let sourceColor = sourceSample.rgb;
    let depthSrc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let geo = sin(uv.x * 24.0 + time * 1.2 + bass * 2.0) * cos(uv.y * 24.0 - time * 0.9 + mids) * 0.08;
    let depth = depthSrc + geo;
    let luma = dot(sourceColor, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let rDist = length((uv - r.xy) * aspectVec);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 38.0 - rAge * 12.0) * exp(-rDist * 7.0) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
        }
    }
    rippleDistortion = rippleDistortion + sin(distMouse * 35.0 - time * 8.0) * exp(-distMouse * 8.0) * clickImpulse * 0.5;
    rippleDistortion = rippleDistortion + holdEffect * 0.25;

    // Hologram interference & spectral reconstruction
    let pattern = interferencePattern(uv, depth, fringeDensity, reconAngle, rippleDistortion);
    let interference = pattern.x;
    // ── Idea 2: coherence envelope ────────────────────────────────────
    // Path difference is in radians of the carrier. Coherence Length is how
    // far that difference can grow before the fringes wash out. Speckle
    // scale below is unchanged.
    let pathNorm = pattern.y / max(fringeDensity, 1.0);
    let cohLen = mix(1.6, 28.0, coherence);
    let envelope = exp(-(pathNorm * pathNorm) / max(cohLen * cohLen, 0.25));
    let interferenceVis = mix(0.5, interference, envelope);
    let phase = acos(clamp(interferenceVis * 2.0 - 1.0, -1.0, 1.0));
    let reconPhase = (uv.x * cos(reconAngle + 0.5) + uv.y * sin(reconAngle + 0.5)) * 24.0;
    let totalPhase = phase + reconPhase + rippleDistortion * 4.0;

    let holoSpectral = spectralReconstruct(totalPhase, luma, saturation);

    let speckle = speckleNoise(uv + time * 0.005 * (1.0 + treble), coherence, time);
    let speckleMod = mix(1.0, 0.6 + 0.8 * speckle, coherence);

    let hologram = holoSpectral * (luma * 1.2 + 0.15 + bass * 0.25) * speckleMod;

    let fringes = sin(phase * fringeDensity * 0.5 + rippleDistortion * 6.0) * 0.5 + 0.5;
    let fringeColor = vec3<f32>(fringes * 0.6, fringes * 0.35, fringes * 0.8) * saturation;

    // Parallax depth view offset
    let parallax = (depth * 0.025 + holdEffect * 0.04) * (1.0 + mids * 0.3);
    let parallaxUV = clamp(uv + vec2<f32>(cos(reconAngle), sin(reconAngle)) * parallax, vec2<f32>(0.0), vec2<f32>(1.0));
    let parallaxColor = textureSampleLevel(readTexture, u_sampler, parallaxUV, 0.0).rgb;

    var color = mix(sourceColor * 0.25, hologram + fringeColor * 0.3, 0.75);
    color = mix(color, parallaxColor * holoSpectral, clamp(depth * 0.4 + holdEffect * 0.3, 0.0, 1.0));

    // ── Idea 1: equal-phase contours ──────────────────────────────────
    // The dark line sits where the cosine crosses a half-fringe.
    let contour = smoothstep(0.045, 0.0, abs(interference - 0.5));
    color = mix(color, color * 0.12, contour * 0.7);

    // Exact temporal feedback from dataTextureC (linear, same space as A).
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    color = max(mix(color, prev, 0.12 + mids * 0.08), vec3<f32>(0.0));

    let finalColor = acesToneMap(color * (1.0 + treble * 0.15));
    let alpha = clamp(luma * 0.6 + fringes * 0.3 + holdEffect * 0.2 + clickImpulse * 0.2 + contour * 0.15, 0.15, 0.98);

    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
