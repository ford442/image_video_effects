// ═══════════════════════════════════════════════════════════════════
//  Vitreous Chrono-Chandelier
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-10-10, 2026-11-08
//  Ideas: pendular phase-locked chime clusters; floor-bound caustic web lattice; chronometric tick-marks; crystal cleavage planes; pendulum-projected floor foci (each chime focuses a caustic disc that sways with its swing); cleavage shards (bass over Shatter Threshold slides the cut-off half out along the cleavage normal); hub lamp (soft inverse-square, §12.2F)
//  Rescue 2026-11-08: camera was upside-down (hanging chimes in the top half, black bottom); Chime Density was used as the cell size and the app feeds 0.5 (no JSON params) -> 0.5-unit cells clipped every 1-3 unit pendulum into noise; floor caustic web was painted over crystals; pendulum amplitude decayed to nothing after ~1 minute and was never re-excited; Shatter Threshold was a dead slider
//  A packing: ACES display RGBA
//  By: Claude Code Batch 3B
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Shatter Threshold (bass level at which crystals split), y=Chime Density (0..1 -> cell size 7..1, default 0.5 = 4), z=Refraction Index, w=Transmission

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdRoundedBox(p: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

fn pendulumAngle(theta0: f32, t: f32, length: f32, damping: f32) -> f32 {
    let g = 9.81;
    let omega = sqrt(g / length);
    // RESCUE: HEAD damped with exp(-damping * t) forever, so every chime was still after ~1 minute. The chime is now struck again every
    // 6 half-periods exactly at its lowest point (cos = 0), so the position stays continuous and only the velocity is kicked.
    let ph = omega * t;
    let cyc = 18.849556;                              // 6 * pi
    let k = floor((ph - 1.5707963) / cyc);
    let tau = (ph - 1.5707963 - k * cyc) / omega;     // time since the last strike
    let dampedAmp = theta0 * exp(-damping * tau);
    return dampedAmp * cos(ph);
}

fn refractRay(rd: vec3<f32>, n: vec3<f32>, ior: f32) -> vec3<f32> {
    let dt = dot(rd, n);
    let discr = 1.0 - ior * ior * (1.0 - dt * dt);
    if (discr < 0.0) { return reflect(rd, n); }
    return ior * rd - (ior * dt + sqrt(discr)) * n;
}

fn causticPattern(p: vec3<f32>, time: f32) -> f32 {
    let s1 = sin(p.x * 8.0 + time * 2.0);
    let s2 = sin(p.y * 7.0 - time * 1.5);
    let s3 = sin(p.z * 6.0 + time * 1.0);
    return abs(s1 * s2 * s3);
}

fn fresnelSchlick(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    let ct = clamp(1.0 - cosTheta, 0.0, 1.0);
    let ct5 = ct * ct * ct * ct * ct;
    return F0 + (vec3<f32>(1.0) - F0) * ct5;
}

// Per-cell pendulum pose shared by the SDF and the floor foci. x,y = crystal offset (swingX, swingZ), z = angle, w = per-cell hash.
fn chimeSwing(cellX: f32, cellZ: f32, time: f32, audioBass: f32) -> vec4<f32> {
    let h = hash3(vec3<f32>(cellX, 0.0, cellZ));
    let len = 1.0 + h.x * 2.0;
    let damping = 0.1 + h.y * 0.2;
    let theta0 = 0.3 + h.z * 0.4;
    var angle = pendulumAngle(theta0, time + cellX * 0.5 + cellZ * 0.3, len, damping);
    // Idea 1: neighboring chimes phase-lock and drift apart in clusters.
    let cluster = sin((cellX + cellZ) * 0.75 + time * (0.5 + audioBass * 0.6));
    angle += 0.14 * cluster * (0.3 + audioBass * 0.7);
    return vec4<f32>(sin(angle) * len, cos(angle) * len * 0.3, angle, h.z);
}

fn sceneSDF(p: vec3<f32>, time: f32, spacing: f32, audioBass: f32, shard: f32) -> f32 {
    var q = p;
    let cellX = round(q.x / spacing);
    let cellZ = round(q.z / spacing);
    q.x = q.x - cellX * spacing;
    q.z = q.z - cellZ * spacing;
    let cs = chimeSwing(cellX, cellZ, time, audioBass);
    var crystalPos = q - vec3<f32>(cs.x, -1.5, cs.y);
    let crystal = sdRoundedBox(crystalPos, vec3<f32>(0.25, 0.6, 0.15), 0.05);
    var mountPos = q - vec3<f32>(0.0, 0.8, 0.0);
    let mount = sdTorus(mountPos, vec2<f32>(0.3, 0.06));
    let linkBox = sdRoundedBox(q - vec3<f32>(0.0, 0.4, 0.0), vec3<f32>(0.04, 0.15, 0.04), 0.01);
    // Idea 2: crystal cleavage planes
    let cleavageN = normalize(vec3<f32>(1.0, 1.0, 1.0));
    let cleavage = dot(crystalPos, cleavageN) - 0.2;
    var facetedCrystal = max(crystal, cleavage);
    // ── 2nd-pass Idea 2: cleavage shards. Bass over the Shatter Threshold slides the half the plane cut off back out along the plane normal
    // (it re-forms as bass falls). `shard` is 0 at silence, so the idle crystal is exactly the HEAD cut crystal.
    if (shard > 0.001) {
        let sp = crystalPos - cleavageN * (shard * (0.6 + 0.4 * cs.w));
        let shardD = max(sdRoundedBox(sp, vec3<f32>(0.25, 0.6, 0.15), 0.05), 0.2 - dot(sp, cleavageN));
        facetedCrystal = min(facetedCrystal, shardD);
    }

    // Idea 1: chronometric tick-marks floating around chimes
    let tickRot = p.x * 2.0 + p.y * 5.0 + time;
    let tickMarks = max(length(vec2<f32>(p.x, p.z)) - 0.6, abs(fract(tickRot) - 0.5) - 0.05);

    let d1 = min(facetedCrystal, mount);
    let d2 = min(d1, linkBox);
    return min(d2 - audioBass * 0.02, max(tickMarks, abs(p.y) - 0.02));
}

fn calcNormal(p: vec3<f32>, time: f32, spacing: f32, audioBass: f32, shard: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * sceneSDF(p + e.xyy, time, spacing, audioBass, shard) +
                     e.yyx * sceneSDF(p + e.yyx, time, spacing, audioBass, shard) +
                     e.yxy * sceneSDF(p + e.yxy, time, spacing, audioBass, shard) +
                     e.xxx * sceneSDF(p + e.xxx, time, spacing, audioBass, shard));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }
    let uv = (fragCoord * 2.0 - res) / res.y;
    let shatterThreshold = u.zoom_params.x;
    // RESCUE: the slider is a density, not a cell size (HEAD used it as the cell size and the app feeds 0.5 -> 0.5-unit cells).
    let spacing = mix(7.0, 1.0, u.zoom_params.y);
    let refractionIndex = u.zoom_params.z;
    let transmission = u.zoom_params.w;
    let audioBass = plasmaBuffer[0].x;
    let time = u.config.x * 0.5;
    // 2nd-pass Idea 2 input: bass above the Shatter Threshold slider (was read into nothing at HEAD) splits the crystals.
    let shard = clamp((audioBass - shatterThreshold) / max(1.0 - shatterThreshold, 0.05), 0.0, 1.0) * 0.9;
    // RESCUE: uv.y grows downward on screen but the scene is y-up -> flip; frame the hanging forest (pitch 0.30 rad down).
    var ro = vec3<f32>(2.0, 1.6, -6.5);
    var rd = normalize(vec3<f32>(uv.x, -uv.y, 1.0));
    rd = vec3<f32>(rd.x, rd.y * 0.955336 - rd.z * 0.295520, rd.y * 0.295520 + rd.z * 0.955336);
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    // repel point follows the camera frame: cursor up = up (view half-height at z = 0 is ~6.5)
    let mousePos = vec3<f32>(ro.x + mouseX * 6.5, ro.y - mouseY * 6.5, 0.0);
    var t = 0.0;
    var hit = false;
    var hitT = 0.0;
    var hitP = vec3<f32>(0.0);
    for(var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        let distToMouse = distance(p, mousePos);
        if (distToMouse < 4.0) {
            p += normalize(p - mousePos) * (1.0 / (distToMouse + 0.5)) * audioBass;
        }
        let d = sceneSDF(p, time, spacing, audioBass, shard);
        if (d < 0.001) {
            hit = true;
            hitP = p;
            hitT = t;
            break;
        }
        t += d * 0.6;
        if (t > 50.0) { break; }
    }
    var colR = 0.0;
    var colG = 0.0;
    var colB = 0.0;
    var fresnel = vec3<f32>(0.0);
    if (hit) {
        let n = calcNormal(hitP, time, spacing, audioBass, shard);
        let viewDir = -rd;
        let cosTheta = clamp(dot(viewDir, n), 0.0, 1.0);
        let F0 = vec3<f32>(0.04);
        fresnel = fresnelSchlick(cosTheta, F0);
        let iorR = 1.5 + refractionIndex * 0.1;
        let iorG = 1.52 + refractionIndex * 0.1;
        let iorB = 1.54 + refractionIndex * 0.1;
        let rdR = refractRay(rd, n, 1.0 / iorR);
        let rdG = refractRay(rd, n, 1.0 / iorG);
        let rdB = refractRay(rd, n, 1.0 / iorB);
        let causticR = causticPattern(hitP + rdR * 2.0, time);
        let causticG = causticPattern(hitP + rdG * 2.0, time);
        let causticB = causticPattern(hitP + rdB * 2.0, time);
        colR = causticR * 0.8 + fresnel.r * 0.3;
        colG = causticG * 0.7 + fresnel.g * 0.3;
        colB = causticB * 0.6 + fresnel.b * 0.3;
        colR = colR * transmission + audioBass * 0.1;
        colG = colG * transmission + audioBass * 0.05;
        colB = colB * transmission;
        // ── 2nd-pass Idea 3: hub lamp (soft inverse-square, §12.2F). Each mount holds a warm lamp; facets catch it as Lambert + a glint on the
        // flat cleavage faces, I * r0^2 / (d^2 + r0^2) so the core radius keeps the mount from blowing out. Bass pulses it.
        let cellH = vec2<f32>(round(hitP.x / spacing), round(hitP.z / spacing));
        let ql = vec3<f32>(hitP.x - cellH.x * spacing, hitP.y, hitP.z - cellH.y * spacing);
        let toLamp = vec3<f32>(0.0, 0.8, 0.0) - ql;
        let lampD2 = dot(toLamp, toLamp);
        let lampDir = toLamp * inverseSqrt(max(lampD2, 1e-4));
        let lampAtten = 2.25 / (lampD2 + 2.25);
        let lampLambert = max(dot(n, lampDir), 0.0);
        let lampGlint = pow(max(dot(reflect(-lampDir, n), viewDir), 0.0), 48.0);
        let lamp = vec3<f32>(1.0, 0.72, 0.42) * (1.0 + audioBass * 0.8) * (lampLambert * 0.5 + lampGlint * 1.6) * lampAtten * 1.6;
        colR += lamp.r;
        colG += lamp.g;
        colB += lamp.b;
    } else {
        let bgGlow = vec3<f32>(0.05, 0.02, 0.08) * (1.0 - length(uv) * 0.5);
        colR = bgGlow.r;
        colG = bgGlow.g;
        colB = bgGlow.b;
    }
    // Idea 2: refracted caustic web projected onto an abyssal floor plane.
    if (rd.y < -0.02) {
        let floorY = -2.6;
        let tf = (floorY - ro.y) / rd.y;
        // RESCUE: only where the floor is the first surface (HEAD painted it over the crystals), faded with distance so the far lattice
        // does not alias.
        if (tf > 0.0 && (!hit || tf < hitT)) {
            let fp = ro + rd * tf;
            let fade = exp(-tf * 0.045);
            let web = pow(causticPattern(fp * 0.85 + vec3<f32>(0.0, 0.0, time * 0.25), time * 1.2), 3.0);
            colR += web * 0.22 * (0.5 + audioBass * 0.4) * fade;
            colG += web * 0.45 * (0.5 + audioBass * 0.4) * fade;
            colB += web * 0.75 * (0.5 + audioBass * 0.4) * fade;
            // ── 2nd-pass Idea 1: pendulum-projected floor foci. Each chime focuses a bright disc + ring on the floor under it, and the focus
            // sways with that chime's own swing (the same chimeSwing the SDF hangs the crystal from). Red rim outside, blue core.
            let fcx = round(fp.x / spacing);
            let fcz = round(fp.z / spacing);
            let fcs = chimeSwing(fcx, fcz, time, audioBass);
            let dF = length(fp.xz - vec2<f32>(fcx * spacing + fcs.x, fcz * spacing + fcs.y)) / vec3<f32>(1.0, 0.94, 0.88);
            let focus = exp(-dF * dF * 6.0) + 0.35 * exp(-abs(dF - vec3<f32>(0.75)) * 9.0);
            let focusGain = (0.55 + audioBass * 0.45) * fade;
            colR += focus.x * 0.55 * focusGain;
            colG += focus.y * 0.80 * focusGain;
            colB += focus.z * 1.00 * focusGain;
        }
    }
    colR = clamp(colR, 0.0, 1.0);
    colG = clamp(colG, 0.0, 1.0);
    colB = clamp(colB, 0.0, 1.0);
    var col = vec3<f32>(colR, colG, colB);

    let coord = vec2<i32>(id.xy);

    // ═══ CHUNK: temporal-feedback (dataTextureC → dataTextureA) ═══
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.92, 0.05 + audioBass * 0.01);

    // ═══ CHUNK: chromatic-aberration ═══
    let caStr = 0.003 * (1.0 + audioBass) + fresnel.r * 0.002;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    col = acesToneMap(col * 1.2);

    let alpha = clamp(fresnel.r * 0.8 + 0.2, 0.0, 1.0);
    let uv01 = fragCoord / res;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
