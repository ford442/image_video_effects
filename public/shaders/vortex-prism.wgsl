// ═══════════════════════════════════════════════════════════════════════════════
//  VORTEX PRISM with Alpha Physics
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: continuous 7-tap spectrum fan; Rankine core (smoothness = core radius); shear caustics
//  A packing: ACES display RGBA
//
//  Twisting vortex effect that separates colors prismatically with physical deformation.
//
//  ALPHA PHYSICS:
//  - Prismatic separation creates differential light paths per channel
//  - Each RGB channel experiences different distortion = different alpha
//  - Wavelength-dependent opacity simulates chromatic dispersion
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=TwistAmount, y=PrismStrength, z=Radius, w=Smoothness

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(
        v.x * c - v.y * s,
        v.x * s + v.y * c
    );
}

// Calculate prismatic distortion magnitude
fn calculatePrismaticDistortion(
    falloff: f32,
    twistAmount: f32,
    prismStrength: f32
) -> f32 {
    let twistMag = abs(twistAmount) * falloff;
    let prismMag = prismStrength * falloff;
    return twistMag + prismMag;
}

// Wavelength-dependent alpha calculation
// Blue (shorter wavelength) scatters more = lower alpha
// Red (longer wavelength) penetrates more = higher alpha
fn calculatePrismaticAlpha(
    baseAlpha: f32,
    distortionMag: f32,
    channel: i32  // 0=R, 1=G, 2=B
) -> f32 {
    // Wavelength scattering factors (simplified)
    // Shorter wavelengths scatter more
    let scatteringFactor = vec3<f32>(0.8, 1.0, 1.3); // R, G, B
    
    let wavelengthScatter = scatteringFactor[channel];
    
    // Distortion creates scattering loss
    let scatterLoss = distortionMag * 0.2 * wavelengthScatter;
    
    // Higher twist = more separation = more scattering
    return clamp(baseAlpha - scatterLoss, 0.3, 1.0);
}

// Idea 1 helper: normalised wavelength (0 = red end, 1 = blue end) → RGB
// response. Normalised per channel by the caller so white stays white.
fn spectralResponse(lambda: f32) -> vec3<f32> {
    let d = vec3<f32>(lambda) - vec3<f32>(0.0, 0.5, 1.0);
    return exp(-(d * d) / (2.0 * 0.22 * 0.22));
}

// Idea 2: Rankine vortex profile — solid-body rotation inside the core radius
// rc (constant twist angle: a calm, unsheared eye), 1/r decay outside (the
// sheared outer band), tapered to zero at the effect radius like HEAD.
fn rankineProfile(r: f32, rc: f32, radius: f32) -> f32 {
    let core = select(rc / max(r, 1e-5), 1.0, r <= rc);
    let taper = 1.0 - smoothstep(rc, radius, r);
    return core * taper;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    // ═══ AUDIO REACTIVITY ═══ (HEAD read zoom_config.x = time as "audio")
    let audioBass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Params — bass adds up to +30% twist
    let twistAmount = (u.zoom_params.x - 0.5) * 20.0 * (1.0 + 0.3 * audioBass); // -10 to 10
    let prismStrength = u.zoom_params.y * 0.1;
    let radius = mix(0.1, 1.5, u.zoom_params.z);
    let smoothness = u.zoom_params.w;

    let mouseX = u.zoom_config.y;
    let mouseY = u.zoom_config.z;

    // Center of vortex
    var center = vec2<f32>(mouseX, mouseY);
    if (mouseX == 0.0 && mouseY == 0.0) {
        center = vec2<f32>(0.5, 0.5);
    }

    // Aspect Ratio Correction
    let aspect = resolution.x / resolution.y;

    let fragCoord = vec2<f32>(global_id.xy);
    let uv = fragCoord / resolution;

    // UV relative to center, corrected for aspect
    var d = uv - center;
    d.x = d.x * aspect;

    let dist = length(d);

    // Idea 2: Rankine core — the (formerly dead) smoothness slider sets the
    // core radius. Default 0.5 → rc ≈ 0.33·radius, which tracks HEAD's
    // smoothstep falloff to within ~0.05 at mid-radius.
    let rc = radius * mix(0.05, 0.6, smoothness);
    let falloff = rankineProfile(dist, rc, radius);
    let twistAngle = falloff * twistAmount;

    // Idea 3: Shear caustics — radial shear of the twist, r·|dθ/dr| (rotation
    // per log-radius). Zero in the solid-body eye, steep in the 1/r band.
    let eps = max(radius * 0.01, 1e-4);
    let dProfile = (rankineProfile(dist + eps, rc, radius) - rankineProfile(max(dist - eps, 0.0), rc, radius)) / (2.0 * eps);
    // Normalised by the twist so the band sits on the steep part of the
    // profile at any Twist Force; strength then grows with |twist|.
    let shearN = abs(dProfile) * dist;
    let shearGain = smoothstep(0.3, 3.0, abs(twistAmount));

    // Calculate distortion magnitude
    let distortionMag = calculatePrismaticDistortion(falloff, twistAmount, prismStrength);

    // Idea 1: Continuous spectrum fan — 7 wavelength taps whose twist angles
    // span HEAD's [1 − prism, 1 + prism] (red end → blue end), each weighted by
    // a normalised wavelength→RGB response: smooth rainbow arcs, white stays white.
    let causticSpread = clamp(prismStrength * 6.0, 0.0, 0.6);
    var fanRGB = vec3<f32>(0.0);
    var fanA = vec3<f32>(0.0);
    var respSum = vec3<f32>(0.0);
    var caustic = vec3<f32>(0.0);
    var uvMid = uv;
    for (var k = 0; k < 7; k++) {
        let lambda = f32(k) / 6.0;
        let fanK = 1.0 + prismStrength * (2.0 * lambda - 1.0);
        var dk = rotate(d, twistAngle * fanK);
        dk.x = dk.x / aspect;
        let uvK = center + dk;
        if (k == 3) { uvMid = uvK; }
        let tap = textureSampleLevel(readTexture, u_sampler, uvK, 0.0);
        let resp = spectralResponse(lambda);
        fanRGB += tap.rgb * resp;
        fanA += vec3<f32>(tap.a) * resp;
        respSum += resp;
        // Idea 3: each wavelength crosses the shear threshold at a slightly
        // different radius (spread follows the fan) → spectrally tinted band;
        // weighting by the twisted tap's luma turns it into spiral streaks.
        let shearK = shearN * (1.0 + causticSpread * (2.0 * lambda - 1.0));
        let tapLuma = dot(tap.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
        caustic += resp * smoothstep(0.75, 1.05, shearK) * smoothstep(0.45, 1.0, tapLuma);
    }
    let invSum = vec3<f32>(1.0) / max(respSum, vec3<f32>(1e-4));
    let fanColor = fanRGB * invSum;
    let fanAlpha = fanA * invSum;
    caustic = caustic * invSum * shearGain;

    // Calculate per-channel alphas with wavelength physics
    let alphaR = calculatePrismaticAlpha(fanAlpha.r, distortionMag, 0);
    let alphaG = calculatePrismaticAlpha(fanAlpha.g, distortionMag, 1);
    let alphaB = calculatePrismaticAlpha(fanAlpha.b, distortionMag, 2);

    // Blend alphas based on prism strength
    let avgAlpha = mix(
        (alphaR + alphaG + alphaB) / 3.0,
        max(max(alphaR, alphaG), alphaB),
        prismStrength * 0.5
    );

    // Compose final color (Idea 3: caustic streaks added on top of the fan)
    var color = vec4<f32>(fanColor + caustic * 0.35, avgAlpha);

    // Add subtle glow at center with alpha
    if (dist < 0.05 * radius) {
        let glowIntensity = (1.0 - dist / (0.05 * radius)) * 0.15;
        let glowAlpha = glowIntensity * 0.5;
        color = color + vec4<f32>(0.1, 0.1, 0.2, glowAlpha) * (1.0 - dist / (0.05 * radius));
        color.a = min(color.a + glowAlpha, 1.0);
    }

    let outColor = vec4<f32>(aces(max(color.rgb, vec3<f32>(0.0))), clamp(color.a, 0.0, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

    // Depth follows the twisted geometry (centre-wavelength path)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvMid, 0.0).r;
    // Each channel effectively samples at different depth due to dispersion
    let depthUncertainty = distortionMag * 0.05;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(clamp(depth * (1.0 + depthUncertainty), 0.0, 1.0), 0.0, 0.0, 0.0));
}
