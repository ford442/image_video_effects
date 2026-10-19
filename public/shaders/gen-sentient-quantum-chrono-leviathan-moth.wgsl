// ═══════════════════════════════════════════════════════════════════
//  Sentient Quantum-Chrono Leviathan-Moth
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: peristaltic leviathan armor segments; frozen-time wing lamellae; electroreceptor antenna arcs; trailing feather-wake vortices;
//         Beer–Lambert membrane transmission (§12.2F: nebula seen through the crystalline wing, slant-path
//         attenuated, tinted by the refraction offset HEAD computed and dropped);
//         Marey chronophotograph wing ghosts (earlier flap phases traced as fading plates, Chrono Distortion sets exposure)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Wing Span, y=Plasma Intensity, z=Chrono Distortion, w=Nebular Density

// ----------------------------------------------------------------
// Helper functions and Math utilities
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;

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

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D Voronoi / Cellular noise approximation
fn voronoi(p: vec3<f32>) -> f32 {
    let n = floor(p);
    let f = fract(p);
    var res: f32 = 8.0;
    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash3(n + b);
                let d = dot(r, r);
                res = min(res, d);
            }
        }
    }
    return sqrt(res);
}

fn fbm(p: vec3<f32>) -> f32 {
    var value: f32 = 0.0;
    var amp: f32 = 0.5;
    var pp = p;
    for(var i = 0; i < 4; i++) {
        value += amp * (voronoi(pp) * 2.0 - 1.0);
        pp *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// ----------------------------------------------------------------
// SDFs
// ----------------------------------------------------------------

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Gyroid for nebula
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let pp = p * scale;
    return abs(dot(sin(pp), cos(pp.zxy)) + bias) / scale - thickness;
}

// Mouse rotation (acts as gravitational chronal anomaly): world -> moth frame
fn mothFrame(pos: vec3<f32>) -> vec3<f32> {
    var p = pos;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let rotXZ = rot(mouse.x * PI) * p.xz;
    p.x = rotXZ.x;
    p.z = rotXZ.y;
    let rotYZ = rot(-mouse.y * PI) * p.yz;
    p.y = rotYZ.x;
    p.z = rotYZ.y;
    return p;
}

fn flapAt(time: f32, audio: f32) -> f32 {
    let flapSpeed = 4.0 + audio * 10.0;
    return sin(time * flapSpeed) * 0.5 * (1.0 + audio);
}

// Moth frame -> wing frame (mirrored, flapped, offset from the body)
fn wingLocal(pm: vec3<f32>, flapAngle: f32) -> vec3<f32> {
    var pWings = pm;
    pWings.x = abs(pWings.x); // Symmetry
    let rotXY = rot(flapAngle) * pWings.xy;
    pWings.x = rotXY.x;
    pWings.y = rotXY.y;
    pWings.x -= u.zoom_params.x * 0.5; // Offset from body
    return pWings;
}

// Moth mapping
fn map(pos: vec3<f32>) -> vec2<f32> {
    let p = mothFrame(pos);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let audio = bass;

    var dMain = 1e10;
    var matID = 0.0; // 1.0 = Body, 2.0 = Wings

    // Body (Capsule with displacement)
    var pBody = p;
    let bodyRadius = 0.3 + 0.05 * sin(time * 2.0 + pBody.z * 5.0);
    var dBody = sdCapsule(pBody, vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, 0.0, -1.0), bodyRadius);
    // Fractal displacement
    dBody -= 0.1 * fbm(pBody * 4.0 + time * 0.5);
    // Peristaltic leviathan armor segments along the capsule axis
    let segPhase = pBody.z * 3.2 + time * 1.1 + mids;
    let armorGroove = 0.018 * (0.5 + 0.5 * sin(segPhase));
    dBody -= armorGroove;

    // Wings
    let wingSpan = u.zoom_params.x;
    let chronoDistortion = u.zoom_params.z;
    var pWings = wingLocal(p, flapAt(time, audio));

    // Chrono distortion ripples bend the membrane (HEAD thinned a 0.01 plate
    // by up to 0.045 here and below, which ate the wings down to ring outlines).
    pWings.y -= chronoDistortion * 0.05 * sin(length(pWings.xz) * 20.0 - time * 10.0);

    // Wing shape (thin flat SDF with Voronoi)
    var dWings = sdBox(pWings, vec3<f32>(wingSpan * 0.5, 0.025, wingSpan * 0.6));

    // Wing pattern/crystalline structure
    let wingNoise = voronoi(pWings * 8.0 - vec3<f32>(0.0, 0.0, time * 2.0));
    dWings += 0.012 * wingNoise;
    // Frozen-time wing lamellae: closely spaced chrono-phase strata
    let lamella = sin(length(pWings.xz) * 28.0 - time * 4.0 + chronoDistortion * 6.0);
    dWings += chronoDistortion * 0.012 * lamella;

    // Combine
    if (dBody < dWings) {
        dMain = dBody;
        matID = 1.0;
    } else {
        dMain = dWings;
        matID = 2.0;
    }

    // Smooth merge slightly
    dMain = smin(dBody, dWings, 0.2);
    if(dBody - 0.1 < dWings) { matID = 1.0; } else { matID = 2.0; } // approx

    return vec2<f32>(dMain, matID);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

// Blackbody color map
fn blackbody(temp: f32) -> vec3<f32> {
    let t = temp * 4000.0;
    var color = vec3<f32>(0.0);
    if (t < 1000.0) {
        color = vec3<f32>(t/1000.0, 0.0, 0.0);
    } else if (t < 2000.0) {
        color = vec3<f32>(1.0, (t-1000.0)/1000.0, 0.0);
    } else {
        color = vec3<f32>(1.0, 1.0, (t-2000.0)/2000.0);
    }
    // Shift color for neon pink/cyan bioluminescence
    return color.zyx + vec3<f32>(0.2, 0.0, 0.5) * temp;
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= dim.x || f32(id.y) >= dim.y) { return; }
    let uv = vec2<f32>(id.xy) / dim;
    let ndc = (uv * 2.0 - 1.0) * vec2<f32>(1.0, -1.0); // y up (HEAD was upside-down)
    let aspect = dim.x / dim.y;

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass;
    let held = f32(u.zoom_config.w > 0.5);
    let wingSpan = u.zoom_params.x;

    // Camera: raised 3/4 view onto the wing planes (HEAD sat almost edge-on)
    let ro = vec3<f32>(0.0, 2.2, -3.6);
    let ww = normalize(vec3<f32>(0.0, 0.0, 0.3) - ro);
    let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
    let vv = cross(ww, uu);
    let rd = normalize(ndc.x * aspect * uu + ndc.y * vv + 1.5 * ww);
    let chrono = u.zoom_params.z;

    // Background / Nebula
    var col = vec3<f32>(0.0);
    let nebDensity = u.zoom_params.w;

    // Raymarching Moth
    var t = 0.0;
    var d = 0.0;
    var matID = 0.0;
    var hit = false;

    var p = ro;

    // ── Idea: Marey chronophotograph wing ghosts ──
    // Earlier flap phases are traced along the primary ray as faint plates,
    // like Marey's photographic gun fixing successive wing positions on one
    // plate. Older exposures fade; Chrono Distortion sets the exposure.
    var ghost = vec3<f32>(0.0);
    let ghostTint = array<vec3<f32>, 3>(
        vec3<f32>(0.45, 0.8, 1.0), vec3<f32>(0.6, 0.5, 1.0), vec3<f32>(0.9, 0.4, 0.9));

    for(var i = 0; i < 110; i++) {
        p = ro + rd * t;
        let res = map(p);
        d = res.x;
        matID = res.y;

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        if (t < 8.0) {
            let pm = mothFrame(p);
            for (var k = 1; k <= 3; k++) {
                let fk = f32(k);
                let gw = wingLocal(pm, flapAt(time - fk * 0.09, audio));
                let gd = sdBox(gw, vec3<f32>(wingSpan * 0.5, 0.01, wingSpan * 0.6));
                ghost += ghostTint[k - 1] * exp(-max(gd, 0.0) * 25.0) * min(d * 0.8, 0.15) * (1.0 - fk * 0.25) * 5.0;
            }
        }
        t += d * 0.8;
    }

    var glow = 0.0; // Plasma dust glow
    var wingTrans = 0.0;
    var wingTint = vec3<f32>(0.0);

    // Shading
    if (hit) {
        let n = calcNormal(p);
        let v = -rd;

        if (matID == 1.0) {
            // Body: Metallic and reflective
            let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let h = normalize(l + v);
            let diff = max(dot(n, l), 0.0);
            let spec = pow(max(dot(n, h), 0.0), 32.0);
            let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            col = vec3<f32>(0.1, 0.15, 0.2) * diff + spec * 0.5 + fresnel * vec3<f32>(0.2, 0.4, 0.5);
            col += 0.1 * fbm(p * 10.0) * vec3<f32>(0.0, 1.0, 0.5);
            let seam = 0.5 + 0.5 * sin(p.z * 3.2 + time * 1.1 + mids);
            col += vec3<f32>(0.15, 0.85, 0.7) * pow(seam, 8.0) * 0.55;
            // Idea 3: electroreceptor antenna arcs near the forward snout.
            let snout = smoothstep(0.2, 1.2, p.z) * exp(-abs(p.x) * 7.0) * exp(-abs(p.y - 0.15) * 10.0);
            let arc = pow(0.5 + 0.5 * sin(atan2(p.y, p.x + 1e-4) * 12.0 + time * (7.0 + treble * 4.0)), 6.0);
            col += vec3<f32>(0.55, 0.95, 1.0) * snout * arc * (0.18 + treble * 0.2);
        } else {
            // Wings: Crystalline and refractive
            let l = normalize(vec3<f32>(0.0, -1.0, 0.0));
            let diff = max(dot(n, l), 0.0);
            let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);

            // Faux refraction
            let refrRd = refract(rd, n, 0.8);
            // Sample nebula background slightly shifted
            let bgShift = sdGyroid(p + refrRd * 0.5, 2.0, 0.05, time) * 0.1;

            let baseColor = vec3<f32>(0.2, 0.6, 1.0);
            col = mix(baseColor, vec3<f32>(1.0, 0.5, 0.8), audio);
            col *= (0.45 + diff * 0.3) + fresnel * 0.5;

            // Glowing lines
            let wingGlow = smoothstep(0.4, 0.5, voronoi(p * 15.0));
            col += wingGlow * vec3<f32>(0.5, 1.0, 1.0) * u.zoom_params.y;
            let chronoDistortion = u.zoom_params.z;
            let lamA = 0.5 + 0.5 * sin(length(p.xz) * 28.0 - time * 4.0);
            let lamB = 0.5 + 0.5 * sin(length(p.xz) * 28.0 - time * 4.0 + 2.1);
            col += vec3<f32>(lamA, 0.2, lamB) * chronoDistortion * fresnel * 0.45;
            // Lamella crests catch light at any angle so the strata edges read.
            col += vec3<f32>(0.45, 0.85, 1.0) * pow(lamA, 12.0) * (0.15 + chronoDistortion * 0.6);

            // ── Idea: Beer–Lambert membrane transmission ──
            // The membrane is thin crystal: the nebula behind it shows through,
            // attenuated by the slant path length (~55% absorbed head-on) and tinted by the refraction
            // offset above. Applied once the nebula volume is integrated.
            wingTrans = exp(-0.05 * 16.0 / max(abs(dot(n, rd)), 0.12)); // ~55% absorbed at normal incidence
            wingTint = mix(vec3<f32>(0.55, 0.95, 1.0), vec3<f32>(1.0, 0.55, 0.9), 0.5 + 0.5 * sin(bgShift * 40.0 + time));

            // Shedding dust (approximated along trailing axis)
            glow += 0.5 * u.zoom_params.y * smoothstep(0.0, 1.0, p.z);
        }
    }

    // Volumetric Nebula and Plasma Trails
    var vT = 0.0;
    var vCol = vec3<f32>(0.0);
    for(var i = 0; i < 50; i++) {
        let vp = ro + rd * vT;
        let g = sdGyroid(vp, 1.5, 0.03, sin(time * 0.2));

        var density = smoothstep(0.1, 0.0, g) * nebDensity * 0.05;
        // Add color based on depth and audio
        let vColor = mix(vec3<f32>(0.0, 0.1, 0.2), vec3<f32>(0.4, 0.0, 0.3), fract(vT * 0.1 + audio * 0.5));

        vCol += density * vColor;

        // Quantum Dust / Plasma trail behind the moth
        let trailMask = smoothstep(2.0, 0.0, length(vp.xy)) * smoothstep(-1.0, 5.0, vp.z);
        let dustNoise = fbm(vp * 5.0 - vec3<f32>(0.0, 0.0, time * 5.0));
        var dustDens = smoothstep(0.6, 1.0, dustNoise) * trailMask;

        // Mouse click/drag interaction increases dust
        let dustColor = blackbody(max(dustNoise * 2.0 * u.zoom_params.y, 0.0));
        vCol += dustDens * dustColor * 0.2 * (1.0 + held * 1.5 + treble * 0.4);
        // Idea 4: feather-like wake vortices shed from the trailing wing span.
        let wakeRadius = length(vp.xy) - (0.35 + wingSpan * 0.2 + 0.12 * sin(vp.z * 2.4 + time * 2.8));
        let wake = exp(-wakeRadius * wakeRadius * 14.0) * smoothstep(-2.0, 4.0, vp.z);
        let feather = pow(0.5 + 0.5 * sin(vp.z * 8.0 - time * 6.0 + vp.x * 3.0), 3.0);
        vCol += vec3<f32>(0.2, 0.75, 1.0) * wake * feather * (0.05 + mids * 0.08);

        vT += 0.2 + hash3(vp).x * 0.1; // Dithered stepping
        if (vT > 20.0) { break; }
    }

    col = col * (1.0 - wingTrans * 0.5) + vCol * wingTint * wingTrans * 1.4;
    if (!hit) {
        col = vCol;
    } else {
        col = mix(col, vCol, 1.0 - exp(-t * 0.05)); // Fog blend
    }

    col += glow * vec3<f32>(0.1, 0.5, 1.0);
    col += ghost * (0.25 + chrono * 1.5) * u.zoom_params.y * 0.5;

    // Post-processing
    col = acesToneMap(col);
    // Nebula backdrop is part of the scene: HEAD's 0.16 miss alpha washed it out on light pages.
    let alpha = clamp(select(0.8, 0.92, hit) + length(vCol) * 0.1 + glow * 0.05 + length(ghost) * 0.1, 0.8, 1.0);
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    let pix = vec2<i32>(id.xy);
    let outCol = vec4<f32>(col, alpha);
    textureStore(writeTexture, pix, outCol);
    textureStore(writeDepthTexture, pix, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pix, outCol);
}
