// ═══════════════════════════════════════════════════════════════════════════════
//  Spectral Bleed & Confinement
//  Category: advanced-hybrid
//  Features: mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-11-09
//  Ideas: tangent-aligned bleed tensor (Di Zenzo colour structure tensor from the three Sobel gradients, tap lattice rotated into the edge frame and stretched along the tangent per channel, §12.2A structure-tensor orientation); energy-moving reflection halo (rejected kernel mass drives the boundary glow, which is paid for by the bled colour under it, §12.2F energy-conserving bloom). Rescued: bleedRate was zoom_config.x (= time), confinement cancelled out of the kernel normalisation (now a real cross-channel wall), flat "Gaussian" envelope, redundant Sobels.
//  A packing: display RGBA (ACES) + semantic alpha — HEAD stored unclamped HDR colour with alpha 1.0; C is read exact and is display-referred
//
//  Specific color bands "leak" outward from edges while being electromagnetically
//  "confined" by other channels. Creates glowing halos that feel physically
//  constrained—like plasma in a magnetic bottle.
//  Mathematical approach: Sobel edge detection per channel, anisotropic
//  diffusion with channel-dependent diffusion tensors, electromagnetic
//  confinement via cross-channel gradient repulsion, Fresnel-like boundary
//  reflection for confined colors.
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=DiffusionRadius, y=FieldIntensity, z=ChannelBias, w=PulseSpeed
// zoom_config: .w = mouse held (tightens the confinement walls); .x is TIME and is not read.

// Bleed kernel tuning (tap space: one tap = `radius` texels)
const SIG_TAPS: f32 = 3.5;    // Gaussian sigma of the tap envelope, in taps (replaces HEAD's dimensionally-broken flat box)
const STRETCH: f32 = 1.5;     // extra reach along the edge tangent on a coherent own-channel edge (tangent taps spread to 1 + STRETCH)
const WALL_K: f32 = 6.0;      // cross-channel wall steepness (x confinement strength)
const BLEED_RATE: f32 = 0.4;  // HEAD mapped zoom_config.x (time!) * 0.6 + 0.1; 0.4 is that mapping at its midpoint

// ─────────────────────────────────────────────────────────────────────────────
//  Sobel edge detection, all three channels from one 3x3 fetch.
//  Returns the per-channel gradient vectors as columns: [0]=R, [1]=G, [2]=B.
// ─────────────────────────────────────────────────────────────────────────────
fn sobelAll(uv: vec2<f32>, texel: vec2<f32>) -> mat3x2<f32> {
    var v: array<vec3<f32>, 9>;
    var idx = 0;
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            v[idx] = textureSampleLevel(readTexture, u_sampler,
                clamp(uv + vec2<f32>(f32(dx), f32(dy)) * texel, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            idx++;
        }
    }
    // Sobel kernels (same weights as HEAD, applied to all three channels at once)
    let gx = -v[0] + v[2] - 2.0 * v[3] + 2.0 * v[5] - v[6] + v[8];
    let gy = -v[0] - 2.0 * v[1] - v[2] + v[6] + 2.0 * v[7] + v[8];
    return mat3x2<f32>(
        vec2<f32>(gx.r, gy.r),
        vec2<f32>(gx.g, gy.g),
        vec2<f32>(gx.b, gy.b)
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Anisotropic diffusion kernel for color bleeding
//  Diffuses one channel outward from edges. Returns (bled value, rejected kernel mass).
//
//  Idea 1 (tangent-aligned tensor): the 9x9 tap lattice is rotated into the edge frame
//  (tangent, normal) and stretched by `stretch` along the tangent only: D_parallel > D_perp,
//  a channel on a coherent edge of its own reaches (1 + STRETCH)x further along it while its
//  across-edge reach stays HEAD's.
//  Confinement (R2): a tap only counts as much as the OTHER two channels agree with
//  the centre pixel there (exp(-confinement * WALL_K * |delta others|)): a wall made of
//  the other channels' edges. Taps already carry rgb, so the wall costs no extra fetch.
//  rho = 1 - sum(wall-weighted) / sum(unwalled): the kernel mass the wall turned away.
// ─────────────────────────────────────────────────────────────────────────────
fn diffuseChannel(uv: vec2<f32>, texel: vec2<f32>, channel: i32, radius: f32, confinement: f32,
                  ctr: vec3<f32>, tng: vec2<f32>, stretch: f32) -> vec2<f32> {
    let chMask = select(select(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, 1.0, 0.0), channel == 1),
                        vec3<f32>(1.0, 0.0, 0.0), channel == 0);
    let otherMask = vec3<f32>(1.0) - chMask;
    let stepUV = texel * radius;
    let nrmV = vec2<f32>(-tng.y, tng.x);
    let invS2 = 0.5 / (SIG_TAPS * SIG_TAPS);
    let wallGain = confinement * WALL_K;

    var sum = 0.0;
    var wWall = 0.0;
    var wGauss = 0.0;
    for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
            let fx = f32(dx);
            let fy = f32(dy);
            let g = exp(-(fx * fx + fy * fy) * invS2);
            let off = (fx * stretch) * tng + fy * nrmV;

            let s = textureSampleLevel(readTexture, u_sampler,
                clamp(uv + off * stepUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let wall = exp(-wallGain * dot(abs(s - ctr), otherMask));

            let w = g * wall;
            sum += dot(s, chMask) * w;
            wWall += w;
            wGauss += g;
        }
    }
    let bled = sum / max(wWall, 0.001);
    let rho = clamp(1.0 - wWall / max(wGauss, 0.001), 0.0, 1.0);
    return vec2<f32>(bled, rho);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fresnel-like boundary glow at confinement edges
// ─────────────────────────────────────────────────────────────────────────────
fn fresnelGlow(edgeStr: f32, confinement: f32, phase: f32) -> f32 {
    let boundary = smoothstep(0.05, 0.2, edgeStr) * smoothstep(0.05, 0.15, confinement);
    return boundary * (0.5 + 0.5 * sin(phase)) * 0.3;
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB for glow coloring
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = fragCoord / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let diffRadius = u.zoom_params.x * 4.0 + 1.0;          // 1 – 5
    let fieldIntensity = u.zoom_params.y * 2.0 + 0.3;      // 0.3 – 2.3
    let channelBias = u.zoom_params.z;                       // 0 – 1 (which channel bleeds most)
    let pulseSpeed = u.zoom_params.w * 4.0 + 0.5;          // 0.5 – 4.5
    let bleedRate = BLEED_RATE;
    // Holding the pointer squeezes the bottle: wall strength 0.5 idle -> 3.5 held (HEAD's mapping,
    // which was invisible because confinement cancelled out of the kernel — now it bites).
    let confinementStr = u.zoom_config.w * 3.0 + 0.5;       // 0.5 – 3.5

    // ─────────────────────────────────────────────────────────────────────────
    //  Read source and depth
    // ─────────────────────────────────────────────────────────────────────────
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ─────────────────────────────────────────────────────────────────────────
    //  Per-channel edge detection (one shared 3x3 fetch)
    // ─────────────────────────────────────────────────────────────────────────
    let grads = sobelAll(uv, texel);
    let gR = grads[0];
    let gG = grads[1];
    let gB = grads[2];
    let edgeR = length(gR);
    let edgeG = length(gG);
    let edgeB = length(gB);

    // ── Idea 1: Di Zenzo colour structure tensor (§12.2A) ───────────────────
    // J = sum_c g_c g_c^T over the three channel gradients `main` already has.
    // theta = edge-normal angle, coherence = (l1-l2)/(l1+l2) = 2*sqrt(((jxx-jyy)/2)^2+jxy^2)/trace.
    let jxx = gR.x * gR.x + gG.x * gG.x + gB.x * gB.x;
    let jyy = gR.y * gR.y + gG.y * gG.y + gB.y * gB.y;
    let jxy = gR.x * gR.y + gG.x * gG.y + gB.x * gB.y;
    // +1e-6: atan2(0, 0) is indeterminate in WGSL and exactly-flat sky / black bars give a zero tensor.
    let theta = 0.5 * atan2(2.0 * jxy, jxx - jyy + 1e-6);
    let disc = sqrt(max(0.25 * (jxx - jyy) * (jxx - jyy) + jxy * jxy, 0.0));
    let coh = clamp(2.0 * disc / max(jxx + jyy, 1e-6), 0.0, 1.0);
    let edgeMax = max(edgeR, max(edgeG, edgeB));
    let aniso = coh * smoothstep(0.02, 0.15, edgeMax);          // 0 on flat cloth -> isotropic, as HEAD
    let nrm = vec2<f32>(cos(theta), sin(theta));
    let tng = vec2<f32>(-nrm.y, nrm.x);
    // channel-dependent tensor: a channel with its own coherent edge reaches further along it,
    // a channel with no edge of its own bleeds isotropically (and is walled in by the others).
    let strR = 1.0 + STRETCH * aniso * smoothstep(0.01, 0.15, edgeR);
    let strG = 1.0 + STRETCH * aniso * smoothstep(0.01, 0.15, edgeG);
    let strB = 1.0 + STRETCH * aniso * smoothstep(0.01, 0.15, edgeB);

    // ─────────────────────────────────────────────────────────────────────────
    //  Channel-biased bleed radius: selected channel bleeds more
    // ─────────────────────────────────────────────────────────────────────────
    let biasR = mix(1.0, 1.8, smoothstep(0.0, 0.33, channelBias));
    let biasG = mix(1.0, 1.8, smoothstep(0.33, 0.66, channelBias) - smoothstep(0.66, 1.0, channelBias));
    let biasB = mix(1.0, 1.8, smoothstep(0.66, 1.0, channelBias));

    // Pulsing bleed radius
    let pulse = 0.8 + 0.2 * sin(time * pulseSpeed);
    let radiusR = diffRadius * biasR * pulse * (0.5 + depth * 0.5);
    let radiusG = diffRadius * biasG * pulse * (0.5 + depth * 0.5);
    let radiusB = diffRadius * biasB * pulse * (0.5 + depth * 0.5);

    // ─────────────────────────────────────────────────────────────────────────
    //  Diffuse each channel with confinement from the other two
    // ─────────────────────────────────────────────────────────────────────────
    let dR = diffuseChannel(uv, texel, 0, radiusR, confinementStr, srcColor, tng, strR);
    let dG = diffuseChannel(uv, texel, 1, radiusG, confinementStr, srcColor, tng, strG);
    let dB = diffuseChannel(uv, texel, 2, radiusB, confinementStr, srcColor, tng, strB);

    let bledColor = vec3<f32>(dR.x, dG.x, dB.x);
    let rho = vec3<f32>(dR.y, dG.y, dB.y);

    // ─────────────────────────────────────────────────────────────────────────
    //  Mix original with bled version based on edge strength
    //  Strong edges bleed, flat areas stay crisp
    // ─────────────────────────────────────────────────────────────────────────
    let edgeMask = vec3<f32>(
        smoothstep(0.02, 0.15, edgeR),
        smoothstep(0.02, 0.15, edgeG),
        smoothstep(0.02, 0.15, edgeB)
    );
    var result = mix(srcColor, bledColor, edgeMask * bleedRate);

    // ─────────────────────────────────────────────────────────────────────────
    //  Confinement boundary glow: where bleed meets resistance
    // ─────────────────────────────────────────────────────────────────────────
    let glowR = fresnelGlow(edgeR, edgeG + edgeB, time * pulseSpeed + 0.0);
    let glowG = fresnelGlow(edgeG, edgeR + edgeB, time * pulseSpeed + 2.09);
    let glowB = fresnelGlow(edgeB, edgeR + edgeG, time * pulseSpeed + 4.18);
    // ── Idea 2: energy-moving reflection halo (§12.2F) ──────────────────────
    // The share of a channel's kernel mass the wall turned away (rho) is the reflected energy:
    // it scales the Fresnel-like glow, and the bled colour under the rim pays for it
    // (out = res*(1-k*g) + g, k = 0.6) so the halo moves light instead of inventing it.
    let glow = vec3<f32>(
        glowR * (0.4 + 1.2 * rho.x) * 1.0,
        glowG * (0.4 + 1.2 * rho.y) * 0.8,
        glowB * (0.4 + 1.2 * rho.z) * 1.2
    ) * fieldIntensity;
    result = result * (vec3<f32>(1.0) - 0.6 * clamp(glow, vec3<f32>(0.0), vec3<f32>(1.0))) + glow;

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: localized bleed burst
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[min(i, 49u)];
        let dist = distance(uv, r.xy);
        let age = time - r.z;
        if (age > 0.0 && age < 3.0) {
            let ring = exp(-abs(dist - age * 0.15) * 30.0) * exp(-age * 0.8);
            let burstHue = fract(dist * 3.0 + age * 0.5);
            result += hsv2rgb(burstHue, 0.8, 1.0) * ring * 0.2 * fieldIntensity;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Feedback: bleed persists over time (C is display RGBA, read exactly)
    // ─────────────────────────────────────────────────────────────────────────
    let history = textureLoad(dataTextureC, vec2<i32>(id.xy), 0).rgb;
    let display = acesToneMap(max(result, vec3<f32>(0.0)));
    let finalColor = mix(display, history, 0.3);

    // Semantic alpha: the photo covers the frame (0.8); bleeding edges and the rim glow are opaque.
    let alpha = mix(0.8, 1.0, clamp(max(edgeMask.x, max(edgeMask.y, edgeMask.z)) + max(glow.x, max(glow.y, glow.z)), 0.0, 1.0));

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
