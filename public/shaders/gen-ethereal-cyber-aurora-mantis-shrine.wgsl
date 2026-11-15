// ----------------------------------------------------------------
// Ethereal Cyber-Aurora Mantis-Shrine
// Category: generative
// Features: mouse-driven, audio-reactive, upgraded-rgba
// Upgraded: 2026-11-15
// Ideas: aurora curtain sky fused to the lotus palette hue clock; chrome mantis mirrors the curtains (environment reflection); heartbeat ring travelling out of the heart along the filaments and washing the body
// A packing: ACES display RGBA (HEAD stored nothing in A; C is never read)
// Rescues: audio from plasmaBuffer[0].x (HEAD read dataTextureC(0,0), never written); upright camera (HEAD screen-y was world-down: mantis head-down, mist a ceiling); camera pitch clamped above the ground mist (HEAD white-out at the bottom edge); semantic alpha; m_scale / normalize guards
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 20.0;

// Palette function for auroral colors
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth minimum
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Capsule SDF
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Torus SDF
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Noise for mist and filaments
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// ── Idea 1: aurora curtain sky (native: the shrine is named for it) ──
// Hanging curtains folded around the azimuth, sharp lower hem + long soft fade upward,
// vertical ray striations, coloured with the lotus' own palette() hue clock.
fn auroraSky(rd: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    // Below the horizon every layer's hem term is exactly 0, so skip the noise work.
    if (rd.y <= 0.0) { return vec3<f32>(0.0); }
    let alt = rd.y;
    let az = atan2(rd.x, rd.z);
    var acc = vec3<f32>(0.0);
    for (var k = 0; k < 3; k++) {
        let fk = f32(k);
        let wob = noise3(vec3<f32>(az * 1.6 + fk * 3.1, alt * 1.5, time * 0.06 + fk * 1.7)) * 2.4;
        let band = 0.5 + 0.5 * sin(az * (3.0 + fk * 1.5) + wob + time * 0.05 * (1.0 + fk));
        let sheet = band * band * band;
        let hem = smoothstep(fk * 0.03, 0.10 + fk * 0.04, alt);
        let fade = exp(-max(alt - 0.10, 0.0) * (2.4 + fk * 0.9));
        let rays = 0.6 + 0.4 * noise3(vec3<f32>(az * 16.0 + fk * 9.0, alt * 0.8, time * 0.35));
        let tint = palette(alt * 0.7 + fk * 0.21 - time * 0.2,
                           vec3<f32>(0.5), vec3<f32>(0.5),
                           vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.3, 0.1, 0.6));
        acc += tint * sheet * hem * fade * rays;
    }
    return acc * (0.8 + bass * 0.8);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Chrome environment: aurora above the horizon, ground-mist tint below.
// Below refl.y = -0.18 the mix weight is exactly 0, so the sky work is skipped with an identical result.
fn chromeEnv(refl: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    let groundRefl = vec3<f32>(0.03, 0.10, 0.17);
    if (refl.y < -0.18) { return groundRefl; }
    let skyRefl = auroraSky(refl, time, bass) + vec3<f32>(0.02, 0.05, 0.1) * noise3(refl * 3.0);
    return mix(groundRefl, skyRefl, smoothstep(-0.18, 0.06, refl.y));
}

// Heartbeat ring + heart flash at a surface point (only mats 2, 3, 4 read it).
fn beatRing(p: vec3<f32>, heartP: vec3<f32>, ringR: f32, beatPhase: f32, m_scale: f32) -> vec2<f32> {
    let dh = length(p - heartP);
    let rr = (dh - ringR) / (0.42 * m_scale);
    let ring = exp(-rr * rr) * (1.0 - 0.7 * beatPhase);
    let heartFlash = exp(-beatPhase * 5.0) * exp(-dh * 1.4 / m_scale);
    return vec2<f32>(ring, heartFlash);
}

// Heart centre in world space (mirrors the mp/hp offsets used in map()).
fn heartPos(time: f32, m_scale: f32) -> vec3<f32> {
    return vec3<f32>(0.0, m_scale * (1.2 + sin(time) * 0.2), 0.0);
}

// Map function returning (distance, material_id)
// material_id: 1.0 for mist, 2.0 for mantis, 3.0 for lotus, 4.0 for heart/filaments
fn map(p: vec3<f32>) -> vec2<f32> {
    var d = MAX_DIST;
    var mat = 0.0;

    let time = u.config.x;

    // Mouse Interaction
    var q = p;
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse_uv.x * 5.0, -mouse_uv.y * 5.0, 0.0);

    if (u.zoom_config.w > 0.5) { // Click triggered burst
        let dist = length(q - mouse_pos);
        let ripple = sin(dist * 10.0 - time * 5.0) * exp(-dist * 0.5) * 0.2;
        q += (q - mouse_pos) / max(dist, 0.001) * ripple;
    }

    // --- 1. Mist (FBM) ---
    let mist_fbm = noise3(q * 0.5 + vec3<f32>(time * 0.1)) * 0.5 + noise3(q * 1.0 - vec3<f32>(time * 0.2)) * 0.25;
    // Rescue 3 (cont.): with the upright camera the mist must be the GROUND (HEAD's -p.y+2 was a ceiling that only
    // looked like a floor because the whole picture was upside-down).
    let mist_d = p.y + 2.0 - mist_fbm * u.zoom_params.z * 5.0; // Ground mist

    // --- 2. Mantis ---
    var mantis_d = MAX_DIST;
    let m_scale = max(u.zoom_params.x, 0.1);
    var mp = q / m_scale;
    mp.y -= 1.0 + sin(time) * 0.2; // Hovering

    // Thorax
    mantis_d = sdCapsule(mp, vec3<f32>(0.0, 0.5, 0.0), vec3<f32>(0.0, -0.5, -0.2), 0.3);
    // Head
    let head = length(vec3<f32>(abs(mp.x), mp.y - 0.7, mp.z + 0.1) * vec3<f32>(1.0, 1.2, 0.8)) - 0.2;
    mantis_d = smin(mantis_d, head, 0.1);

    // Arms
    var amp = mp;
    amp.x = abs(amp.x); // symmetry
    let arm1 = sdCapsule(amp, vec3<f32>(0.3, 0.4, 0.0), vec3<f32>(0.8, 0.6, 0.5), 0.05);
    let arm2 = sdCapsule(amp, vec3<f32>(0.8, 0.6, 0.5), vec3<f32>(0.5, -0.2, 0.8), 0.03);
    mantis_d = smin(mantis_d, smin(arm1, arm2, 0.1), 0.1);

    mantis_d *= m_scale;

    // --- 3. Lotus ---
    var lotus_d = MAX_DIST;
    var lp = q;
    lp.y += 1.0;

    let lotus_comp = u.zoom_params.y;
    for(var i=0; i<4; i++) {
        if(f32(i) > lotus_comp) { break; }
        var a = atan2(lp.x, lp.z);
        var r = length(lp.xz);
        let num_petals = 6.0 + f32(i) * 2.0;
        let p_angle = 6.28318 / num_petals;
        a = (fract(a / p_angle) - 0.5) * p_angle;
        lp.x = cos(a) * r;
        lp.z = sin(a) * r;

        let rot_mat = rot(0.5 + sin(time * 0.5 + f32(i)) * 0.2);
        let lp_xy_1 = rot_mat * lp.xy;
        lp.x = lp_xy_1.x;
        lp.y = lp_xy_1.y;
        lp.y -= 0.5 * pow(0.7, f32(i));

        let petal = sdCapsule(lp, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), 0.05 + 0.1 * (1.0 - lp.x));
        lotus_d = smin(lotus_d, petal, 0.2);
    }

    // --- 4. Heart Pulse & Filaments ---
    // Rescue 1: HEAD read dataTextureC(0,0).x as "audio" - nothing ever writes A, so it was a dead 0.
    let bassMap = plasmaBuffer[0].x;
    let pulse = u.zoom_params.w * (1.0 + bassMap * 5.0);

    // Heart
    var hp = mp;
    hp.y -= 0.2;
    let rot_h = rot(time);
    let hp_xz_2 = rot_h * hp.xz;
    hp.x = hp_xz_2.x;
    hp.z = hp_xz_2.y;
    let hp_xy_3 = rot_h * hp.xy;
    hp.x = hp_xy_3.x;
    hp.y = hp_xy_3.y;
    let heart = (length(hp) - 0.15) * m_scale;

    // Filaments (Connecting arms to lotus)
    let f_disp = noise3(q * 5.0 - vec3<f32>(0.0, time * 2.0, 0.0)) * 0.02;
    let filaments = sdCapsule(amp, vec3<f32>(0.5, -0.2, 0.8), vec3<f32>(1.0, -1.0, 0.0), 0.01) * m_scale + f_disp;

    let emissive_d = smin(heart, filaments, 0.1) - pulse * 0.01;

    // Combine
    if (mist_d < d) { d = mist_d; mat = 1.0; }
    if (lotus_d < d) { d = lotus_d; mat = 3.0; }
    if (mantis_d < d) { d = mantis_d; mat = 2.0; }
    if (emissive_d < d) { d = emissive_d; mat = 4.0; }

    // Smooth blending between lotus and mantis
    if (mat == 2.0 || mat == 3.0) {
        d = smin(mantis_d, lotus_d, 0.5);
        mat = select(3.0, 2.0, mantis_d < lotus_d); // Approximate material
    }

    return vec2<f32>(d * 0.5, mat); // Distance under-relaxation for fractals/noise
}

// Raymarching
// Perf (fog crawl): inside the mist HEAD's step is clamped to 0.01 and the ray burns the whole 100-step
// budget there (74-86 % of all steps in a frame that is half ground fog). The crawl now moves CRAWL_N x as far
// per step, charges the loop CRAWL_N budget units, and adds CRAWL_N x the per-step mist term, with the term
// extrapolated to the centroid of the interval it stands for (first-order, from the previous crawl sample).
// Same depth range, same budget, same integral; only the quadrature is coarser. Approach steps are untouched.
const CRAWL_N = 4;
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var dO = 0.0;
    var mat = 0.0;
    var mist_dens = 0.0;
    var gPrev = 0.0;
    var prevCrawl = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let res = map(p);
        let dS = res.x;
        let inMist = res.y == 1.0;
        let crawl = inMist && dS < 0.01;
        // Units of HEAD's 0.01-steps this iteration stands for; the last group is clipped to the budget left.
        let nUnits = select(1, min(CRAWL_N, MAX_STEPS - i), crawl);
        let fN = f32(nUnits);

        if (inMist && dS < 0.1) {
            let g = 0.05 * (0.1 - dS); // Accumulate mist (HEAD's per-step term)
            let gHat = g + select(0.0, 0.375 * (g - gPrev), prevCrawl);
            mist_dens += select(g, fN * gHat, crawl);
            gPrev = g;
        }

        dO += select(max(dS, 0.01), 0.01 * fN, crawl); // Prevent getting stuck
        i += nUnits - 1;
        prevCrawl = crawl;
        mat = res.y;

        if (dO > MAX_DIST || (dS < SURF_DIST && res.y != 1.0)) { break; }
    }
    return vec3<f32>(dO, mat, mist_dens);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    var uv = (fragCoord - 0.5 * res) / res.y;
    // Rescue 3: pixel rows grow DOWN the screen but u_cam is world-up, so HEAD rendered the shrine upside-down
    // (mantis head-down, lotus above it). Flip so +y on screen is +y in the world.
    uv.y = -uv.y;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let m_scale = max(u.zoom_params.x, 0.1); // Rescue 5: guard the mp = q / m_scale divide (saved min is 0.5)

    // Mouse orbit
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);

    // Rescue 4: HEAD let the orbit drop/lift the camera into the mist SDF (flat white frame). Keep the idle
    // framing, let the cursor lift the camera freely, but only dip it a hair below the horizon (ground mist at y=-2).
    let pitchIn = clamp(select(mouse_uv.y * 0.12, mouse_uv.y, mouse_uv.y > 0.0), -0.12, 0.9);
    let cam_rot_x = rot(-pitchIn * 1.5);
    let cam_rot_y = rot(mouse_uv.x * 3.14 + time * 0.1);

    let ro_yz_4 = cam_rot_x * ro.yz;
    ro.y = ro_yz_4.x;
    ro.z = ro_yz_4.y;
    let ro_xz_5 = cam_rot_y * ro.xz;
    ro.x = ro_xz_5.x;
    ro.z = ro_xz_5.y;

    let lookat = vec3<f32>(0.0, 0.0, 0.0);
    let zoom = 1.0;

    let f = normalize(lookat - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let u_cam = cross(f, r);
    var rd = normalize(uv.x * r + uv.y * u_cam + f * zoom);

    // Raymarch
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let mat = rm.y;
    let mist = rm.z;

    var col = vec3<f32>(0.0);
    let hit = d < MAX_DIST && mat != 1.0;

    // ── Idea 3: heartbeat ring. A pulse leaves the heart at the beat rate and travels out through the
    // filaments, then washes over the body it passes (native: the heart is the shrine's light source).
    let beatRate = 0.55 + bass * 0.6;
    let beatPhase = fract(time * beatRate);
    let heartP = heartPos(time, m_scale);
    let ringR = beatPhase * 2.4 * m_scale;
    let beatAmp = clamp(u.zoom_params.w, 0.0, 3.0) * 0.6 * (1.0 + bass);

    if (hit) {
        let p = ro + rd * d;
        let n = calcNormal(p);
        let viewDir = normalize(ro - p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);

        if (mat == 2.0) { // Mantis (Liquid Chrome)
            let base = vec3<f32>(0.1, 0.15, 0.2);
            col = base * diff + vec3<f32>(1.0) * spec + vec3<f32>(0.4, 0.8, 1.0) * fresnel;
            // ── Idea 2: chrome environment reflection. The mirror body carries the same curtains as the sky
            // (horizon split: ground mist below, aurora above) instead of a constant grey-blue rim.
            let env = chromeEnv(reflect(rd, n), time, bass);
            col += env * (0.55 + 0.9 * fresnel);
            col += vec3<f32>(0.1, 0.9, 1.0) * beatRing(p, heartP, ringR, beatPhase, m_scale).x * beatAmp * 1.5;
        } else if (mat == 3.0) { // Lotus (Auroral Plasma)
            let base = palette(length(p) * 0.5 - time,
                               vec3<f32>(0.5), vec3<f32>(0.5),
                               vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.3, 0.1, 0.6));
            col = base * (diff * 0.5 + 0.5) + base * fresnel * 2.0;
            // The reflection weight is fresnel*0.6; below 0.004 it moves the pixel by < 0.003 pre-ACES, skip it.
            if (fresnel > 0.004) {
                col += chromeEnv(reflect(rd, n), time, bass) * fresnel * 0.6;
            }
            col += vec3<f32>(0.1, 0.9, 1.0) * beatRing(p, heartP, ringR, beatPhase, m_scale).x * beatAmp * 1.1;
        } else if (mat == 4.0) { // Heart/Filaments (Emissive)
            // Rescue 1: bass (plasmaBuffer[0].x), not the never-written C(0,0) texel.
            let intensity = u.zoom_params.w * (1.0 + bass * 2.0);
            let br = beatRing(p, heartP, ringR, beatPhase, m_scale);
            col = vec3<f32>(0.1, 0.9, 1.0) * intensity * 2.0 * (1.0 + 2.2 * br.x * (0.4 + beatAmp) + 1.4 * br.y);
        }
    }

    // Add Mist Volumetrics
    col += vec3<f32>(0.1, 0.3, 0.5) * mist;

    // Background: faint nebula + the aurora curtains (rays that left the scene)
    if (d >= MAX_DIST) {
        let bg_noise = noise3(rd * 3.0);
        col += vec3<f32>(0.02, 0.05, 0.1) * bg_noise;
        col += auroraSky(rd, time, bass);
    }

    // Rescue 2: ACES on the display colour (HEAD: gamma pow only). Clamp first: the catalog fit maps negatives bright.
    let hdr = max(col, vec3<f32>(0.0));
    let mapped = aces(hdr * 1.25);

    // Rescue 2 (cont.): semantic alpha (HEAD: bare 1.0) and A = display RGBA (HEAD: no A store). Surfaces are
    // opaque, aurora/mist cover in proportion to their light.
    let glowLum = dot(hdr, vec3<f32>(0.299, 0.587, 0.114));
    let cover = select(clamp(glowLum * 1.6 + mist * 2.5, 0.0, 1.0), 1.0, hit);
    let alpha = clamp(0.18 + 0.82 * cover, 0.0, 1.0);

    let outColor = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(id.xy), outColor);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(select(0.0, 1.0 - clamp(d / MAX_DIST, 0.0, 1.0), d < MAX_DIST), 0.0, 0.0, 0.0));
}
