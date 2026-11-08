// ═══════════════════════════════════════════════════════════════════
//  Parallax Layers RGBA
//  Category: artistic
//  Features: rgba, parallax, depth-layers, alpha-occlusion, dof, atmospheric, audio-reactive, mouse-driven
//  Upgraded: 2026-06-28, 2026-11-08
//  By: Codex
//  Ideas: slab occlusion with disocclusion fill (front-to-back over); seamless dolly crossfade (two zoom phases); rack-focus slice defocus (focus plane under the cursor); Beer-Lambert aerial perspective (§12.2F)
//  A packing: display RGBA (A = writeTexture colour + volumetric alpha; C is not read)
//  Rescue: the layer stack never reached the output at HEAD (baseColor unused); chroma was bass-as-uv-offset; edge glow polarity was inverted.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: 4 user params mapped 0..1

fn ping_pong(a: f32) -> f32 {
    return (1.0 - abs(((fract((a * 0.5)) * 2.0) - 1.0)));
}

fn ping_pong_v2_(v: vec2<f32>) -> vec2<f32> {
    let _e2 = ping_pong(v.x);
    let _e4 = ping_pong(v.y);
    return vec2<f32>(_e2, _e4);
}

fn hash21_(p: vec2<f32>) -> f32 {
    var p3_: vec3<f32>;

    p3_ = fract((vec3<f32>(p.x, p.y, p.x) * 0.1031));
    let _e9 = p3_;
    let _e10 = p3_;
    let _e11 = p3_;
    p3_ = (_e9 + vec3(dot(_e10, (_e11 + vec3(33.33)))));
    let _e19 = p3_.x;
    let _e21 = p3_.y;
    let _e24 = p3_.z;
    return fract(((_e19 + _e21) * _e24));
}

fn noise(p_1: vec2<f32>) -> f32 {
    var i_1: vec2<f32>;

    i_1 = floor(p_1);
    let f = fract(p_1);
    let u2_ = ((f * f) * (vec2(3.0) - (2.0 * f)));
    let _e11 = i_1;
    let _e16 = hash21_((_e11 + vec2<f32>(0.0, 0.0)));
    let _e17 = i_1;
    let _e22 = hash21_((_e17 + vec2<f32>(1.0, 0.0)));
    let _e25 = i_1;
    let _e30 = hash21_((_e25 + vec2<f32>(0.0, 1.0)));
    let _e31 = i_1;
    let _e36 = hash21_((_e31 + vec2<f32>(1.0, 1.0)));
    return mix(mix(_e16, _e22, u2_.x), mix(_e30, _e36, u2_.x), u2_.y);
}

fn hsv2rgb(h: f32, s: f32, v_1: f32) -> vec3<f32> {
    var rgb: vec3<f32> = vec3(0.0);

    let c = (v_1 * s);
    let h6_ = (h * 6.0);
    let x = (c * (1.0 - abs(((fract(h6_) * 2.0) - 1.0))));
    if (h6_ < 1.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else {
        if (h6_ < 2.0) {
            rgb = vec3<f32>(x, c, 0.0);
        } else {
            if (h6_ < 3.0) {
                rgb = vec3<f32>(0.0, c, x);
            } else {
                if (h6_ < 4.0) {
                    rgb = vec3<f32>(0.0, x, c);
                } else {
                    if (h6_ < 5.0) {
                        rgb = vec3<f32>(x, 0.0, c);
                    } else {
                        rgb = vec3<f32>(c, 0.0, x);
                    }
                }
            }
        }
    }
    let _e40 = rgb;
    return (_e40 + vec3((v_1 - c)));
}

fn reconstruct_normal(uv_1: vec2<f32>, depth: f32) -> vec3<f32> {
    var resolution_1: vec2<f32>;

    let _e5 = u.config.z;
    let _e9 = u.config.w;
    resolution_1 = vec2<f32>(_e5, _e9);
    let _e14 = resolution_1.x;
    let _e18 = resolution_1.y;
    let offset = vec2<f32>((1.0 / _e14), (1.0 / _e18));
    let _e28 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(offset.x, 0.0)), 0.0);
    let _e37 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(offset.x, 0.0)), 0.0);
    let dx = (_e28.x - _e37.x);
    let _e47 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(0.0, offset.y)), 0.0);
    let _e56 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(0.0, offset.y)), 0.0);
    let dy = (_e47.x - _e56.x);
    let n = vec3<f32>(-(dx), -(dy), 1.0);
    return normalize(n);
}

fn schlickFresnel(cosTheta: f32, F0_: f32) -> f32 {
    return (F0_ + ((1.0 - F0_) * pow((1.0 - cosTheta), 5.0)));
}

fn calculateVolumetricAlpha(layerDepth: f32, fogDensity: f32, viewDotNormal: f32, accumulatedWeight: f32) -> f32 {
    let _e7 = schlickFresnel(max(0.0, viewDotNormal), 0.03);
    let fogAmount = exp(((-(layerDepth) * fogDensity) * 3.0));
    let depthAlpha = mix(0.95, 0.4, fogAmount);
    let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
    let alpha = ((depthAlpha * weightAlpha) * (1.0 - (_e7 * 0.2)));
    return clamp(alpha, 0.0, 1.0);
}

// Idea 3 helper: one slice sample with a depth-scaled R/B split (HEAD's chromatic
// split, now applied to the slice itself) and a 3-tap rotated defocus gather.
// coc is a uv-space radius (0 = pinhole sharp). Colour only; depth is read separately.
fn sliceColor(uv: vec2<f32>, coc: f32, off: vec2<f32>, rot: f32) -> vec3<f32> {
    let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, ping_pong_v2_(uv + off), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, ping_pong_v2_(uv - off), 0.0).b;
    let split = vec3<f32>(r, c0.g, b);
    // 3 taps 120 deg apart, rotated per slice so the slices do not stack the same footprint
    let asp = vec2<f32>(u.config.w / u.config.z, 1.0);
    let d0 = vec2<f32>(cos(rot), sin(rot)) * coc * asp;
    let d1 = vec2<f32>(cos(rot + 2.0943951), sin(rot + 2.0943951)) * coc * asp;
    let d2 = vec2<f32>(cos(rot + 4.1887902), sin(rot + 4.1887902)) * coc * asp;
    let t0 = textureSampleLevel(readTexture, u_sampler, ping_pong_v2_(uv + d0), 0.0).rgb;
    let t1 = textureSampleLevel(readTexture, u_sampler, ping_pong_v2_(uv + d1), 0.0).rgb;
    let t2 = textureSampleLevel(readTexture, u_sampler, ping_pong_v2_(uv + d2), 0.0).rgb;
    let blur = (split + t0 + t1 + t2) * 0.25;
    // blend toward the gathered disc as the circle of confusion opens (~1.5 px = fully soft)
    let k = clamp(coc * u.config.z * 0.6, 0.0, 1.0);
    return mix(split, blur, k);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let zoom_time = u.zoom_config.x;
    let zoom_center = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio from plasmaBuffer[0] (extraBuffer[0] is bass at 0..1 — not a uv offset).
    let bass = plasmaBuffer[0].x;

    // clickIntensity: HEAD fed FFT bin 5 (extraBuffer[10]) into the vortex; keep that drive and let
    // a held pointer spin the slices too (the name always meant click).
    var fftSpin = 0.0;
    if (arrayLength(&extraBuffer) > 10u) {
        fftSpin = extraBuffer[10];
    }
    let clickIntensity = max(fftSpin, 0.6 * mouseDown);

    // Saved slider roles (unchanged): x Parallax = near speed, y Layer Density = far speed,
    // z Depth of Field = aperture (was dead), w Fog = density.
    let dofAmt = u.zoom_params.z;
    let fogDensity = u.zoom_params.w;

    // Idea 3: the focal plane sits at the depth under the cursor (zoom_center, idle 0.5,0.5).
    let focusDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
                                        clamp(zoom_center, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).x;

    // Small, bass-pulsed fringe (HEAD: raw bass 0..1 as a uv offset). Depth-scaled per slice below.
    let chroma = 0.004 + bass * 0.012;

    var accumulatedColor = vec3<f32>(0.0);
    var accumulatedDepth = 0.0;
    var accumulatedGrad = 0.0;
    var transmittance = 1.0; // Idea 1: light not yet blocked by nearer slices
    let ps = 1.0 / resolution;

    for (var i: i32 = 0; i < 5; i = i + 1) {
        let layerDepth_1 = f32(i) / 4.0;
        let layerSpeed = mix(u.zoom_params.x, u.zoom_params.y, layerDepth_1);

        // (HEAD) vortex spin + noise flow jitter, per slice
        let toCenter = uv - zoom_center;
        let dist = length(toCenter);
        let vortexStrength = (clickIntensity * 0.3) / (dist + 0.1);
        let spinAngle = vortexStrength * layerDepth_1 * (1.0 - layerDepth_1);
        let rotatedUV = vec2<f32>(cos(spinAngle) * toCenter.x - sin(spinAngle) * toCenter.y,
                                  sin(spinAngle) * toCenter.x + cos(spinAngle) * toCenter.y) + zoom_center;
        let n1 = noise(rotatedUV * 6.0 + vec2<f32>(time * 0.15, 0.0));
        let n2 = noise(rotatedUV * 6.0 + vec2<f32>(0.0, time * 0.15));
        let flowUV = rotatedUV + vec2<f32>(n1, n2) * 0.015 * layerDepth_1;

        // ── Idea 2: seamless dolly crossfade ───────────────────────────
        // HEAD zoomed each slice 1x -> 5x with fract() and snapped back to 1x (a visible pop per
        // slice per period). Two phases half a period apart, weighted sin^2 / cos^2 (they sum to
        // exactly 1), are each at weight 0 at their own reset, so the loop has no seam.
        let ph = zoom_time * layerSpeed;
        let f0 = fract(ph);
        let f1 = fract(ph + 0.5);
        let s0 = sin(3.14159265 * f0);
        let w0 = s0 * s0;
        let w1 = 1.0 - w0;
        let uvA = ping_pong_v2_((flowUV - zoom_center) / vec2<f32>(1.0 + f0 * 4.0) + zoom_center);
        let uvB = ping_pong_v2_((flowUV - zoom_center) / vec2<f32>(1.0 + f1 * 4.0) + zoom_center);

        // ── Idea 3: rack-focus slice defocus ───────────────────────────
        // Circle of confusion grows with the slice's distance from the focal plane; the Depth of
        // Field slider is the aperture. dof = 0 -> pinhole sharp (every slice), as before.
        let coc = dofAmt * abs(layerDepth_1 - focusDepth) * 0.05;
        let off = vec2<f32>(chroma * (0.25 + 0.75 * layerDepth_1), 0.0);
        let rot = f32(i) * 2.39996323;

        // Phases whose weight is ~0 are skipped (the condition is uniform across the dispatch).
        var sliceCol = vec3<f32>(0.0);
        var sampleDepth = 0.0;
        var wSum = 0.0;
        if (w0 > 0.02) {
            sliceCol += sliceColor(uvA, coc, off, rot) * w0;
            sampleDepth += textureSampleLevel(readDepthTexture, non_filtering_sampler, uvA, 0.0).x * w0;
            wSum += w0;
        }
        if (w1 > 0.02) {
            sliceCol += sliceColor(uvB, coc, off, rot + 1.0) * w1;
            sampleDepth += textureSampleLevel(readDepthTexture, non_filtering_sampler, uvB, 0.0).x * w1;
            wSum += w1;
        }
        sliceCol = sliceCol / max(wSum, 0.0001);
        sampleDepth = sampleDepth / max(wSum, 0.0001);

        // (HEAD) depth-gradient edge, now measured on the slice's OWN zoomed sample (HEAD read
        // it at the unzoomed uv, which would draw rings at the original silhouettes on top of
        // the zoomed picture). One screen pixel in zoomed space = ps / zoom in source space.
        let useA = w0 >= 0.5;
        let uvD = select(uvB, uvA, useA);
        let zf = select(1.0 + f1 * 4.0, 1.0 + f0 * 4.0, useA);
        let gC = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvD, 0.0).x;
        let gX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvD + vec2<f32>(ps.x / zf, 0.0), 0.0).x;
        let gY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvD + vec2<f32>(0.0, ps.y / zf), 0.0).x;
        let sliceGrad = length(vec2<f32>(gX - gC, gY - gC));

        // ── Idea 1: slab occlusion with disocclusion fill ──────────────
        // A slice covers a pixel strongly where the sampled scene depth belongs to its plane and
        // weakly elsewhere (floor 0.35 so a flat or missing depth map still shows every slice).
        // Front-to-back: nearer slices occlude, and where a nearer slice's sample belongs to a
        // different depth the farther slice shows through (the disocclusion fill).
        let density = exp(-layerDepth_1 * 1.5);
        let slab = 1.0 - smoothstep(0.0, 0.25, abs(sampleDepth - layerDepth_1));
        let cover = clamp(density * (1.0 + sampleDepth * 0.5) * mix(0.35, 1.0, slab), 0.0, 0.95);
        let wgt = transmittance * cover;
        accumulatedColor += sliceCol * wgt;
        accumulatedDepth += sampleDepth * wgt;
        accumulatedGrad += sliceGrad * wgt;
        transmittance = transmittance * (1.0 - cover);
    }
    let coverage = 1.0 - transmittance;
    let baseColor = accumulatedColor / max(coverage, 0.0001);
    let baseDepth = accumulatedDepth / max(coverage, 0.0001);

    // (HEAD) depth-gradient edge glow — polarity fixed: HEAD's exp(-k*grad) was brightest on FLAT
    // depth; the glow belongs on the discontinuity (gradient gathered per slice above).
    let depthGrad = accumulatedGrad / max(coverage, 0.0001);
    let edgeGlow = (1.0 - exp(-depthGrad * 30.0)) * (0.15 + 0.35 * baseDepth);
    let finalColor = baseColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

    // ── Idea 4: Beer-Lambert aerial perspective (§12.2F) ────────────────
    // T_c = exp(-sigma_c * d). The green channel keeps HEAD's scalar exactly (sigma = fog*3);
    // red is eaten faster and blue slower, so distance drifts into the existing navy haze.
    let sigma = fogDensity * 3.0 * vec3<f32>(1.25, 1.0, 0.75);
    let trans = exp(-baseDepth * sigma);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outColor = max(finalColor * trans + fogColor * (vec3<f32>(1.0) - trans), vec3<f32>(0.0));

    let viewDotNormal_1 = dot(vec3<f32>(0.0, 0.0, 1.0), reconstruct_normal(uv, baseDepth));
    // Alpha is semantic: slice coverage + atmosphere (HEAD passed a constant 0.5 as the depth).
    let alpha = calculateVolumetricAlpha(baseDepth, fogDensity, viewDotNormal_1, coverage);

    let px = vec2<i32>(gid.xy);
    textureStore(writeTexture, px, vec4<f32>(outColor, alpha));
    textureStore(writeDepthTexture, px, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, px, vec4<f32>(outColor, alpha));
}
