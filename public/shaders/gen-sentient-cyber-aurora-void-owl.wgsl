// ═══════════════════════════════════════════════════════════════════
//  Sentient Cyber-Aurora Void-Owl
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-19
//  Ideas: auroral feather-current lanes; faceted cyber-iris aperture;
//         facial disc (radial rachis dishes + ruff, soft inverse-square sound
//         focus on asymmetric ears); Airy eyeshine sized by the iris pupil (§12.2F)
//  A packing: ACES display RGBA (C read back as colour for the motion-trail mix)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// --- Math & Noise Helpers ---

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for(var i = 0; i < 4; i++) {
        value += amp * noise3(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return value;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Head frame: world → head-local (the head tracks the mouse) and back.
fn headLocal(p: vec3<f32>, mouseXY: vec2<f32>) -> vec3<f32> {
    var h = p - vec3<f32>(0.0, 1.0, 0.0);
    let xz = rot(mouseXY.x * 0.5) * h.xz;
    h = vec3<f32>(xz.x, h.y, xz.y);
    let yz = rot(-mouseXY.y * 0.5) * h.yz;
    return vec3<f32>(h.x, yz.x, yz.y);
}

fn headToWorld(h: vec3<f32>, mouseXY: vec2<f32>) -> vec3<f32> {
    let yz = rot(mouseXY.y * 0.5) * h.yz;
    var w = vec3<f32>(h.x, yz.x, yz.y);
    let xz = rot(-mouseXY.x * 0.5) * w.xz;
    return vec3<f32>(xz.x, w.y, xz.y) + vec3<f32>(0.0, 1.0, 0.0);
}

// (2·J1(x)/x)²: series below 4, asymptotic (first correction term) above.
fn airy(x: f32) -> f32 {
    let xs = max(abs(x), 1e-4);
    let x2 = xs * xs;
    let series = xs * (0.5 - x2 * (0.0625 - x2 * (0.00260417 - x2 * (0.0000542535 - x2 * (6.78168e-7 - x2 * 5.6514e-9)))));
    let chi = xs - 2.35619449;
    let asym = sqrt(0.63661977 / xs) * (cos(chi) - 0.375 / xs * sin(chi));
    let j1 = select(asym, series, xs < 4.0);
    let v = 2.0 * j1 / xs;
    return v * v;
}

const EYE_L = vec3<f32>(0.4, 0.2, 0.8);
const EYE_R = vec3<f32>(-0.4, 0.2, 0.8);

// --- SDF functions ---

struct MapData {
    d: f32,
    mat: f32,
    glow: f32,
    lane: f32,
}

fn map(p: vec3<f32>, time: f32, audio: f32, mouseXY: vec2<f32>, wingbeat_speed: f32, eye_intensity: f32) -> MapData {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;
    var lane = 0.0;

    var pos = p;

    // Head tracking the mouse (mouseXY is -1..1 with +y up)
    let headPos = headLocal(pos, mouseXY);

    // Body Base (Capsule) — ends under the head (HEAD ran it to y = 3, up through and past
    // the head, so the owl read as a pin with eyes halfway up)
    let pa = pos - vec3<f32>(0.0, -1.5, 0.0);
    let ba = vec3<f32>(0.0, 0.4, 0.0) - vec3<f32>(0.0, -1.5, 0.0);
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    let dBody = length(pa - ba * h) - 1.2 * (1.0 - h * 0.5);

    // Head Base (Sphere)
    let dHead = length(headPos) - 1.0;
    var dOwl = smin(dBody, dHead, 0.5);

    // Feathers (Lattice of prisms)
    var fPos = pos;
    let wingbeat = sin(time * 5.0 * wingbeat_speed) * (0.5 + audio * 1.5);

    fPos.x = abs(fPos.x);
    let wingPos = fPos - vec3<f32>(1.5, 0.0, 0.0);

    var wPos = wingPos;
    let wRot = rot(wingbeat * 0.5);
    let nwxy = wRot * vec2<f32>(wPos.x, wPos.y);
    wPos.x = nwxy.x;
    wPos.y = nwxy.y;

    let latticeScale = 0.5;
    let cell = floor(wPos / latticeScale);
    lane = cell.y;
    var q = (fract(wPos / latticeScale + 0.5) - 0.5) * latticeScale;
    let dFeatherCube = sdBox(q, vec3<f32>(0.2, 0.05, 0.1));
    let dWingBox = sdBox(wPos, vec3<f32>(2.0, 3.0, 0.5));
    let dWings = max(dFeatherCube, dWingBox);

    dOwl = min(dOwl, dWings);

    // Eyes: thin glass shell so the iris/core can actually win (on the camera side, +z;
    // HEAD put them at z = -0.8, on the back of the head)
    let eyePosL = headPos - EYE_L;
    let eyePosR = headPos - EYE_R;
    let dEyeGlassL = abs(length(eyePosL) - 0.26) - 0.035;
    let dEyeGlassR = abs(length(eyePosR) - 0.26) - 0.035;
    let dEyeGlass = min(dEyeGlassL, dEyeGlassR);

    let dEyeCoreL = length(eyePosL) - 0.11;
    let dEyeCoreR = length(eyePosR) - 0.11;
    let dEyeCore = min(dEyeCoreL, dEyeCoreR);

    if (dEyeCore < dOwl && dEyeCore < dEyeGlass) {
        d = dEyeCore;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dEyeCore), 2.0) * eye_intensity * (1.0 + audio * 2.0);
    } else if (dEyeGlass < dOwl) {
        d = dEyeGlass;
        mat = 1.0;
    } else {
        d = dOwl;
        mat = 0.0;
        if (dWings < dBody && dWings < dHead) {
            mat = 3.0; // feather lattice (current lanes)
        }
    }

    return MapData(d * 0.5, mat, glow, lane);
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32, mouseXY: vec2<f32>, wingbeat_speed: f32, eye_intensity: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio, mouseXY, wingbeat_speed, eye_intensity).d;
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, mouseXY, wingbeat_speed, eye_intensity).d - d,
        map(p + e.yxy, time, audio, mouseXY, wingbeat_speed, eye_intensity).d - d,
        map(p + e.yyx, time, audio, mouseXY, wingbeat_speed, eye_intensity).d - d
    );
    return normalize(n);
}

// --- Main Compute ---

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    // Row 0 is the top of the screen: flip so +y is up (HEAD drew the owl upside-down).
    let uv = vec2<f32>(f32(id.x) - 0.5 * res.x, 0.5 * res.y - f32(id.y)) / res.y;

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass;

    // UI Sliders
    let wingbeat_speed = u.zoom_params.x;
    let eye_intensity = u.zoom_params.y;
    let aurora_density = u.zoom_params.z;
    let glass_refraction = u.zoom_params.w;

    let mouseNorm = vec2<f32>(u.zoom_config.y * 2.0 - 1.0, 1.0 - u.zoom_config.z * 2.0);

    // Camera
    var ro = vec3<f32>(0.0, 1.0, 10.0);
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch
    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var lane = 0.0;
    var totalGlow = 0.0;
    var hit = false;

    // Volumetric Aurora
    var volColor = vec3<f32>(0.0);
    var volDensity = 0.0;

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let resData = map(p, time, audio, mouseNorm, wingbeat_speed, eye_intensity);
        d = resData.d;
        mat = resData.mat;
        lane = resData.lane;

        if (resData.mat == 2.0) {
            totalGlow += resData.glow * 0.1;
        }

        // Volumetric aurora accumulation (background/ambient)
        // fbm here spans only about ±0.15, so HEAD's smoothstep(0.4, 0.8) never fired: remap
        // to ~0..1, and stretch in y so the volume hangs in curtains.
        let auroraNoise = fbm(p * vec3<f32>(0.5, 0.18, 0.5) + vec3<f32>(time * 0.2, time * 0.1, 0.0)) * 3.3 + 0.5;
        let localDensity = smoothstep(0.4, 0.8, auroraNoise) * aurora_density * 0.05;
        volDensity += localDensity;

        // Color mapping for aurora
        let aColor = mix(vec3<f32>(0.0, 0.8, 0.5), vec3<f32>(0.8, 0.2, 0.8), sin(p.y * 0.5 + time) * 0.5 + 0.5);
        volColor += aColor * localDensity;

        if (d < 0.005 || t > 25.0) { hit = d < 0.005; break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let pupil = 0.07 * (1.0 - 0.45 * clamp(treble, 0.0, 1.0));

    let auroraTint = mix(vec3<f32>(0.1, 0.9, 0.6), vec3<f32>(0.75, 0.25, 0.85), 0.5 + 0.5 * sin(time * 0.4));
    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p, time, audio, mouseNorm, wingbeat_speed, eye_intensity);

        if (mat == 0.0 || mat == 3.0) {
            let lightDir = normalize(vec3<f32>(1.0, 2.0, 1.0));
            let diff = max(dot(n, lightDir), 0.0);
            let refl = reflect(rd, n);
            let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);
            let baseColor = vec3<f32>(0.05, 0.05, 0.08);
            col = baseColor * diff * 0.8 + vec3<f32>(0.5, 0.8, 1.0) * spec * 0.5;
            // aurora back/rim light: the void-dark plumage reads as a silhouette lit by the sky
            let rimL = pow(1.0 - max(dot(-rd, n), 0.0), 3.0);
            col += auroraTint * rimL * (0.25 + aurora_density * 0.35) + vec3<f32>(0.02, 0.025, 0.04);

            // ── Idea 1: facial disc ──
            // Two concave dishes of radial feathers around the eyes, bordered by a ruff; the
            // dish focuses sound onto the ear openings (asymmetric: left ear higher), lit with a
            // soft inverse-square falloff toward each ear.
            if (mat == 0.0) {
                let hp = headLocal(p, mouseNorm);
                let front = smoothstep(0.15, 0.45, hp.z);
                let dl = hp.xy - EYE_L.xy;
                let dr = hp.xy - EYE_R.xy;
                let useL = length(dl) < length(dr);
                let de = select(dr, dl, useL);
                let r = length(de);
                let R = 0.5;
                let disc = smoothstep(R, R - 0.04, r) * front;
                let rachis = pow(0.5 + 0.5 * cos(atan2(de.y, de.x) * 26.0), 3.0);
                let ruff = exp(-pow((r - R) / 0.05, 2.0)) * front;
                let ear = select(vec2<f32>(-0.66, 0.08), vec2<f32>(0.66, 0.32), useL);
                let de2 = dot(hp.xy - ear, hp.xy - ear);
                let r0 = 0.14;
                let focus = r0 * r0 / (de2 + r0 * r0);
                let sound = 0.35 + bass * 1.3 + mids * 0.6;
                col = mix(col, col * 0.6 + vec3<f32>(0.035, 0.04, 0.06), disc);
                col += auroraTint * disc * (0.06 + rachis * 0.22 * smoothstep(0.08, 0.3, r)) * (0.6 + focus * sound * 2.2);
                col += auroraTint * disc * focus * sound * 0.5;
                col += mix(auroraTint, vec3<f32>(0.85, 0.9, 1.0), 0.5) * ruff * 0.55;
            }
            if (mat == 3.0) {
                let along = fract(abs(p.x) * 0.35 + time * (0.8 + mids));
                let pulse = exp(-abs(along - 0.5) * 10.0);
                let rowMix = step(0.5, fract(abs(lane) * 0.5));
                col += mix(vec3<f32>(0.15, 0.95, 0.85), vec3<f32>(0.95, 0.25, 0.9), rowMix) * pulse * aurora_density * 0.55;
            }
        } else if (mat == 1.0) {
            let refl = reflect(rd, n);
            let envWarp = fbm(refl * 5.0 + time);
            col = vec3<f32>(0.2, 0.4, 0.5) * envWarp * glass_refraction;
            let rim = 1.0 - max(dot(-rd, n), 0.0);
            col += vec3<f32>(0.5, 0.8, 1.0) * pow(rim, 3.0);
            let eyeLocal = headLocal(p, mouseNorm);
            let eL = eyeLocal - EYE_L;
            let eR = eyeLocal - EYE_R;
            let ePos = select(eR, eL, length(eL) < length(eR));
            let polar = atan2(ePos.y, ePos.x);
            let radial = length(ePos.xy);
            let sector = fract(polar / (2.0 * PI) * 6.0 + time * (0.15 + treble * 0.4));
            let blade = smoothstep(0.12, 0.02, abs(sector - 0.5));
            // the blades open onto the pupil (narrows with treble; also sizes the Airy halo)
            let ring = smoothstep(0.16, 0.07, radial) * smoothstep(pupil * 0.5, pupil, radial);
            col += vec3<f32>(0.2, 0.95, 1.0) * blade * ring * eye_intensity * 0.65;
        } else if (mat == 2.0) {
            col = mix(vec3<f32>(0.8, 0.2, 1.0), vec3<f32>(0.2, 1.0, 1.0), clamp(audio, 0.0, 1.0));
            col *= eye_intensity;
        }
    }

    col += volColor;
    let glowColor = mix(vec3<f32>(0.8, 0.2, 1.0), vec3<f32>(0.2, 1.0, 1.0), clamp(audio * 2.0, 0.0, 1.0));
    col += glowColor * totalGlow;

    // ── Idea 2: Airy eyeshine (§12.2F) ──
    // The pupil is a circular aperture, so the eyeshine an observer sees is diffraction-limited:
    // (2J1(x)/x)² around each projected eye centre, first dark ring ∝ 1/pupil (the iris
    // narrowing with treble widens the halo). Fades when the eye turns away from the camera.
    let eyeCol = mix(vec3<f32>(0.8, 0.2, 1.0), vec3<f32>(0.2, 1.0, 1.0), clamp(audio * 2.0, 0.0, 1.0));
    let airyR = 0.0024 / pupil;
    for (var k = 0; k < 2; k++) {
        let eLocal = select(EYE_R, EYE_L, k == 0);
        let eW = headToWorld(eLocal, mouseNorm);
        let outward = normalize(headToWorld(eLocal * 1.2, mouseNorm) - eW);
        let v = eW - ro;
        let zc = max(dot(v, fwd), 0.1);
        let sp = vec2<f32>(dot(v, right), dot(v, up)) / zc;
        let faceCam = smoothstep(0.0, 0.5, dot(outward, -normalize(v)));
        let x = 3.8317 * length(uv - sp) / airyR;
        let behind = select(1.0, 0.0, hit && t < length(v) - 0.3);
        col += eyeCol * airy(x) * faceCam * behind * eye_intensity * (2.5 + bass * 3.0);
    }

    // star sparkle: same ±0.15 fbm range, remapped (HEAD's > 0.8 never fired)
    let pNoise = fbm(vec3<f32>(uv * 20.0, time)) * 3.3 + 0.5;
    if (!hit && pNoise > 0.97) {
        col += vec3<f32>(0.5, 1.0, 0.8) * (pNoise - 0.97) * 6.0 * (1.0 + audio);
    }

    let vignette = 1.0 - smoothstep(0.5, 1.5, length(uv));
    col *= vignette;
    col = acesToneMap(col * 1.1);

    // motion trail from our own history (HEAD read readTexture, the input image)
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0).rgb;
    let finalCol = mix(prev, col, 0.4);
    let alpha = clamp(select(0.84, 0.97, hit) + length(volColor) * 0.1 + totalGlow * 0.1, 0.0, 1.0);
    let depth = select(0.0, clamp(1.0 - t / 25.0, 0.0, 1.0), hit);
    let pix = vec2<i32>(id.xy);
    let outCol = vec4<f32>(finalCol, alpha);
    textureStore(writeTexture, pix, outCol);
    textureStore(writeDepthTexture, pix, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pix, outCol);
}
