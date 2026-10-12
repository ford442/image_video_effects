// ═══════════════════════════════════════════════════════════════════
//  Vitreous Chrono-Chandelier
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-10-10
//  Ideas: pendular phase-locked chime clusters; floor-bound caustic web lattice; chronometric tick-marks; crystal cleavage planes
//  A packing: ACES display RGBA
//  By: Claude Code Batch 3B
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission

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
    let dampedAmp = theta0 * exp(-damping * t);
    return dampedAmp * cos(omega * t);
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

fn sceneSDF(p: vec3<f32>, time: f32, chimeDensity: f32, audioBass: f32) -> f32 {
    var q = p;
    let cellX = round(q.x / chimeDensity);
    let cellZ = round(q.z / chimeDensity);
    q.x = q.x - cellX * chimeDensity;
    q.z = q.z - cellZ * chimeDensity;
    let h = hash3(vec3<f32>(cellX, 0.0, cellZ));
    let len = 1.0 + h.x * 2.0;
    let damping = 0.1 + h.y * 0.2;
    let theta0 = 0.3 + h.z * 0.4;
    var angle = pendulumAngle(theta0, time + cellX * 0.5 + cellZ * 0.3, len, damping);
    // Idea 1: neighboring chimes phase-lock and drift apart in clusters.
    let cluster = sin((cellX + cellZ) * 0.75 + time * (0.5 + audioBass * 0.6));
    angle += 0.14 * cluster * (0.3 + audioBass * 0.7);
    let swingX = sin(angle) * len;
    let swingZ = cos(angle) * len * 0.3;
    var crystalPos = q - vec3<f32>(swingX, -1.5, swingZ);
    let crystal = sdRoundedBox(crystalPos, vec3<f32>(0.25, 0.6, 0.15), 0.05);
    var mountPos = q - vec3<f32>(0.0, 0.8, 0.0);
    let mount = sdTorus(mountPos, vec2<f32>(0.3, 0.06));
    let linkBox = sdRoundedBox(q - vec3<f32>(0.0, 0.4, 0.0), vec3<f32>(0.04, 0.15, 0.04), 0.01);
    // Idea 2: crystal cleavage planes
    let cleavage = dot(crystalPos, normalize(vec3<f32>(1.0, 1.0, 1.0))) - 0.2;
    let facetedCrystal = max(crystal, cleavage);
    
    // Idea 1: chronometric tick-marks floating around chimes
    let tickRot = p.x * 2.0 + p.y * 5.0 + time;
    let tickMarks = max(length(vec2<f32>(p.x, p.z)) - 0.6, abs(fract(tickRot) - 0.5) - 0.05);

    let d1 = min(facetedCrystal, mount);
    let d2 = min(d1, linkBox);
    return min(d2 - audioBass * 0.02, max(tickMarks, abs(p.y) - 0.02));
}

fn calcNormal(p: vec3<f32>, time: f32, chimeDensity: f32, audioBass: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * sceneSDF(p + e.xyy, time, chimeDensity, audioBass) +
                     e.yyx * sceneSDF(p + e.yyx, time, chimeDensity, audioBass) +
                     e.yxy * sceneSDF(p + e.yxy, time, chimeDensity, audioBass) +
                     e.xxx * sceneSDF(p + e.xxx, time, chimeDensity, audioBass));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }
    let uv = (fragCoord * 2.0 - res) / res.y;
    let shatterThreshold = u.zoom_params.x;
    let chimeDensity = u.zoom_params.y;
    let refractionIndex = u.zoom_params.z;
    let transmission = u.zoom_params.w;
    let audioBass = plasmaBuffer[0].x;
    let time = u.config.x * 0.5;
    var ro = vec3<f32>(0.0, 3.0, -8.0);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    let mousePos = vec3<f32>(mouseX * 5.0, 3.0 - mouseY * 4.0, 0.0);
    var t = 0.0;
    var hit = false;
    var hitP = vec3<f32>(0.0);
    for(var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        let distToMouse = distance(p, mousePos);
        if (distToMouse < 4.0) {
            p += normalize(p - mousePos) * (1.0 / (distToMouse + 0.5)) * audioBass;
        }
        let d = sceneSDF(p, time, chimeDensity, audioBass);
        if (d < 0.001) {
            hit = true;
            hitP = p;
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
        let n = calcNormal(hitP, time, chimeDensity, audioBass);
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
        if (tf > 0.0) {
            let fp = ro + rd * tf;
            let web = pow(causticPattern(fp * 0.85 + vec3<f32>(0.0, 0.0, time * 0.25), time * 1.2), 3.0);
            colR += web * 0.22 * (0.5 + audioBass * 0.4);
            colG += web * 0.45 * (0.5 + audioBass * 0.4);
            colB += web * 0.75 * (0.5 + audioBass * 0.4);
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
