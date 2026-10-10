// ═══════════════════════════════════════════════════════════════════
//  Liquid Neon Topography
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: neon iso-height contour lines; liquid neon pooling in the valleys; downhill neon rivulets along steepest descent; shoreline foam where ridges meet the pool
//  A packing: ACES display RGBA (C read back as colour history)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Ridge Height, .y = Flow Speed, .z = Emissive Glow, .w = Contour Detail

const MAX_STEPS = 100;
const MAX_DIST = 10.0;
const SURF_DIST = 0.005;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Hash function
fn hash2(p: vec2<f32>) -> vec2<f32> {
    var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

// Simplex noise
fn noise(p: vec2<f32>) -> f32 {
    let K1 = 0.366025404; // (sqrt(3)-1)/2
    let K2 = 0.211324865; // (3-sqrt(3))/6

    let i = floor(p + (p.x + p.y) * K1);
    let a = p - i + (i.x + i.y) * K2;
    var o = vec2<f32>(0.0);
    if (a.x > a.y) { o = vec2<f32>(1.0, 0.0); } else { o = vec2<f32>(0.0, 1.0); }
    let b = a - o + K2;
    let c = a - 1.0 + 2.0 * K2;

    var h = max(0.5 - vec3<f32>(dot(a, a), dot(b, b), dot(c, c)), vec3<f32>(0.0));
    let n = h * h * h * h * vec3<f32>(dot(a, hash2(i + 0.0)), dot(b, hash2(i + o)), dot(c, hash2(i + 1.0)));

    return dot(n, vec3<f32>(70.0));
}

// Domain warped fBm for organic fluid ridges
fn mapTerrain(p: vec2<f32>, time: f32, detail: f32) -> f32 {
    var q = p;
    let flowSpeed = u.zoom_params.y;

    // Domain warp offset
    let warpX = noise(q * 1.5 + time * 0.2 * flowSpeed);
    let warpY = noise(q * 1.5 - time * 0.15 * flowSpeed + vec2<f32>(1.2, 3.4));

    q += vec2<f32>(warpX, warpY) * 0.4;

    var h = 0.0;
    var a = 0.5;
    var f = 1.0;

    let octaves = i32(clamp(detail, 1.0, 8.0));

    for (var i = 0; i < 8; i++) {
        if (i >= octaves) { break; }
        h += a * noise(q * f + time * 0.1 * flowSpeed);
        a *= 0.5;
        f *= 2.0;

        // Slightly rotate each octave
        let r = rot(0.5);
        q = r * q;
    }

    // Create sharp ridges
    h = 1.0 - abs(h);
    h = h * h;

    return h * u.zoom_params.x * 0.5;
}

// Scene Distance Field
fn getDist(p: vec3<f32>, time: f32) -> f32 {
    let detail = u.zoom_params.w;
    let h = mapTerrain(p.xz, time, detail);
    return p.y - h + 1.5; // Offset floor down
}

// Raymarching
fn rayMarch(ro: vec3<f32>, rd: vec3<f32>, time: f32) -> f32 {
    var dO = 0.0;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = getDist(p, time);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }
    return dO;
}

// Normal calculation
fn getNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let d = getDist(p, time);
    let e = vec2<f32>(0.01, 0.0);
    let n = d - vec3<f32>(
        getDist(p - e.xyy, time),
        getDist(p - e.yxy, time),
        getDist(p - e.yyx, time)
    );
    return normalize(n);
}

// Neon color palette
fn neonPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(id.xy);

    if (coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) { return; }

    let res = vec2<f32>(f32(dims.x), f32(dims.y));
    let uv = (vec2<f32>(coord) - 0.5 * res) / res.y;

    // Time and Mouse interaction
    let flowSpeed = u.zoom_params.y;
    let time = u.config.x;

    let mx = (u.zoom_config.y - 0.5) * 2.0;
    let my = (u.zoom_config.z - 0.5) * 2.0;

    // Audio reactivity (plasmaBuffer: bass / mids / treble)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioPulse = smoothstep(0.1, 0.9, bass) * 2.0;

    // Camera setup
    // Sweeping camera based on time and mouse
    let camTime = time * 0.1 * (1.0 + mx * 0.5);
    var ro = vec3<f32>(0.0, 0.5, camTime * 2.0);

    // Mouse X bends the direction slightly, Mouse Y changes height
    ro.y += my;

    let lookAt = vec3<f32>(mx * 2.0, ro.y - 0.2, ro.z + 2.0);

    // Camera matrix
    let f = normalize(lookAt - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let u_vec = cross(f, r);

    let c = ro + f * 1.0;
    let i_p = c + uv.x * r + uv.y * u_vec;
    let rd = normalize(i_p - ro);

    // Render
    var col = vec3<f32>(0.0);
    var coverage = 0.0;
    var sceneT = MAX_DIST;

    let d = rayMarch(ro, rd, time);
    let glowParam = u.zoom_params.z;
    let detail = u.zoom_params.w;
    let ridgeScale = max(u.zoom_params.x * 0.5, 0.001);
    let poolLevel = -1.5 + ridgeScale * (0.14 + bass * 0.08);

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = getNormal(p, time);
        let h = mapTerrain(p.xz, time, detail);

        // Base dark metallic
        let baseColor = vec3<f32>(0.02, 0.02, 0.04);

        // Neon Ridge highlighting
        let ridgeIntensity = smoothstep(0.2, 0.8, h);
        let ridgeColor = neonPalette(p.z * 0.1 + h + time * 0.2);

        // Fresnel for liquid edge glow
        let fresnel = pow(1.0 + dot(rd, n), 4.0);

        // Emissive Glow
        let emission = ridgeColor * ridgeIntensity * glowParam * (1.0 + audioPulse * 0.5);

        // Subsurface scattering fake
        let sss = vec3<f32>(0.1, 0.2, 0.3) * smoothstep(0.0, 0.5, 1.0 - h) * (1.0 - fresnel);

        col = baseColor + emission + sss + ridgeColor * fresnel * glowParam * 0.5;

        // Idea 1: neon iso-height contour lines on world height; Contour Detail densifies the survey.
        let spacing = ridgeScale * 0.9 / (2.0 + detail * 1.5);
        let lineCoord = p.y / max(spacing, 0.0005);
        let lineDist = abs(fract(lineCoord + 0.5) - 0.5) * spacing;
        let lineWidth = 0.004 + 0.0012 * d;
        let contour = 1.0 - smoothstep(0.0, lineWidth, lineDist);
        let majorLine = select(0.55, 1.0, fract(floor(lineCoord + 0.5) / 5.0 + 0.1) < 0.2);
        let contourHue = neonPalette(floor(lineCoord + 0.5) * 0.07 + time * 0.2 * (1.0 + mids * 0.5));
        col += contourHue * contour * majorLine * glowParam * 0.6 * (1.0 - fresnel * 0.5);

        // Idea 3: downhill rivulets — neon beads run along steepest descent (-grad h from the normal),
        // only on slopes that are steep enough to shed liquid; Flow Speed sets how fast they travel.
        let slope = length(n.xz);
        let downhill = -n.xz / max(slope, 0.0001);
        let advect = downhill * time * flowSpeed * 1.2;
        let beadA = noise(p.xz * 5.0 - advect) * 0.5 + 0.5;
        let beadB = noise(p.xz * 13.0 - advect * 1.7 + vec2<f32>(7.1, 3.3)) * 0.5 + 0.5;
        let rivulet = smoothstep(0.55, 0.8, beadA * 0.6 + beadB * 0.5) * smoothstep(0.12, 0.45, slope);
        col += neonPalette(p.z * 0.1 + time * 0.2 + 0.5) * rivulet * glowParam * 0.8 * (1.0 - fresnel * 0.4) * (1.0 + audioPulse * 0.2);

        // Idea 4: shoreline foam — a bright, broken rim where the terrain crosses the pool level; treble sparkles it.
        let shoreDist = abs(p.y - poolLevel);
        let foamNoise = noise(p.xz * 18.0 + vec2<f32>(time * 0.7 * flowSpeed, -time * 0.5)) * 0.5 + 0.5;
        let foam = (1.0 - smoothstep(0.0, 0.05 + 0.01 * d, shoreDist)) * smoothstep(0.35, 0.7, foamNoise);
        col += vec3<f32>(0.7, 0.95, 1.1) * foam * glowParam * 0.7 * (0.6 + treble * 1.2);

        // Fog
        let fog = 1.0 - exp(-0.02 * d * d);
        col = mix(col, vec3<f32>(0.01, 0.01, 0.02), fog);

        coverage = clamp(0.6 + ridgeIntensity * 0.2 + contour * 0.2, 0.0, 1.0) * (1.0 - fog * 0.4);
        sceneT = d;
    } else {
        // Background sky
        let bgGlow = max(0.0, 1.0 - uv.y * 2.0) * neonPalette(time * 0.1);
        col = bgGlow * 0.1 * (1.0 + audioPulse * 0.2);
        coverage = clamp(dot(col, vec3<f32>(0.333)) * 2.0, 0.0, 0.35);
    }

    // Idea 2: liquid neon pooling — a flat bass-lifted fluid level settles in the valleys the currents carve.
    let tPool = (poolLevel - ro.y) / min(rd.y, -0.0001);
    let poolHit = rd.y < 0.0 && tPool > 0.0 && tPool < min(d, MAX_DIST);
    if (poolHit) {
        let pp = ro + rd * tPool;
        let shimmer = noise(pp.xz * 6.0 + vec2<f32>(time * 0.3 * flowSpeed, -time * 0.2 * flowSpeed));
        let pn = normalize(vec3<f32>(shimmer * 0.08 * (1.0 + treble), 1.0, noise(pp.zx * 6.0 - time * 0.25) * 0.08));
        let poolFresnel = pow(clamp(1.0 + dot(rd, pn), 0.0, 1.0), 3.0);
        let reflCol = neonPalette(pp.z * 0.1 + shimmer * 0.3 + time * 0.2) * glowParam * (0.35 + poolFresnel);
        let shallow = clamp((min(d, MAX_DIST) - tPool) * 2.5, 0.0, 1.0);
        let seen = mix(col, col * vec3<f32>(0.3, 0.45, 0.6), shallow);
        let poolFog = 1.0 - exp(-0.02 * tPool * tPool);
        col = mix(seen + reflCol * (0.25 + 0.75 * shallow) * (1.0 + audioPulse * 0.3), vec3<f32>(0.01, 0.01, 0.02), poolFog);
        coverage = clamp(0.7 + poolFresnel * 0.3, 0.0, 1.0) * (1.0 - poolFog * 0.4);
        sceneT = tPool;
    }

    // HDR tone mapping (ACES on display RGB)
    col = aces(col);
    col = pow(col, vec3<f32>(1.0/2.2));

    // Temporal history blending (exact load of last frame's A)
    let history = textureLoad(dataTextureC, coord, 0);
    let finalCol = mix(col, history.rgb, 0.7);
    let alpha = clamp(mix(coverage, history.a, 0.7), 0.0, 1.0);

    let depth = 1.0 - clamp(sceneT / MAX_DIST, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalCol, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalCol, alpha));
}
