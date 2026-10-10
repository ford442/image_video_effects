// ═══════════════════════════════════════════════════════════════════
//  Eldritch-Quantum Fractal-Eye
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, raymarched, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: iris crypts & stroma (radial streaks + crypt lacunae around the pupil, tinted by a KIFS orbit trap); blink (eyelid shell closing on a hashed timer, treble twitches the lids); pupil event-horizon lensing (rays bend toward the pupil axis by dilation, photon ring at the pupil rim)
//  A packing: raw HDR display history RGBA (C mixed back via exact textureLoad; ACES on display only)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Fractal Detail, y=Pupil Dilation, z=Plasma Density, w=Chromatic Shift

const TAU: f32 = 6.28318530718;
const EYE_R: f32 = 2.5;
const LID_R: f32 = 2.62;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

// Math/Hash functions
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p_mut = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                          dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                          dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(p_mut) * 43758.5453123);
}

fn hash11(x: f32) -> f32 {
    return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

// Voronoi 3D
fn voronoi3D(x: vec3<f32>) -> vec2<f32> {
    let p = floor(x);
    let f = fract(x);
    var res = vec2<f32>(8.0, 8.0);
    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash3(p + b);
                let d = dot(r, r);
                if(d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if(d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// The eyeball's gaze rotation (same order as HEAD's sdfEye).
fn gazeRotate(p: vec3<f32>, mouseRotX: mat2x2<f32>, mouseRotY: mat2x2<f32>) -> vec3<f32> {
    var p_rot = p;
    let yz = mouseRotX * p_rot.yz;
    p_rot.y = yz.x; p_rot.z = yz.y;
    let xz = mouseRotY * p_rot.xz;
    p_rot.x = xz.x; p_rot.z = xz.y;
    return p_rot;
}

struct EyeHit {
    d: f32,
    trap: f32,   // KIFS orbit trap (min |z|² over the fold orbit)
    lid: f32,    // 1 when the eyelid shell is the closest surface
};

// lidOpen: half-height of the eyelid opening in world y (Idea 2)
fn sdfEye(p: vec3<f32>, mouseRotX: mat2x2<f32>, mouseRotY: mat2x2<f32>, dilation: f32, iters: i32, lidOpen: f32) -> EyeHit {
    // Basic sphere bounds
    let p_rot = gazeRotate(p, mouseRotX, mouseRotY);

    let r = length(p_rot);
    let sphereDist = r - EYE_R;

    // Pupil singularity
    let pupilDist = length(p_rot.xy) - (0.3 + dilation * 0.5);

    // KIFS Fractal Iris
    var z = p_rot;
    var scale = 1.0;
    var trap = 1e3;
    for(var i = 0; i < iters; i++) {
        z = abs(z) - vec3<f32>(0.2, 0.2, 0.2);
        let r2 = dot(z, z);
        trap = min(trap, r2); // Idea 1: orbit trap for iris tint
        let k = max(1.2 / max(r2, 1e-4), 1.0);
        z *= k;
        scale *= k;
    }
    let fractalDist = length(z) / scale - 0.05;

    let eyeD = max(sphereDist, min(fractalDist, pupilDist));

    // Idea 2: eyelids — a thin shell over the eyeball, cut open by a band
    // |y| < lidOpen. Lids do not follow the gaze (world y, not p_rot).
    let shell = abs(length(p) - LID_R) - 0.06;
    let lidD = max(shell, lidOpen - abs(p.y));

    var h: EyeHit;
    h.d = min(eyeD, lidD);
    h.trap = trap;
    h.lid = select(0.0, 1.0, lidD < eyeD);
    return h;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv01 = (vec2<f32>(global_id.xy) + vec2<f32>(0.5)) / res;
    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;

    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x; // 0 to 1
    let audioMids = plasmaBuffer[0].y;
    let audioTreble = plasmaBuffer[0].z;
    let mouseDown = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Sliders
    let fractalIters = i32(3.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 6.0);
    let dilationIntensity = clamp(u.zoom_params.y, 0.0, 1.0);
    let plasmaDensity = mix(1.5, 7.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let colorShift = clamp(u.zoom_params.w, 0.0, 1.0);

    // Sentient mouse tracking
    // Map mouse [-1, 1]
    let pointerWeight = mix(0.2, 1.0, mouseDown);
    let mx = (u.zoom_config.y * 2.0 - 1.0) * pointerWeight;
    let my = (u.zoom_config.z * 2.0 - 1.0) * pointerWeight;
    // Simple rotation based on mouse
    let rotX = rotate2D(my * 1.5);
    let rotY = rotate2D(mx * 1.5);

    // Dilation: the slider sets the rest size, bass and a held click open it further.
    let dilation = dilationIntensity * 0.6 + audioBass * (0.2 + dilationIntensity * 0.4) + mouseDown * 0.5;
    let pupilR = 0.3 + dilation * 0.5;

    // Idea 2: blink timer — one hashed blink per ~4.5 s cycle, treble twitches the lids.
    let cycle = floor(time / 4.5);
    let ph = fract(time / 4.5);
    let blinkAt = 0.15 + hash11(cycle) * 0.7;
    let blinkW = 0.035;
    let blinkX = clamp(1.0 - abs(ph - blinkAt) / blinkW, 0.0, 1.0);
    let closure = max(blinkX * blinkX * (3.0 - 2.0 * blinkX), clamp(audioTreble, 0.0, 1.0) * 0.3);
    let lidOpen = mix(2.25, -0.05, closure);

    // Raymarching setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Idea 3: pupil event-horizon lensing. The pupil axis in world space is the
    // gaze-rotated z axis; rays bend toward it with strength ∝ dilation.
    let ex = gazeRotate(vec3<f32>(1.0, 0.0, 0.0), rotX, rotY);
    let ey = gazeRotate(vec3<f32>(0.0, 1.0, 0.0), rotX, rotY);
    let ez = gazeRotate(vec3<f32>(0.0, 0.0, 1.0), rotX, rotY);
    let axisW = normalize(vec3<f32>(ex.z, ey.z, ez.z)); // transpose row = inverse rotation
    let closest = ro + rd * max(-dot(ro, rd), 0.0);
    let perp = closest - axisW * dot(closest, axisW);
    let impact = length(perp);
    let lensK = dilation * 0.05;
    let bend = min(lensK / (impact * impact + 0.2), 0.2);
    rd = normalize(rd - perp / max(impact, 1e-3) * bend * smoothstep(0.0, 0.15, impact));

    var t = 0.0;
    let max_t = 15.0;
    var steps = 0;
    var p = vec3<f32>(0.0);
    var hitInfo: EyeHit;

    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        hitInfo = sdfEye(p, rotX, rotY, dilation, fractalIters, lidOpen);
        if(hitInfo.d < 0.001 || t > max_t) { break; }
        t += hitInfo.d;
        steps++;
    }

    var finalColor = vec3<f32>(0.0);
    let hit = t < max_t;

    if (hit) {
        // SDF normals so the fractal relief catches the light
        let e = vec2<f32>(0.002, 0.0);
        let n = normalize(vec3<f32>(
            sdfEye(p + e.xyy, rotX, rotY, dilation, fractalIters, lidOpen).d - sdfEye(p - e.xyy, rotX, rotY, dilation, fractalIters, lidOpen).d,
            sdfEye(p + e.yxy, rotX, rotY, dilation, fractalIters, lidOpen).d - sdfEye(p - e.yxy, rotX, rotY, dilation, fractalIters, lidOpen).d,
            sdfEye(p + e.yyx, rotX, rotY, dilation, fractalIters, lidOpen).d - sdfEye(p - e.yyx, rotX, rotY, dilation, fractalIters, lidOpen).d
        ) + vec3<f32>(1e-6));
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);
        let ao = 1.0 - f32(steps) / 100.0;

        var col: vec3<f32>;
        if (hitInfo.lid > 0.5) {
            // Idea 2: eyelid — dark bruised skin, magenta lash line at the lid edge
            let edge = exp(-abs(abs(p.y) - lidOpen) * 18.0);
            col = vec3<f32>(0.14, 0.03, 0.12) * (diff + 0.25) + vec3<f32>(1.0, 0.1, 0.6) * edge * 0.8;
        } else {
            // We hit the eye
            let p_rot = gazeRotate(p, rotX, rotY);
            let v = voronoi3D(p_rot * plasmaDensity + time);
            let plasma = smoothstep(0.1, 0.2, v.y - v.x);

            // Base color
            col = vec3<f32>(0.1, 0.0, 0.3); // Deep abyssal purple

            // Sclera Veins
            col += vec3<f32>(0.0, 1.0, 0.8) * plasma * 2.0; // Bioluminescent cyan
            col += vec3<f32>(0.9, 0.4, 0.0) * audioTreble * plasma * 0.5; // treble-driven sclera sparkle

            let rr = length(p_rot.xy);
            let front = 1.0 - smoothstep(-0.5, 0.5, p_rot.z); // facing the camera

            // Idea 1: iris crypts & stroma in the annulus around the pupil
            let irisR = pupilR + 0.85;
            let irisMask = smoothstep(pupilR, pupilR + 0.05, rr) * (1.0 - smoothstep(irisR - 0.08, irisR, rr)) * front;
            if (irisMask > 0.0) {
                let ang = atan2(p_rot.y, p_rot.x);
                let rn = clamp((rr - pupilR) / (irisR - pupilR), 0.0, 1.0);
                // radial stroma fibers, wavy, slowly drifting with mids
                let fib = abs(sin(ang * 34.0 + sin(ang * 7.0 + rn * 4.0) * 0.8 + time * 0.05 * (1.0 + audioMids)));
                let stroma = 1.0 - smoothstep(0.0, 0.35, fib);
                // crypts: dark lacunae, one per angular sector at a hashed radius
                let secF = ang / TAU * 14.0;
                let sec = floor(secF);
                let cr = 0.35 + hash11(sec) * 0.35;
                let cq = vec2<f32>((fract(secF) - 0.5) * 1.2, (rn - cr) * 3.0);
                let crypt = 1.0 - smoothstep(0.12, 0.3, length(cq));
                // collarette ridge partway out
                let collar = exp(-abs(rn - 0.3) * 30.0);
                // KIFS orbit trap picks the iris pigment
                let trapT = clamp(sqrt(hitInfo.trap) * 2.2, 0.0, 1.0);
                let pigment = mix(vec3<f32>(1.0, 0.55, 0.1), vec3<f32>(0.1, 0.9, 0.7), trapT);
                var iris = pigment * (0.45 + stroma * 0.9) * (1.0 - crypt * 0.75);
                iris += vec3<f32>(1.0, 0.8, 0.4) * collar * 0.6;
                col = mix(col, iris * 1.6, irisMask);
            }

            // Pupil: rotated coordinates and the SDF pupil radius (HEAD used
            // unrotated length(p.xy) against 0.5 + dilation)
            if (rr < pupilR && p_rot.z < 0.0) {
                col = vec3<f32>(1.0, 0.0, 0.5) * (1.0 - rr); // Neon magenta
            }
            // Idea 3: photon ring hugging the pupil rim, brighter with dilation
            col += vec3<f32>(1.0, 0.7, 1.0) * exp(-abs(rr - pupilR) * 40.0) * front * (0.4 + dilation * 1.2);
        }

        col *= (diff * ao + 0.2);

        // Color shift
        col = mix(col, col.zxy, colorShift);

        finalColor = col;
    } else {
        // Volumetric background glow based on distance to pupil axis (dim even without bass)
        let axisDist = length(uv);
        finalColor += vec3<f32>(0.5, 0.0, 1.0) * (0.1 / (axisDist + 0.01)) * (0.08 + audioBass);
        // Idea 3: lensed halo — the event horizon bends a ring of light around the eye
        finalColor += vec3<f32>(0.6, 0.2, 1.0) * exp(-abs(impact - 2.7) * 6.0) * (0.05 + dilation * 0.15);
    }

    var rippleGlow = 0.0;
    let aspect = res.x / max(res.y, 1.0);
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let delta = vec2<f32>((uv01.x - ripple.x) * aspect, uv01.y - ripple.y);
            rippleGlow += exp(-abs(length(delta) - age * 0.23) * 72.0) * exp(-age * 1.4);
        }
    }
    finalColor += vec3<f32>(0.3 + audioMids * 0.4, 0.1, 0.8 + audioTreble * 0.6) * rippleGlow;
    let previous = textureLoad(dataTextureC, coord, 0);
    let hdrColor = clamp(mix(max(finalColor, vec3<f32>(0.0)), previous.rgb, 0.06 + audioBass * 0.07), vec3<f32>(0.0), vec3<f32>(8.0));
    let mappedColor = acesToneMap(hdrColor);
    let luma = dot(mappedColor, vec3<f32>(0.299, 0.587, 0.114));
    let semantic_alpha = clamp(select(0.04, 0.28 + luma * 0.68, hit) + rippleGlow * 0.1, 0.02, 0.98);
    let outDepth = select(0.0, clamp(1.0 - t / max_t, 0.0, 1.0), hit);

    textureStore(writeTexture, global_id.xy, vec4<f32>(mappedColor, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(hdrColor, semantic_alpha));
}
