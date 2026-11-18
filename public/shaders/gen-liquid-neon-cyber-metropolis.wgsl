// ═══════════════════════════════════════════════════════════════════
//  Liquid-Neon Cyber-Metropolis
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-11-18
//  Ideas: liquid neon rivers flowing down tower veins; wet-street neon reflections; gravity-warp horizon ring; neon light-trail traffic in the street canyons; flickering lit-window lattice with bass-flash neon panes; neon sign columns (scrolling LED glyph strips on tower faces); roof panel seams (tiled neon roofs); roof obstruction beacons (blinking red aircraft-warning lamps); camera altitude clears the skyline (was inside a tower 23% of the orbit)
//  A packing: ACES display RGBA (C read back via exact textureLoad as neon persistence history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Neon Intensity, y=City Density, z=Audio Reactivity, w=Gravity Warp Strength

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}


// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn h21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

fn boxSDF(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

struct MapResult {
    d: f32,
    mat: f32, // 0.0 = concrete, 1.0 = neon
};

fn gravityMousePos() -> vec3<f32> {
    return vec3<f32>(
        (u.zoom_config.y - 0.5) * 20.0,
        0.0,
        (u.zoom_config.z - 0.5) * 20.0
    );
}

// === Gravity Warp (Mouse Interaction) ===
fn gravityWarp(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    let mousePos = gravityMousePos();
    let distToMouse = length(p.xz - mousePos.xz);
    let warpStrength = u.zoom_params.w;
    if (distToMouse < 12.0 && warpStrength > 0.0) {
        let warpAmt = (12.0 - distToMouse) / 12.0;
        let warpDir = normalize(vec3<f32>(p.x - mousePos.x, 0.0, p.z - mousePos.z));
        p.x -= warpDir.x * warpAmt * warpStrength * 6.0;
        p.z -= warpDir.z * warpAmt * warpStrength * 6.0;
    }
    return p;
}

// === City Density & Repetition === (higher slider = denser city; spans the 0-1 slider range,
// default 0.5 keeps HEAD's ~6.5 cell size)
fn cityRepSize() -> f32 {
    return mix(8.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
}

fn cityHash(p: vec3<f32>, repSize: f32) -> f32 {
    let cellId = floor((p.xz + repSize * 0.5) / repSize);
    return fract(sin(dot(cellId, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn map(p_in: vec3<f32>) -> MapResult {
    let p = gravityWarp(p_in);

    let repSize = cityRepSize();
    var q = p;
    q.x = (fract(p.x / repSize + 0.5) - 0.5) * repSize;
    q.z = (fract(p.z / repSize + 0.5) - 0.5) * repSize;

    // === Audio Reactivity + Height Variation ===
    let audioAmp = plasmaBuffer[0].x * u.zoom_params.z;
    let hHash = cityHash(p, repSize);
    let baseHeight = 2.5 + hHash * 9.0;
    let animHeight = baseHeight + sin(u.config.x * 2.5 + hHash * 12.0) * audioAmp * 3.5;

    // Base building
    let bSize = vec3<f32>(repSize * 0.36, animHeight, repSize * 0.36);
    var dConcrete = boxSDF(q - vec3<f32>(0.0, animHeight * 0.5, 0.0), bSize);

    // KIFS architectural detail on top
    var kifsP = q - vec3<f32>(0.0, animHeight * 1.8, 0.0);
    for (var i = 0; i < 4; i++) {
        kifsP = abs(kifsP) - vec3<f32>(0.18, 0.55, 0.18);
        let r = rot2D(0.45 + sin(u.config.x * 0.1) * 0.1);
        let kxy = r * kifsP.xy;
        kifsP.x = kxy.x; kifsP.y = kxy.y;
    }
    let dKifs = boxSDF(kifsP, vec3<f32>(0.12, 1.8, 0.12));
    dConcrete = min(dConcrete, dKifs);

    // Neon veins (slightly larger + pulsing)
    let neonSize = vec3<f32>(repSize * 0.39, animHeight * 1.15, repSize * 0.39);
    var dNeon = boxSDF(q - vec3<f32>(0.0, animHeight * 0.5, 0.0), neonSize)
                + 0.08 * sin(q.y * 14.0 - u.config.x * 6.0);

    // Ground plane
    let dFloor = p.y + 0.05;
    dConcrete = smin(dConcrete, dFloor, 0.6);

    // Final result
    var res: MapResult;
    res.d = smin(dConcrete, dNeon, 0.15);

    if (dNeon < dConcrete - 0.03) {
        res.mat = 1.0; // neon
    } else {
        res.mat = 0.0; // concrete
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord - 0.5 * res) / res.y;

    // Camera
    let time = u.config.x;
    let camTime = time * 0.15;
    // ── Rescue 1: camera clears the skyline ──
    // HEAD orbited at y = 14 ± 3, which is INSIDE the tower field (towers span y -h/2..1.5h,
    // neon shell to 1.65h, crowns to ~25): the camera was inside the SDF for ~23% of the
    // orbit and the frame went to one flat neon wall. 28 ± 2 keeps d > 3 at idle.
    var ro = vec3<f32>(
        sin(camTime) * 28.0,
        28.0 + sin(time * 0.3) * 2.0,
        cos(camTime) * 28.0 + 8.0
    );

    // Mouse influence on camera
    let mx = (u.zoom_config.y - 0.5) * 12.0;
    let my = (u.zoom_config.z - 0.5) * 8.0;
    ro.x += mx;
    ro.y += my * 0.6;

    let ta = vec3<f32>(mx * 0.6, 3.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.2 * cw);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let bloomCol = mix(vec3<f32>(0.0, 0.85, 1.1), vec3<f32>(1.0, 0.1, 0.9), sin(time * 0.8) * 0.5 + 0.5);

    // Raymarching
    var t = 0.0;
    var hit = false;
    var mat = 0.0;
    var glow = 0.0;
    let maxSteps = 160;
    let maxDist = 120.0;

    for (var i = 0; i < maxSteps; i++) {
        let p = ro + rd * t;
        let resMap = map(p);

        if (resMap.d < 0.001) {
            hit = true;
            mat = resMap.mat;
            break;
        }
        if (t > maxDist) { break; }

        t += resMap.d * 0.75;

        // Neon glow accumulation
        if (resMap.mat > 0.5) {
            glow += 0.012 / (0.08 + abs(resMap.d)) * u.zoom_params.x * (1.0 + treble * 0.3);
        }
    }

    // Shading
    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let wp = gravityWarp(p);
        let repSize = cityRepSize();
        let hHash = cityHash(wp, repSize);
        let qxz = (fract(wp.xz / repSize + 0.5) - 0.5) * repSize;

        let lig = normalize(vec3<f32>(0.6, 1.0, -0.4));
        let dif = max(dot(n, lig), 0.0);
        let amb = 0.12 + 0.88 * max(n.y, 0.0);

        if (mat < 0.5) {
            // Concrete
            col = vec3<f32>(0.045, 0.05, 0.07) * (dif * 0.7 + amb);
            
            // Idea 5: lit-window lattice on the tower faces — most panes dark, a few warm and flickering,
            // and the rare pane flashes neon on a bass hit.
            let faceLateral = select(p.x, p.z, abs(n.x) > abs(n.z));
            let winGrid = vec2<f32>(faceLateral * 1.8, p.y * 1.4);
            let winCell = floor(winGrid);
            let winFrac = fract(winGrid) - 0.5;
            let winHash = fract(sin(dot(winCell, vec2<f32>(12.9898, 78.233)) + hHash * 50.0) * 43758.5453);
            let winFrame = step(abs(winFrac.x), 0.26) * step(abs(winFrac.y), 0.3);
            let facade = smoothstep(0.35, 0.1, abs(n.y)) * step(0.3, p.y);
            let winOn = step(0.7, winHash) * (0.55 + 0.45 * step(0.25, fract(winHash * 31.0 + time * 0.35)));
            let winFlash = step(0.93, winHash) * clamp(bass, 0.0, 1.5);
            let winNeon = mix(vec3<f32>(0.0, 1.0, 1.2), vec3<f32>(1.1, 0.0, 1.1), fract(winHash * 17.0));
            col += (vec3<f32>(1.0, 0.72, 0.38) * winOn * 0.45 + winNeon * winFlash * 1.6) * winFrame * facade;

            // Subtle scanning lines
            let scan = fract(length(p.xz) * 0.08 - time * 3.0);
            if (scan < 0.04) {
                col += vec3<f32>(0.0, 0.4, 0.9) * (0.6 - scan * 15.0);
            }

            let groundMask = (1.0 - smoothstep(0.0, 0.6, p.y)) * smoothstep(0.7, 0.95, n.y);

            // Idea 1 (apron): the neon river pools where each vein meets the street.
            let veinEdge = length(max(abs(qxz) - vec2<f32>(repSize * 0.39), vec2<f32>(0.0)));
            let apronHue = fract(time * 0.25 + hHash);
            let apronCol = mix(vec3<f32>(0.0, 1.0, 1.2), vec3<f32>(1.1, 0.0, 1.1), apronHue);
            col += apronCol * exp(-veinEdge * 3.0) * groundMask * 0.9 * u.zoom_params.x * (1.0 + bass * 0.5);

            // Idea 4: neon traffic — liquid light trails stream along the street canyons between towers.
            // Two lanes per side of each street centreline, opposite directions either side, faster on bass.
            let cl = vec2<f32>(repSize * 0.5 - abs(qxz.x), repSize * 0.5 - abs(qxz.y));
            let side = vec2<f32>(select(-1.0, 1.0, qxz.x > 0.0), select(-1.0, 1.0, qxz.y > 0.0));
            let cellIdXZ = floor((wp.xz + repSize * 0.5) / repSize);
            let laneSeed = fract(sin(dot(cellIdXZ, vec2<f32>(7.1, 13.7))) * 4375.5453);
            let trailSpeed = 1.2 + bass * 2.2;
            let trailZ = pow(fract(p.z * 0.11 - side.x * time * trailSpeed + laneSeed * 9.0), 14.0);
            let trailX = pow(fract(p.x * 0.11 - side.y * time * trailSpeed + laneSeed * 5.0), 14.0);
            // ── Rescue 2: pow(negative, 2.0) is indeterminate in WGSL (NaN on real GPUs); square it ──
            let laneDz = (cl.x - 0.45) / 0.09;
            let laneDx = (cl.y - 0.45) / 0.09;
            let laneZ = exp(-laneDz * laneDz);
            let laneX = exp(-laneDx * laneDx);
            let trailColZ = select(vec3<f32>(0.1, 0.9, 1.2), vec3<f32>(1.2, 0.15, 0.35), side.x > 0.0);
            let trailColX = select(vec3<f32>(0.1, 0.9, 1.2), vec3<f32>(1.2, 0.15, 0.35), side.y > 0.0);
            col += (trailColZ * trailZ * laneZ + trailColX * trailX * laneX) * groundMask * 2.4 * u.zoom_params.x;

            // Idea 3: gravity-warp horizon ring — the warp's 12-unit edge glows on the street.
            let mouseDist = length(p.xz - gravityMousePos().xz);
            let ringAngle = atan2(p.z - gravityMousePos().z, p.x - gravityMousePos().x);
            let ringShimmer = 0.7 + 0.3 * sin(ringAngle * 12.0 + time * 3.0) * (0.4 + mids);
            let ring = exp(-abs(mouseDist - 12.0) * 3.0) * groundMask * u.zoom_params.w * ringShimmer;
            col += bloomCol * ring * 1.4;

            // Idea 2: wet-street neon reflections — a short glossy march off the puddled
            // ground re-accumulates the same neon glow term as the primary march.
            let puddle = smoothstep(0.1, 0.6, 0.5 + 0.5 * sin(p.x * 0.43 + 1.3) * sin(p.z * 0.37 - 0.7));
            let wet = groundMask * puddle;
            if (wet > 0.01) {
                let rippleN = normalize(vec3<f32>(
                    sin(p.x * 3.1 + time * 1.7) * 0.03,
                    1.0,
                    cos(p.z * 2.7 - time * 1.3) * 0.03
                ));
                let rrd = reflect(rd, rippleN);
                var rt = 0.1;
                var rglow = 0.0;
                for (var j = 0; j < 40; j++) {
                    let rMap = map(p + vec3<f32>(0.0, 0.06, 0.0) + rrd * rt);
                    if (rMap.d < 0.002 || rt > 40.0) { break; }
                    rglow += select(0.0, 0.012 / (0.08 + abs(rMap.d)), rMap.mat > 0.5);
                    rt += max(rMap.d * 0.8, 0.05);
                }
                col += bloomCol * rglow * 0.1 * u.zoom_params.x * wet;
            }
        } else {
            // Neon
            let hue = fract(p.y * 0.04 + time * 0.25);
            let neonCol = mix(vec3<f32>(0.0, 1.0, 1.2), vec3<f32>(1.1, 0.0, 1.1), hue);
            col = neonCol * (1.8 + sin(time * 8.0 + p.y * 10.0) * 0.6) * u.zoom_params.x;

            // Idea 1: liquid neon rivers — bright packets flow down each tower's vein,
            // per-tower phase from the cell hash, speed lifted by bass.
            let flowPhase = fract(p.y * 0.25 + time * (0.6 + bass * 0.8) + hHash * 7.0);
            let packet = pow(flowPhase, 8.0);
            col += neonCol * packet * 2.5 * u.zoom_params.x;

            let neonGain = mix(0.6, 1.4, clamp(u.zoom_params.x, 0.0, 1.0));
            // Rib crests tilt wall normals up to n.y = ±0.75, so roofs need n.y > 0.85.
            let roof = smoothstep(0.85, 0.97, n.y);
            let wallM = 1.0 - smoothstep(0.7, 0.9, abs(n.y));

            // ── Idea 6: neon sign columns (native) ──
            // One vertical LED strip per face on about 60% of the faces: four glyph cells wide,
            // dark mullions, bits scroll DOWN the strip like the liquid packets above, bass flicker.
            let faceX = abs(n.x) > abs(n.z);
            let faceSgn = select(select(-1.0, 1.0, n.z > 0.0), select(-1.0, 1.0, n.x > 0.0), faceX);
            let faceId = select(0.0, 2.0, faceX) + faceSgn * 0.5 + 0.5;
            let hf = h21(vec2<f32>(hHash * 91.7, faceId * 17.3));
            let stripOn = step(0.4, hf);
            let lat = select(qxz.x, qxz.y, faceX);
            let c0 = (fract(hf * 7.0) - 0.5) * repSize * 0.2;
            let gx = (lat - c0) / 0.55;
            let gy = p.y / 0.7 + time * (0.9 + bass * 1.6);
            let inStrip = step(abs(gx), 2.0) * step(0.8, p.y) * step(p.y, 5.0 + 9.0 * fract(hf * 3.7));
            let gcell = vec2<f32>(floor(gx), floor(gy));
            let gbit = step(0.5, h21(gcell + vec2<f32>(hf * 31.0, 3.7)));
            let gfx = fract(gx);
            let gfy = fract(gy);
            let gmask = step(0.12, gfx) * step(gfx, 0.88) * step(0.15, gfy) * step(gfy, 0.85);
            let signCol = select(vec3<f32>(1.2, 0.1, 0.35), vec3<f32>(0.1, 0.9, 1.2), fract(hf * 13.0) > 0.5);
            let signAmt = stripOn * inStrip * wallM;
            col = mix(col, col * 0.25, signAmt);
            col += signCol * gbit * gmask * signAmt * (1.6 + bass * 1.5 + 0.3 * sin(time * 17.0 + hf * 40.0)) * neonGain;

            // ── Idea 7: roof panel seams (native) ──
            // Up-facing neon skin is a tiled panel roof: per-panel level from the tower hash,
            // dark seams. Anchored to the tower cell (qxz) so the panels follow the gravity warp.
            let panelUV = qxz / 1.1;
            let panelCell = floor(panelUV);
            let panelF = abs(fract(panelUV) - 0.5);
            let seam = smoothstep(0.40, 0.47, max(panelF.x, panelF.y));
            let panelLevel = (0.55 + 0.45 * h21(panelCell + vec2<f32>(hHash * 91.0, 5.1))) * (1.0 - 0.85 * seam);
            col = mix(col, col * panelLevel, roof);

            // ── Idea 8: roof obstruction beacons (native) ──
            // One red aircraft-warning lamp on a roof corner per tower, per-tower blink phase;
            // the persistence blend below gives the lamp its one-frame afterglow.
            let bcSign = vec2<f32>(select(-1.0, 1.0, fract(hHash * 7.31) > 0.5), select(-1.0, 1.0, fract(hHash * 13.77) > 0.5));
            let bcD = qxz - bcSign * repSize * 0.3;
            let bcR2 = dot(bcD, bcD);
            let bcPhase = fract(time * 0.7 + hHash * 5.0);
            let bcOn = smoothstep(0.0, 0.04, bcPhase) * (1.0 - smoothstep(0.34, 0.42, bcPhase));
            col += vec3<f32>(1.5, 0.06, 0.04) * (exp(-bcR2 * 4.0) * 2.2 + exp(-bcR2 * 0.8) * 0.5) * bcOn * roof * neonGain;
        }

        // Fake specular reflection
        if (mat < 0.5) {
            let refl = reflect(rd, n);
            let refGlow = max(0.0, dot(refl, vec3<f32>(0.0, 1.0, 0.0))) * 0.35;
            col += vec3<f32>(0.1, 0.7, 1.0) * refGlow * u.zoom_params.x;
        }
    }

    // Global neon bloom
    col += bloomCol * glow * 0.13;

    // Fog
    col = mix(col, vec3<f32>(0.008, 0.012, 0.035), 1.0 - exp(-0.0008 * t * t));

    // Tonemapping + gamma
    col = aces(col);
    col = pow(col, vec3<f32>(0.4545));

    // Neon persistence: bright veins leave a short decaying afterglow from exact colour history.
    let coord = vec2<i32>(id.xy);
    let previous = textureLoad(dataTextureC, coord, 0);
    col = max(col, previous.rgb * 0.3);

    let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let hitMask = select(0.0, 1.0, hit);
    let neonMask = select(0.0, 1.0, hit && mat > 0.5);
    let alpha = clamp(0.15 + hitMask * 0.55 + neonMask * 0.15 + luma * 0.2 + glow * 0.02, 0.0, 1.0);
    let depth = select(1.0, clamp(t / maxDist, 0.0, 0.995), hit);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
