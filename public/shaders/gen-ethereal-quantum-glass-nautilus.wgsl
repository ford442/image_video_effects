// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Glass Nautilus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-11-08
//  Ideas: chamber septa walls between adjacent spiral chambers; pearl nacre luster on inner chamber ridges; siphuncle canal; aperture lip on the outer chamber; bioluminescent siphon jet; abyssal pressure fractures; Beer-Lambert shell absorption (§12.2F); conchiolin flame stripes along the growth lines; siphon plume cone from the aperture mouth
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .x = Refraction Index, .y = Spiral Tightness, .z = Iridescence Shift, .w = Audio Reactivity

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.005;
const TAU: f32 = 6.28318530718;
// Rescue R2/R4: the shell is finite. The outermost whorl ends in an aperture at centre-line radius SHELL_R
// (growth coordinate kMax = ln(SHELL_R)/b); the whole map is bounded by a sphere of radius BOUND_R.
const SHELL_R: f32 = 1.6;
const BOUND_R: f32 = 2.6;
const FLAME_N: f32 = 16.0;          // flame stripes per whorl (integer: seam-safe)
const PLUME_LEN: f32 = 2.2;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453);
}

fn voronoi(p: vec3<f32>) -> f32 {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
            for (var k = -1; k <= 1; k++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let d = g + o - f;
                let dist = dot(d, d);
                if (dist < md) {
                    md = dist;
                }
            }
        }
    }
    return md;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Log-spiral nautilus map with chamber septa walls (native idea 1).
fn map(p_in: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> f32 {
    var p = p_in;

    let pulse = 1.0 + audioReactive * 0.2 * sin(u.config.x * 2.0);
    p *= 1.0 / pulse;

    let a = atan2(p.z, p.x);
    let r = length(p.xz);

    let b = spiralTightness;
    let theta = log(max(r, 0.001)) / b;

    var n = theta - a / TAU;
    let nf = floor(n);
    let nf1 = nf + 1.0;

    // Rescue R2: the whorl ends at the aperture. kMax is the growth coordinate (turns from the apex) of the
    // last centre-line point; at this angle the outermost EXISTING turn is nfMax. Clamping the turn index
    // keeps the distance a true polar-tube distance (an arc-length cut term overestimates far away and the
    // march jumps over the shell) and leaves the aperture as a step in the outer edge at angle a_m.
    let kMax = log(SHELL_R) / max(b, 0.02);
    let k0 = nf + a / TAU;
    let nfMax = floor(kMax - a / TAU);
    let nfc0 = min(nf, nfMax);
    let nfc1 = min(nf1, nfMax);
    let r0 = exp((nfc0 + a / TAU) * b);
    let r1 = exp((nfc1 + a / TAU) * b);
    let d0 = length(vec2<f32>(r - r0, p.y)) - r0 * 0.4;
    let d1 = length(vec2<f32>(r - r1, p.y)) - r1 * 0.4;

    var d = min(d0, d1);

    // Chamber septa: radial partition walls between adjacent spiral chambers.
    let chamberFrac = fract(n);
    let nearSeptum = min(chamberFrac, 1.0 - chamberFrac);
    let radialWall = nearSeptum * r * 7.5;
    let kNearS = floor(n + 0.5) + a / TAU;
    let septaPlane = length(vec2<f32>(radialWall, p.y * 0.55)) - 0.035 + select(0.0, 2.0, kNearS > kMax);
    d = min(d, septaPlane);

    // Idea — siphuncle: a thin canal along the spiral centerline.
    let rSip = exp((nf + a / TAU) * b) * 0.22;
    let siphuncle = length(vec2<f32>(r - rSip, p.y)) - 0.018 + select(0.0, 2.0, k0 > kMax);
    d = min(d, siphuncle);

    // Idea — aperture lip: a thicker rim on the outer chamber's leading edge.
    let apertureGate = smoothstep(0.62, 0.88, chamberFrac);
    // Rescue R3: HEAD blended the DISTANCE (mix(8.0, lip, gate)), which overestimated up to 8x in the gate
    // ramp and let the march step through the bounded shell. Same swelling, now as a radius blend 0.4 -> 0.5.
    let apertureLip = length(vec2<f32>(r - r1, p.y)) - r1 * mix(0.4, 0.5, apertureGate);
    d = min(d, apertureLip);

    let vNoise = voronoi(p * 20.0);
    d += vNoise * 0.02;

    return max(d * 0.85, length(p) - BOUND_R) * pulse;
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> f32 {
    var d0 = 0.0;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * d0;
        let dS = map(p, audioReactive, spiralTightness);
        d0 += dS;
        if (d0 > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }
    return d0;
}

fn calcNormal(p: vec3<f32>, audioReactive: f32, spiralTightness: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, audioReactive, spiralTightness) - map(p - e.xyy, audioReactive, spiralTightness),
        map(p + e.yxy, audioReactive, spiralTightness) - map(p - e.yxy, audioReactive, spiralTightness),
        map(p + e.yyx, audioReactive, spiralTightness) - map(p - e.yyx, audioReactive, spiralTightness)
    );
    return normalize(n);
}

// Native idea 2: pearl nacre luster on inner chamber ridges.
fn pearlNacreLuster(p: vec3<f32>, n: vec3<f32>, viewDir: vec3<f32>, spiralTightness: f32, iridescenceShift: f32, t: f32) -> vec3<f32> {
    let r = length(p.xz);
    let a = atan2(p.z, p.x);
    let b = spiralTightness;
    let theta = log(max(r, 0.001)) / b;
    let nf = floor(theta - a / TAU);
    let r0 = exp((nf + a / TAU) * b);
    let innerRidge = smoothstep(0.38, 0.0, abs(r - r0 * 0.62));
    let nacrePhase = dot(n, viewDir) * 9.0 + iridescenceShift * TAU + t * 0.35;
    let nacre = 0.5 + 0.5 * cos(vec3<f32>(1.0, 1.28, 1.62) * nacrePhase + innerRidge * 4.0);
    return nacre * innerRidge * vec3<f32>(0.92, 0.96, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let coord = vec2<i32>(id.xy);
    let base_uv = vec2<f32>(f32(id.x), f32(id.y)) / resolution.xy;
    var uv = base_uv * 2.0 - 1.0;
    uv.y = -uv.y;                       // Rescue R1: texture row 0 is the TOP; world +y must point up the image
    uv.x *= resolution.x / resolution.y;

    let refrIndex = u.zoom_params.x;
    let spiralTightness = u.zoom_params.y;
    let iridescenceShift = u.zoom_params.z;
    let audioParam = u.zoom_params.w;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let audioReactive = audioParam * (0.35 + bass * 0.65 + mids * 0.2);

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    var ro = vec3<f32>(0.0, 3.0, -3.3);   // Rescue R4: 42 deg elevation (was 26 deg, same orbit radius)

    var mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    mouse_uv.y = -mouse_uv.y;
    mouse_uv.x *= resolution.x / resolution.y;

    let time = u.config.x * 0.2;
    ro = vec3<f32>(ro.x * cos(time) - ro.z * sin(time), ro.y, ro.x * sin(time) + ro.z * cos(time));

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);

    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    if (u.zoom_config.w > 0.0) {
        let mouseDist = length(uv - mouse_uv);
        let pull = 0.5 / (mouseDist * mouseDist + 0.1);
        rd = normalize(rd + vec3<f32>(uv - mouse_uv, 0.0) * pull * 0.2);
    }

    let d = raymarch(ro, rd, audioReactive, spiralTightness);

    var col = vec3<f32>(0.02, 0.02, 0.05);
    var alpha = 0.05 + treble * 0.03;
    var depth = textureLoad(readDepthTexture, coord, 0).r;
    // Rescue R4: a ray that ran out of steps near a silhouette is a miss (HEAD counted it as a hit -> speckle).
    let hit = d < MAX_DIST && map(ro + rd * d, audioReactive, spiralTightness) < 0.05;

    // Aperture mouth (R4: the siphon jet used a fixed point). The last centre-line point sits at radius SHELL_R
    // and angle a_m with a_m/TAU = kMax (mod 1); the mouth faces along the growth tangent.
    let kMaxM = log(SHELL_R) / max(spiralTightness, 0.02);
    let aM = TAU * (kMaxM - round(kMaxM));
    let pulseM = 1.0 + audioReactive * 0.2 * sin(u.config.x * 2.0);
    let radialM = vec3<f32>(cos(aM), 0.0, sin(aM));
    let mouth = radialM * SHELL_R * pulseM;
    let growthDir = normalize(vec3<f32>(-sin(aM), 0.0, cos(aM)) + radialM * (spiralTightness / TAU));

    // ── Idea 9: siphon plume (analytic ray / axis-segment closest approach, no loop, no extra map()) ──
    // A cone of bioluminescent water leaves the mouth along the growth tangent; visible against the void.
    let pw0 = ro - mouth;
    let pb = dot(rd, growthDir);
    let pDen = max(1.0 - pb * pb, 1e-3);
    let pu = clamp((dot(growthDir, pw0) - pb * dot(rd, pw0)) / pDen, 0.0, PLUME_LEN);
    let pS = max(pb * pu - dot(rd, pw0), 0.0);
    let pC = ro + rd * pS;
    let pAxis = mouth + growthDir * pu;
    let pFrac = pu / PLUME_LEN;
    let pWidth = 0.22 + 0.34 * pFrac;
    let pDist = length(pC - pAxis) / pWidth;
    let pBillow = 0.62 + 0.38 * sin(pu * 13.0 - time * 30.0 + dot(pC, vec3<f32>(7.0, 5.0, 3.0)));
    let plume = exp(-pDist * pDist) * pow(1.0 - pFrac, 1.2) * pBillow * (0.7 + treble * 1.2 + audioReactive * 0.3);

    if (hit) {
        let p = ro + rd * d;
        let n = calcNormal(p, audioReactive, spiralTightness);
        let viewDir = normalize(ro - p);

        let lightDir = normalize(vec3<f32>(1.0, 2.0, -2.0));
        let diffuse = max(dot(n, lightDir), 0.0);

        let NdotV = max(dot(n, viewDir), 0.0);
        let phase = NdotV * 5.0 + iridescenceShift * TAU + time;
        let iridescence = 0.5 + 0.5 * cos(vec3<f32>(1.0, 1.2, 1.4) * phase);

        let envUV = clamp(base_uv + vec2<f32>(n.x, -n.y) * 0.1 * (refrIndex - 1.0), vec2<f32>(0.0), vec2<f32>(1.0));   // world +y is up, uv +y is down
        let envRefr = textureSampleLevel(readTexture, u_sampler, envUV, 0.0).rgb;

        let coreDist = length(p);
        let glow = exp(-coreDist * 0.5) * vec3<f32>(0.2, 0.8, 1.0) * (1.0 + audioReactive);

        let nacre = pearlNacreLuster(p, n, viewDir, spiralTightness, iridescenceShift, time);

        // ── Idea 7: Beer-Lambert shell absorption (§12.2F) ──────────────────────
        // What reaches the eye through the glass (env refraction + the core glow) has crossed a chord of whorl
        // glass: chord = 2R cos(theta_t), R = 0.4 r (the whorl tube radius), theta_t from Snell with the
        // Refraction Index slider. Red dies first: thick outer whorls go abyssal teal, the apex stays clear.
        let rW = max(length(p.xz), 0.001);
        let sinT2 = (1.0 - NdotV * NdotV) / max(refrIndex * refrIndex, 1.0);
        let chord = 2.0 * 0.4 * rW * sqrt(max(1.0 - sinT2, 0.0));
        let trans = exp(-vec3<f32>(1.8, 0.7, 0.25) * chord);

        // ── Idea 8: conchiolin flame stripes (organism artifact) ────────────────
        // Dark indigo stripes along the growth lines of the outer whorls: constant growth coordinate k
        // (turns from the apex, integer FLAME_N per turn so the atan2 seam is invisible), forked by a warp,
        // strongest on the flanks, fading into the unpigmented new shell at the aperture.
        let aW = atan2(p.z, p.x);
        let thW = log(rW) / max(spiralTightness, 0.02);
        let kEnd = log(SHELL_R) / max(spiralTightness, 0.02);
        // nearest EXISTING whorl (a hit on the outer flank has a polar radius past the last centre line)
        let kNear = min(floor(thW - aW / TAU + 0.5), floor(kEnd - aW / TAU)) + aW / TAU;
        let flameWarp = 0.35 * sin(kNear * TAU * 3.0 + p.y * 6.0) + 0.2 * sin(kNear * TAU * 7.0 - p.y * 3.0);
        let flameS = fract(kNear * FLAME_N + flameWarp);
        let flame = smoothstep(0.0, 0.08, flameS) * (1.0 - smoothstep(0.08, 0.5, flameS));
        let flank = mix(0.4, 1.0, smoothstep(0.1, 0.6, abs(p.y) / (0.4 * rW)));
        let pigment = flame * flank * (1.0 - smoothstep(kEnd - 0.5, kEnd - 0.05, kNear));

        // the pigment sits in the shell layer: it darkens the surface, the nacre and the light seen through it
        let shellLight = iridescence * diffuse * 0.5 + (envRefr * 0.3 + glow) * trans + nacre * 0.55;
        col = mix(shellLight, vec3<f32>(0.03, 0.02, 0.14) * (0.4 + diffuse), pigment * 0.85);

        let edge = 1.0 - NdotV;
        col += vec3<f32>(edge * 0.5, edge * 0.2, 0.0);

        let aP = atan2(p.z, p.x);
        let rP = length(p.xz);
        let thetaP = log(max(rP, 0.001)) / max(spiralTightness, 0.05);
        let chamberP = fract(thetaP - aP / TAU);
        let rOuter = exp((floor(thetaP - aP / TAU) + 1.0 + aP / TAU) * spiralTightness);
        let onLip = smoothstep(0.62, 0.9, chamberP) * smoothstep(0.22, 0.0, abs(rP - rOuter) / max(rOuter, 0.001));
        col += vec3<f32>(0.75, 0.9, 1.0) * edge * onLip * refrIndex * 0.18;
        
        // Idea 1: Bioluminescent siphon jet (glowing particles emitting from the nautilus opening)
        let siphonDist = length(p - mouth);   // Rescue R4: anchored at the real aperture mouth
        let siphonNoise = voronoi(p * 50.0 - vec3<f32>(time * 5.0, 0.0, 0.0));
        let siphonJet = smoothstep(0.5, 0.0, siphonDist) * siphonNoise;
        col += vec3<f32>(0.2, 0.9, 1.0) * siphonJet * (1.0 + treble * 2.0);

        // Idea 2: Abyssal pressure fractures (crack lines on the outer shell)
        let fracNoise = voronoi(p * 10.0);
        let fracture = smoothstep(0.03, 0.0, abs(fracNoise - 0.5));
        col += vec3<f32>(1.0, 0.2, 0.6) * fracture * (0.2 + bass * 0.8) * NdotV;

        // plume in front of the shell skin
        col += vec3<f32>(0.2, 0.9, 1.0) * plume * step(pS, d) * 1.7;

        depth = clamp(1.0 - d / MAX_DIST, 0.0, 1.0);
        alpha = clamp(diffuse * 0.55 + NdotV * 0.25 + length(nacre) * 0.2 + plume * step(pS, d) * 0.2 - pigment * 0.1, 0.0, 1.0);
    } else {
        col += vec3<f32>(0.2, 0.9, 1.0) * plume * 1.7;
        alpha = clamp(alpha + plume * 0.5, 0.0, 1.0);
    }

    let previous = textureLoad(dataTextureC, coord, 0);
    col = mix(col, previous.rgb * 0.94, 0.04 + mids * 0.02);

    col = acesToneMap(col * (1.05 + bass * 0.15));
    let finalAlpha = clamp(alpha + previous.a * 0.06, 0.0, 1.0);
    let finalColor = vec4<f32>(col, finalAlpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
