// ═══════════════════════════════════════════════════════════════════
//  Prismatic Cyber-Chrono Nebula-Peacock
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: barbule thin-film interference (keratin film, per-wavelength phase) on feather vanes; zoned ocellus eye-spots (pupil / cobalt / bronze / teal / gold halo); rachis-barb branching shafts; chrono-precession ocellus halos; coronet crest aigrette quills with pennant bulbs; melanin 2D photonic-crystal rod-lattice Bragg shift & chrono-afterimage trail
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Plumage Spread, y=Quantum Glass Refraction, z=Nebula Density, w=Audio Reactivity

// ----------------------------------------------------------------
// CONSTANTS & HELPERS
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for Nebula
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// SDFs
// ----------------------------------------------------------------
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCylinder(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// ----------------------------------------------------------------
// MAPPING & DOMAIN WARPING
// ----------------------------------------------------------------

// Mouse Interaction (Gravitational Singularity); held mouse deepens the well.
fn gravityWarp(pos: vec3<f32>) -> vec3<f32> {
    var p = pos;
    let time = u.config.x;
    let mx = (u.zoom_config.y * 2.0 - 1.0) * (u.config.z / u.config.w);
    let my = (1.0 - u.zoom_config.z * 2.0);
    let held = select(1.0, 2.2, u.zoom_config.w > 0.5);

    let mouseDist = length(p.xy - vec2<f32>(mx, my));
    let gravity = exp(-mouseDist * 2.0) * 0.5 * held;

    p.x += sin(time * 0.5 + p.y) * gravity;
    p.y += cos(time * 0.5 + p.x) * gravity;
    return p;
}

// Idea 5: Coronet crest aigrettes — a fan of 7 slender spatula-tipped quills atop the head.
fn sdCrestAigrettes(bodyP: vec3<f32>, time: f32, shiver: f32) -> vec2<f32> {
    let base = bodyP - vec3<f32>(0.0, 1.12, 0.30);
    let fanAngle = clamp(atan2(base.x, max(base.y, 0.001)), -0.75, 0.75);
    let quillCount = 7.0;
    let sector = 1.5 / quillCount;
    let snapped = clamp(round(fanAngle / sector), -3.0, 3.0) * sector;
    let sway = (0.04 + shiver * 0.03) * sin(time * 3.8 + snapped * 9.0);
    let dir = normalize(vec3<f32>(sin(snapped + sway), cos(snapped + sway), -0.15));
    let quillLen = 0.38;
    let h = clamp(dot(base, dir), 0.0, quillLen);
    let dShaft = length(base - dir * h) - mix(0.014, 0.007, h / quillLen);
    let tipCenter = dir * quillLen;
    let tipLocal = (base - tipCenter) * vec3<f32>(1.2, 0.85, 2.2);
    let dBulb = length(tipLocal) - 0.042;
    let dCrest = smin(dShaft, dBulb, 32.0);
    let bulbGlow = 0.004 / (dBulb * dBulb + 0.0015);
    return vec2<f32>(dCrest, bulbGlow);
}

// Fractal plumage fold (shared by map and the ocellus shading).
// shiver = click-ripple train-rattle agitation.
fn featherFold(p: vec3<f32>, shiver: f32) -> vec3<f32> {
    let time = u.config.x;
    let plumageSpread = u.zoom_params.x;

    var tailP = p;
    tailP.y -= 0.5; // Offset to attach to body

    // Rotate tail based on spread
    var temp_yz2 = rot(-0.5 - plumageSpread * 0.5) * tailP.yz;
    tailP.y = temp_yz2.x;
    tailP.z = temp_yz2.y;

    // Polar domain repetition for the feathers
    let angle = atan2(tailP.x, tailP.y);
    let r = length(tailP.xy);

    let featherCount = 12.0 + plumageSpread * 8.0;
    let sector = (2.0 * PI) / featherCount;
    let aMod = (fract(angle / sector + 0.5) - 0.5) * sector;

    tailP.x = r * sin(aMod);
    tailP.y = r * cos(aMod);

    var foldP = tailP;
    for (var i = 0; i < 4; i++) {
        foldP.x = abs(foldP.x) - 0.1 * (1.0 + plumageSpread);
        foldP.z = abs(foldP.z) - 0.05;

        let rattle = shiver * sin(time * 23.0 + f32(i) * 1.7) * 0.07;
        var temp_xy = rot(0.2 + sin(time * 0.2 + f32(i)) * 0.1 + rattle) * foldP.xy;
        foldP.x = temp_xy.x;
        foldP.y = temp_xy.y;
    }
    return foldP;
}

// Returns vec3: x=distance, y=material_id, z=glow_intensity
fn map(pos: vec3<f32>, audio: f32, shiver: f32) -> vec3<f32> {
    let time = u.config.x;
    let p = gravityWarp(pos);

    // --- Core Body (Quantum Glass) ---
    var bodyP = p;
    bodyP.y += sin(time * 0.3) * 0.1; // Gentle bobbing
    var temp_xz = rot(time * 0.1) * bodyP.xz;
    bodyP.x = temp_xz.x;
    bodyP.z = temp_xz.y;

    var dBody = sdCylinder(bodyP, vec2<f32>(0.2, 0.8));
    var temp_yz = rot(0.2) * bodyP.yz;
    bodyP.y = temp_yz.x;
    bodyP.z = temp_yz.y;
    dBody = smin(dBody, sdSphere(bodyP - vec3<f32>(0.0, 0.9, 0.3), 0.25), 8.0); // Head

    let crestInfo = sdCrestAigrettes(bodyP, time, shiver);
    let dCrest = crestInfo.x;

    // --- Fractal Plumage (Feathers) ---
    let foldP = featherFold(p, shiver);

    // Tiny 'eye-spots' inside the fractal
    let eyeDist = sdSphere(foldP - vec3<f32>(0.0, 0.5, 0.0), 0.05 + audio * 0.05);
    let glow = 0.01 / (eyeDist * eyeDist + 0.001) * audio + crestInfo.y * (0.25 + audio * 0.5);

    let dTail = sdBox(foldP, vec3<f32>(0.05, 1.5, 0.02));

    var d = min(dBody, dTail);
    var mat = 0.0; // 0 for body, 1 for feathers, 2 for coronet crest aigrettes
    if (dTail < dBody) {
        mat = 1.0;
    }
    if (dCrest < d) {
        d = dCrest;
        mat = 2.0;
    }

    return vec3<f32>(d, mat, glow);
}

fn getNormal(p: vec3<f32>, audio: f32, shiver: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, audio, shiver).x - map(p - e.xyy, audio, shiver).x,
        map(p + e.yxy, audio, shiver).x - map(p - e.yxy, audio, shiver).x,
        map(p + e.yyx, audio, shiver).x - map(p - e.yyx, audio, shiver).x
    ));
}

// ----------------------------------------------------------------
// NATIVE IDEA 1: barbule thin-film interference
// Peacock barbules are keratin films over melanin rod lattices; colour comes
// from path difference 2·n·d·cosθt, per wavelength. Film thickness varies
// along the vane so colour bands sweep as the feather tilts to the view.
// ----------------------------------------------------------------
fn barbuleThinFilm(foldP: vec3<f32>, n: vec3<f32>, v: vec3<f32>, mids: f32) -> vec3<f32> {
    let nFilm = 1.56; // keratin
    let cosI = clamp(abs(dot(n, v)), 0.0, 1.0);
    let sinT2 = (1.0 - cosI * cosI) / (nFilm * nFilm);
    let cosT = sqrt(max(1.0 - sinT2, 0.0));
    let thickness = 330.0 + 150.0 * (0.5 + 0.5 * sin(foldP.y * 7.0 + u.config.x * (0.3 + mids * 0.6)))
                  + 40.0 * u.zoom_params.x;
    let opd = 2.0 * nFilm * thickness * cosT;
    let lambda = vec3<f32>(650.0, 530.0, 450.0);
    return 0.5 + 0.5 * cos(2.0 * PI * opd / lambda);
}

// ----------------------------------------------------------------
// NATIVE IDEA 2: zoned ocellus (eye-spot)
// Real peacock ocelli are concentric structural-colour zones: dark pupil,
// cobalt heart, bronze ring, teal-green ring, golden-brown halo.
// ----------------------------------------------------------------
fn ocellusZones(foldP: vec3<f32>, audio: f32) -> vec4<f32> {
    let scale = 1.0 + clamp(audio, 0.0, 2.0) * 0.35;
    let e = length(vec2<f32>(foldP.x, (foldP.y - 0.5) * 0.55)) / scale;
    let pupil  = vec3<f32>(0.01, 0.02, 0.10);
    let cobalt = vec3<f32>(0.05, 0.20, 1.00);
    let bronze = vec3<f32>(0.75, 0.42, 0.12);
    let teal   = vec3<f32>(0.00, 0.85, 0.55);
    let gold   = vec3<f32>(1.00, 0.80, 0.25);
    var c = mix(pupil, cobalt, smoothstep(0.012, 0.020, e));
    c = mix(c, bronze, smoothstep(0.028, 0.034, e));
    c = mix(c, teal, smoothstep(0.040, 0.046, e));
    c = mix(c, gold, smoothstep(0.054, 0.062, e));
    let mask = 1.0 - smoothstep(0.070, 0.085, e);
    return vec4<f32>(c, mask);
}

// Idea 3: central rachis with branching barbs across each folded feather vane.
fn rachisBarbs(foldP: vec3<f32>, time: f32) -> f32 {
    let rachis = smoothstep(0.055, 0.012, abs(foldP.x));
    let barbCarrier = foldP.x - 0.16 * sin(foldP.y * 15.0 + time * 0.6);
    let barbs = smoothstep(0.06, 0.016, abs(barbCarrier)) * smoothstep(0.18, 1.35, abs(foldP.y));
    return max(rachis, barbs * 0.75);
}

// Idea 4: ocellus halo precession rotating around each eye-spot.
fn ocellusHalo(foldP: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let center = vec2<f32>(foldP.x, (foldP.y - 0.5) * 0.55);
    let radius = length(center);
    let angle = atan2(center.y, center.x);
    let ring = exp(-pow((radius - 0.078) * 95.0, 2.0));
    let precess = 0.5 + 0.5 * cos(angle * 7.0 - time * (1.4 + audio * 2.2));
    let haloCol = mix(vec3<f32>(0.15, 0.95, 0.85), vec3<f32>(1.0, 0.72, 0.25), precess);
    return haloCol * ring * (0.35 + audio * 0.4);
}

// Idea 6: 2D melanin photonic-crystal rod-lattice Bragg shift across barbule tilt angle.
fn braggRodLattice(foldP: vec3<f32>, n: vec3<f32>, v: vec3<f32>, treble: f32) -> vec3<f32> {
    let nEff = 1.72; // keratin + melanin rod composite effective index
    let cosTheta = clamp(abs(dot(n, v)), 0.05, 1.0);
    // Lattice pitch (145..185 nm) modulates across the feather vane
    let pitchNm = 162.0 + 22.0 * sin(foldP.x * 38.0) * cos(foldP.y * 24.0);
    let braggLambda = 2.0 * nEff * pitchNm * sqrt(max(1.0 - 0.28 * (1.0 - cosTheta * cosTheta), 0.1));
    let delta = (vec3<f32>(630.0, 525.0, 455.0) - vec3<f32>(braggLambda)) / 52.0;
    let order1 = exp(-delta * delta);
    // Azimuthal rod-lattice polarization cross-term
    let rodGrating = 0.5 + 0.5 * cos(foldP.x * 140.0 + atan2(n.y, n.x) * 4.0);
    return order1 * (0.55 + 0.45 * rodGrating) * (1.0 + treble * 0.35);
}

// ----------------------------------------------------------------
// NEBULA / VOLUMETRICS
// ----------------------------------------------------------------
fn nebulaFBM(p: vec3<f32>) -> f32 {
    var q = p;
    var f = 0.0;
    var a = 0.5;
    for (var i = 0; i < 4; i++) {
        let h = hash33(floor(q));
        let fr = fract(q);
        let sm = fr * fr * (3.0 - 2.0 * fr);
        // extremely crude noise approximation
        let val = mix(
            mix(mix(h.x, hash33(floor(q) + vec3<f32>(1.,0.,0.)).x, sm.x),
                mix(hash33(floor(q) + vec3<f32>(0.,1.,0.)).x, hash33(floor(q) + vec3<f32>(1.,1.,0.)).x, sm.x), sm.y),
            mix(mix(hash33(floor(q) + vec3<f32>(0.,0.,1.)).x, hash33(floor(q) + vec3<f32>(1.,0.,1.)).x, sm.x),
                mix(hash33(floor(q) + vec3<f32>(0.,1.,1.)).x, hash33(floor(q) + vec3<f32>(1.,1.,1.)).x, sm.x), sm.y), sm.z);

        f += a * val;
        q = q * 2.0;
        a *= 0.5;
    }
    return f;
}

// ----------------------------------------------------------------
// MAIN COMPUTE
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let coord = vec2<i32>(id.xy);
    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    // Upright screen coordinates (+y = world up so head & fanned train stand upright)
    let uv = vec2<f32>((fragCoord.x * 2.0 - res.x) / res.y, (res.y - fragCoord.y * 2.0) / res.y);
    let aspect = res.x / res.y;

    let time = u.config.x;

    // Audio (plasmaBuffer), gained by the Audio Reactivity slider
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let audioGain = u.zoom_params.w;
    let audio = audioGain * (0.35 + bass * 0.65 + mids * 0.2);

    // Parameters
    let ior = u.zoom_params.y;
    let nebDensity = u.zoom_params.z;

    // Click ripples: expanding display rings that make the train rattle
    var shiver = 0.0;
    var ringGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var k = 0u; k < rippleCount; k++) {
        let rp = u.ripples[k];
        let age = time - rp.z;
        if (age < 0.0 || age > 3.0) {
            continue;
        }
        let rc = vec2<f32>((rp.x * 2.0 - 1.0) * aspect, 1.0 - rp.y * 2.0);
        let rd2 = length(uv - rc);
        let front = abs(rd2 - age * 0.9);
        let fade = 1.0 - age / 3.0;
        let band = exp(-front * front * 60.0) * fade;
        ringGlow += band;
        shiver += band * 2.0 + exp(-rd2 * 1.5) * fade * 0.5;
    }
    shiver = min(shiver, 3.0);

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.5));

    // Raymarch
    var t = 0.0;
    var dInfo = vec3<f32>(0.0);
    var hit = false;
    var totalGlow = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        dInfo = map(p, audio, shiver);
        totalGlow += dInfo.z;
        if (dInfo.x < SURF_DIST) {
            hit = true;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += dInfo.x;
    }

    var col = vec3<f32>(0.0);

    // Volumetric Nebula Background (simplified)
    var nebAcc = 0.0;
    for (var i = 0; i < 5; i++) {
        let np = ro + rd * (t + f32(i) * 0.5);
        nebAcc += nebulaFBM(np + time * 0.1) * nebDensity;
    }
    let nebAvg = nebAcc / 5.0;
    col += vec3<f32>(0.1, 0.3, 0.6) * nebAvg * (1.0 + bass * audioGain * 0.4);

    var alpha = clamp(nebAvg * 0.45 + treble * 0.03, 0.03, 0.6);
    var depth = 0.0;

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p, audio, shiver);
        let v = -rd;

        let lightPos = vec3<f32>(2.0, 4.0, -3.0);
        let l = normalize(lightPos - p);

        let diff = max(dot(n, l), 0.0);
        let r = reflect(-l, n);
        let spec = pow(max(dot(v, r), 0.0), 32.0) * (1.0 + treble * 0.4);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        if (dInfo.y < 0.5) {
            // Body: Quantum Glass
            let glassCol = vec3<f32>(0.8, 0.9, 1.0);

            // Fake refraction / chromatic aberration based on IOR param
            let refractDirR = refract(rd, n, 1.0 / ior);
            let refractDirG = refract(rd, n, 1.0 / (ior + 0.02));
            let refractDirB = refract(rd, n, 1.0 / (ior + 0.04));

            let bgR = nebulaFBM(p + refractDirR * 2.0);
            let bgG = nebulaFBM(p + refractDirG * 2.0);
            let bgB = nebulaFBM(p + refractDirB * 2.0);

            let refrCol = vec3<f32>(bgR, bgG, bgB) * 2.0;

            col = mix(refrCol, glassCol, fresnel) + spec;
            col *= vec3<f32>(0.5, 0.8, 1.0); // Tint
            alpha = clamp(0.55 + fresnel * 0.35 + spec * 0.1, 0.0, 1.0);
        } else if (dInfo.y > 1.5) {
            // Coronet crest aigrettes: golden quill stems with iridescent turquoise pennant bulbs
            let crestPhase = 0.5 + 0.5 * cos(p.y * 18.0 - time * 2.5);
            let aigretteCol = mix(vec3<f32>(0.05, 0.92, 0.82), vec3<f32>(1.0, 0.84, 0.28), crestPhase);
            col = aigretteCol * (0.45 + diff * 0.85) + spec * vec3<f32>(1.0, 0.9, 0.55) * 1.4 + fresnel * vec3<f32>(0.2, 0.95, 1.0);
            alpha = clamp(0.82 + fresnel * 0.18, 0.0, 1.0);
        } else {
            // Feathers: Iridescent Metallic + 2D Melanin Rod-Lattice Bragg Shift
            let iridMix = fract(length(p) * 2.0 - time);
            let baseCol = mix(vec3<f32>(0.0, 0.8, 0.8), vec3<f32>(0.8, 0.0, 0.8), iridMix); // Teal to Magenta

            let foldP = featherFold(gravityWarp(p), shiver);
            let film = barbuleThinFilm(foldP, n, v, mids);
            let bragg = braggRodLattice(foldP, n, v, treble);
            let shafts = rachisBarbs(foldP, time);
            let halo = ocellusHalo(foldP, time, audio);
            let structural = mix(baseCol, (film * 0.65 + bragg * 0.55) * vec3<f32>(0.6, 0.95, 1.0), 0.58);

            col = structural * diff + spec * vec3<f32>(1.0, 0.8, 0.4) + fresnel * (film + bragg * 0.5);
            col = mix(col, col * vec3<f32>(0.6, 0.75, 0.55), shafts * 0.35);
            col += vec3<f32>(0.95, 0.82, 0.35) * shafts * 0.12;

            let oc = ocellusZones(foldP, audio);
            col = mix(col, oc.rgb * (0.35 + diff * 0.9) + fresnel * oc.rgb, oc.a * 0.85);
            col += halo;
            alpha = clamp(0.7 + diff * 0.2 + oc.a * 0.1, 0.0, 1.0);
        }
        depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    }

    // Add eye-spot & crest pennant glow
    let eyeGlow = totalGlow * 0.05;
    col += vec3<f32>(1.0, 0.8, 0.2) * eyeGlow;

    // Click rings: structural gold/teal display flash
    col += mix(vec3<f32>(0.0, 0.9, 0.7), vec3<f32>(1.0, 0.8, 0.3), 0.5 + 0.5 * sin(time * 4.0)) * ringGlow * 0.6;

    alpha = clamp(alpha + eyeGlow * 0.15 + ringGlow * 0.3, 0.0, 1.0);

    // Chrono-afterimage trail from exact dataTextureC feedback
    let chronoAfterimage = textureLoad(dataTextureC, coord, 0).rgb;
    col = mix(col, chronoAfterimage * vec3<f32>(0.92, 0.97, 1.03), 0.07 + mids * 0.04);

    // Tone mapping (ACES)
    col = acesToneMap(col * (1.0 + bass * audioGain * 0.1));

    let finalColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
