// ═══════════════════════════════════════════════════════════════════
//  astral-veins
//  Category: atmospheric
//  Features: upgraded-rgba, depth-aware, mouse-driven, audio-reactive, temporal-persistence
//  Complexity: High
//  Upgraded: 2026-03-22
//  Upgraded: 2026-10-31
//  Ideas: forward-scatter lobe along the veins (Henyey-Greenstein on the flow-oriented vein tangent, light = cursor); flow-advected persistence (afterglow in C streams down the warp currents); Rayleigh lambda^-4 blue aureole + pulse trains riding the warped potential
//  A packing: raw persistence state in A = (glow, veinMask, 0.737 sentinel, clamp(glow)); ACES applied to the vein glow layer on writeTexture only
//  Sliders: x = Flow Speed, y = Noise Scale, z = Glow Intensity, w = Hue Shift
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Constants that HEAD wrongly read from the (mis-ordered) zoom_config slots.
const VEIN_THRESH: f32 = 1.1;   // slope of the warped potential where a vein starts
const VEIN_SOFT: f32   = 0.9;
const DEPTH_INFLUENCE: f32 = 0.6;
const PULSE_SPEED: f32 = 0.25;
const FLOW_EPS: f32 = 0.03;
const SENTINEL: f32 = 0.737;
const HG_G: f32 = 0.45;

// ---------------------------------------------------------------
//  Utility – simple hash & value‑noise (fast, good enough for art)
// ---------------------------------------------------------------
fn hash(p: vec2<f32>) -> f32 {
    var h = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    let d = dot(h, vec3<f32>(h.y, h.z, h.x) + vec3<f32>(33.33));
    h = h + vec3<f32>(d);
    return fract((h.x + h.y) * h.z);
}
fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0,0.0)), hash(i + vec2<f32>(1.0,0.0)), w.x),
        mix(hash(i + vec2<f32>(0.0,1.0)), hash(i + vec2<f32>(1.0,1.0)), w.x), w.y);
}

// FBM – 5 octaves, rotating each octave to avoid axial artefacts
fn fbm(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var pt = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i: u32 = 0u; i < 5u; i = i + 1u) {
        sum += amp * noise(pt);
        pt = rot * pt * 2.0;
        amp *= 0.5;
    }
    return sum;
}

// Double domain‑warped potential: .x = f, .yz = second warp r (the flow field)
fn veinPotential(p: vec2<f32>, t: f32) -> vec3<f32> {
    let q = vec2<f32>(fbm(p + t), fbm(p + vec2<f32>(5.2, 1.3) + t));
    let r = vec2<f32>(
        fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + t * 0.7),
        fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + t * 0.7));
    let f = fbm(p + 4.0 * r + t * 0.3);
    return vec3<f32>(f, r);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
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
    let xc = max(x, vec3<f32>(0.0));
    return clamp((xc * (2.51 * xc + 0.03)) / (xc * (2.43 * xc + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn depthAt(c: vec2<i32>, dims: vec2<i32>) -> f32 {
    return textureLoad(readDepthTexture, clamp(c, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
}

// Persisted glow from C; 0 unless the texel carries our sentinel (inherited state from the previous shader).
fn glowAt(c: vec2<i32>, dims: vec2<i32>) -> f32 {
    let t = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    let ok = select(0.0, 1.0, abs(t.b - SENTINEL) < 0.0005);
    return clamp(t.r, 0.0, 4.0) * ok;
}

// Bilinear tap at a fractional pixel position (result is bounded by its four neighbours).
fn glowBilinear(pf: vec2<f32>, dims: vec2<i32>) -> f32 {
    let b = floor(pf);
    let fr = pf - b;
    let c0 = vec2<i32>(b);
    let g00 = glowAt(c0, dims);
    let g10 = glowAt(c0 + vec2<i32>(1, 0), dims);
    let g01 = glowAt(c0 + vec2<i32>(0, 1), dims);
    let g11 = glowAt(c0 + vec2<i32>(1, 1), dims);
    return mix(mix(g00, g10, fr.x), mix(g01, g11, fr.x), fr.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let dims = vec2<i32>(resolution);
    let pix = vec2<i32>(gid.xy);
    let uv  = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;

    let speed     = u.zoom_params.x * 0.4;
    let scale     = mix(0.4, 3.0, u.zoom_params.y);
    let intensity = u.zoom_params.z;
    let hueShift  = u.zoom_params.w;
    let mouse     = u.zoom_config.yz;

    // Depth & normal (veins follow geometry)
    let depth = depthAt(pix, dims);
    let dL = depthAt(pix - vec2<i32>(1, 0), dims);
    let dR = depthAt(pix + vec2<i32>(1, 0), dims);
    let dU = depthAt(pix - vec2<i32>(0, 1), dims);
    let dD = depthAt(pix + vec2<i32>(0, 1), dims);
    let normal = normalize(vec3<f32>(-(dR - dL) * 0.5, -(dD - dU) * 0.5, 1.0));

    // Domain‑warped flow field; the vein mask is the slope of the WARPED potential f
    let p = uv * scale;
    let tt = time * speed;
    let s0 = veinPotential(p, tt);
    let sx = veinPotential(p + vec2<f32>(FLOW_EPS, 0.0), tt);
    let sy = veinPotential(p + vec2<f32>(0.0, FLOW_EPS), tt);
    let grad = vec2<f32>(sx.x - s0.x, sy.x - s0.x) / FLOW_EPS;
    let gradMag = length(grad);
    let veinMask = smoothstep(VEIN_THRESH, VEIN_THRESH + VEIN_SOFT, gradMag);

    let flow = s0.yz - vec2<f32>(0.5);

    // ── Idea 1: forward-scatter lobe. Vein tangent oriented along the local flow; light = cursor ──
    let tang0 = vec2<f32>(-grad.y, grad.x) / max(gradMag, 1e-4);
    let tang = tang0 * select(-1.0, 1.0, dot(tang0, flow) >= 0.0);
    let toLight = mouse - uv;
    let lightDir = toLight / max(length(toLight), 1e-4);
    let cosT = clamp(dot(tang, lightDir), -1.0, 1.0);
    let hg = (1.0 - HG_G * HG_G) / pow(1.0 + HG_G * HG_G - 2.0 * HG_G * cosT, 1.5);
    let hgMax = (1.0 + HG_G) / ((1.0 - HG_G) * (1.0 - HG_G));
    let lobe = mix(0.35, 1.0, hg / hgMax);

    // Depth‑aware warp of the video sample
    let warpedUV = uv + normal.xy * DEPTH_INFLUENCE * 0.02;

    // Colour & pulse; Idea 3b: pulse trains travel along the warped potential
    let hue = fract(hueShift + time * 0.1);
    let baseCol = hsv2rgb(hue, 0.8, 1.0);
    let pulse = 0.5 + 0.5 * sin(6.2831853 * (PULSE_SPEED * time - s0.x * 3.0));
    let glow = pow(veinMask, 1.5) * intensity * (0.35 + 0.65 * pulse) * lobe * (1.0 + bass * 0.4);
    let veinCol = baseCol * glow;

    // ── Idea 2: persistence streams down the warp currents ──
    let back = vec2<f32>(gid.xy) - flow * 6.0;
    var prev = glowBilinear(back, dims);
    prev = prev * 0.94 + glow * 0.06;
    textureStore(dataTextureA, pix, vec4<f32>(prev, veinMask, SENTINEL, clamp(prev, 0.0, 1.0)));

    // ── Idea 3: Rayleigh (lambda^-4: 650/550/450nm) blue‑biased aureole ──
    let rayleigh = vec3<f32>(0.23, 0.45, 1.0);
    let halo = prev * 0.4 * mix(vec3<f32>(1.0), rayleigh, 0.7);

    let videoCol = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    var outCol = videoCol + acesToneMap(veinCol);
    outCol = 1.0 - (1.0 - clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.0))) * (1.0 - clamp(halo, vec3<f32>(0.0), vec3<f32>(1.0)));

    let luma = dot(outCol, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(writeTexture, pix, vec4<f32>(outCol, finalAlpha));
    textureStore(writeDepthTexture, pix, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
