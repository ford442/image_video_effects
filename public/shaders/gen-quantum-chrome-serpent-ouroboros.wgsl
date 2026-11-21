// ----------------------------------------------------------------
// Quantum-Chrome Serpent Ouroboros
// Category: generative
// Upgraded: 2026-09-27, 2026-11-21
// Ideas: quantum dispersion trails; audio chromatic reflection aberration; ouroboros head-swell / tail-taper profile circulating the ring; shingled keeled scale plates (scale-density keyed); step-count AO in the plate grooves (12.2E)
// A packing: raw linear pre-ACES col + alpha, read back as colour history (C); ACES on writeTexture only
// Fix (2026-11-21): the coil twist reused the already overwritten pos.x for pos.z (a shear, not a rotation); the environment peaked at ~0.1 so the chrome reflected black (mean luma 0.07) - the same two cyan/purple bands are now bright, narrow neon strips.
// ----------------------------------------------------------------
#include "_prelude.wgsl"
// zoom_params: x=Coil Tightness, y=Scale Density, z=Core Heat, w=Dispersion

const PI: f32 = 3.14159265359;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D rotation matrix around Y axis
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

// 3D rotation matrix around X axis
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

// 3D rotation matrix around Z axis
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Hash function
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + vec3<f32>(33.33));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Value noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let n = i.x + i.y * 157.0 + i.z * 113.0;

    let res = mix(
        mix(
            mix(fract(sin(n) * 43758.5453123), fract(sin(n + 1.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 157.0) * 43758.5453123), fract(sin(n + 158.0) * 43758.5453123), u.x),
            u.y
        ),
        mix(
            mix(fract(sin(n + 113.0) * 43758.5453123), fract(sin(n + 114.0) * 43758.5453123), u.x),
            mix(fract(sin(n + 270.0) * 43758.5453123), fract(sin(n + 271.0) * 43758.5453123), u.x),
            u.y
        ),
        u.z
    );
    return res;
}

// Fractional Brownian Motion
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 5; i++) {
        f += amp * noise(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

// Torus SDF
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Main SDF logic
fn map(p: vec3<f32>, time: f32, audio: f32) -> vec2<f32> { // returns (distance, material_id)
    var pos = p;

    // Smooth magnetic twisting of space
    let twist_angle = sin(pos.y * 0.2 + time * 0.5) * u.zoom_params.x * 0.5;
    let xz_rot = rot(twist_angle);
    let twx = pos.x * xz_rot[0].x + pos.z * xz_rot[1].x;
    let twz = pos.x * xz_rot[0].y + pos.z * xz_rot[1].y;   // uses the ORIGINAL pos.x (HEAD reused the overwritten one: a shear)
    pos.x = twx;
    pos.z = twz;

    // Mouse interaction warps space
    let mx = (u.zoom_config.y * 2.0 - 1.0) * 2.0;
    let my = (u.zoom_config.z * 2.0 - 1.0) * 2.0;
    pos.x += sin(pos.y * 0.5) * mx;
    pos.z += cos(pos.y * 0.5) * my;

    // Base torus shape
    let r1 = 3.0; // Major radius
    var r2 = 0.8; // Minor radius

    // Toroidal coordinates for scales
    let theta = atan2(pos.z, pos.x);
    let phi = atan2(pos.y, length(pos.xz) - r1);

    // Scale patterns using sine waves and noise along toroidal coordinates
    let scaleFreq = u.zoom_params.y * 10.0;
    let scaleVal = sin(theta * scaleFreq + time) * sin(phi * scaleFreq * 0.5);

    // ── Idea 1: ouroboros profile. s = 0 at the head, running once around the ring; the tail tapers to a
    // thin tip that meets the swollen head/neck (radius is continuous at the seam), and the whole profile
    // circulates slowly - the snake chasing the tail it swallows. Pure r2 modulation.
    let s = fract((theta - time * 0.12) / (2.0 * PI));
    let tailTaper = mix(1.0, 0.55, smoothstep(0.5, 1.0, s));
    let neck = mix(0.55, 1.0, smoothstep(0.0, 0.05, s));
    let hz = (s - 0.07) / 0.05;
    let hb = max(1.0 - hz * hz, 0.0);                    // polynomial bump (no exp): head swell over s = 0.02..0.12
    let headBulge = 0.3 * hb * hb * smoothstep(0.0, 0.02, s);
    r2 *= tailTaper * neck + headBulge;

    // Audio reactivity makes scales flare and ripple
    let audioBump = audio * 0.3 * (1.0 + sin(theta * 5.0 - time * 2.0));
    r2 += scaleVal * 0.05 + audioBump;

    let d_coarse = sdTorus(pos, vec2<f32>(r1, r2));
    // Cost bound: plates move the surface by < 0.04 and the KIFS term adds < 1 %, so far from the hide
    // neither can change a march step - skip them until the ray is within 0.15 of the surface.
    if (d_coarse > 0.15) {
        return vec2<f32>(d_coarse, 1.0);
    }

    // ── Idea 2: shingled keeled plates on a brick-offset (theta, phi) lattice. Density rides the existing
    // Scale Density slider (integer counts so the lattice closes around both angles); each plate rises from
    // its free edge and drops softly onto the next row, with a keel down its centre. The sine-product
    // above stays as the large-scale swell.
    let nU = max(floor(scaleFreq * 8.0), 8.0);
    let nV = 2.0 * max(floor(scaleFreq * 1.2), 3.0);
    let vC = (phi / (2.0 * PI) + 0.5) * nV;
    let row = floor(vC);
    let uC = theta / (2.0 * PI) * nU + 0.5 * (row - 2.0 * floor(row * 0.5));
    let fu = fract(uC);
    let fv = fract(vC);
    let arch = sin(PI * fv);
    let edge = 0.68 + 0.2 * arch;                        // free edge bows out: rounded plate tips
    let ramp = max(smoothstep(0.0, 0.8, fu) - smoothstep(edge, edge + 0.12, fu), 0.0);
    let kz = (fv - 0.5) * 10.0;
    let kk = max(1.0 - kz * kz * 0.25, 0.0);             // keel: polynomial bump, |fv - 0.5| < 0.2
    let plate = ramp * (0.55 + 0.45 * arch + 0.35 * kk * kk);
    let d_torus = d_coarse - (plate - 0.5) * 0.045;   // sdTorus(r2 + dr) = sdTorus(r2) - dr

    // Add micro-fractal detail to surface (KIFS)
    var q = pos;
    q.x = q.x - r1 * cos(theta);
    q.z = q.z - r1 * sin(theta);
    // q is now relative to the core of the tube

    // Simple KIFS fold for scale edges
    var f_dist = length(q);
    for (var i=0; i<3; i++) {
        q = abs(q) - vec3<f32>(0.1, 0.1, 0.1);
        let rotM = rot(0.5);
        let new_xy = rotM * vec2<f32>(q.x, q.y);
        q.x = new_xy.x;
        q.y = new_xy.y;
    }

    let final_dist = d_torus + length(q) * 0.01;

    return vec2<f32>(final_dist, 1.0); // Material ID 1.0 = Serpent
}

// Normal calculation
fn calcNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.005;
    return normalize(
        e.xyy * map(p + e.xyy, time, audio).x +
        e.yyx * map(p + e.yyx, time, audio).x +
        e.yxy * map(p + e.yxy, time, audio).x +
        e.xxx * map(p + e.xxx, time, audio).x
    );
}

// ── Idea 3: step-count AO (12.2E). Two taps up the normal; where the plate grooves of Idea 2 trap the
// surface, map() reads nearer than the tap height and the chrome's reflection/diffuse are occluded.
fn grooveAO(p: vec3<f32>, n: vec3<f32>, time: f32, audio: f32) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 2; i++) {
        let h = 0.02 + 0.07 * f32(i - 1);
        occ += (h - map(p + n * h, time, audio).x) * sca;
        sca *= 0.6;
    }
    return clamp(1.0 - 9.0 * occ, 0.0, 1.0);
}

// Raymarching function
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32) -> vec2<f32> { // returns (t, material_id)
    var t = 0.0;
    var mat_id = 0.0;
    for (var i = 0; i < 128; i++) {
        let p = ro + rd * t;
        let res = map(p, time, audio);
        if (res.x < 0.001 * t) {
            mat_id = res.y;
            break;
        }
        t += res.x * 0.7; // Under-relax to avoid artifacting with SDF distortions
        if (t > 20.0) {
            break;
        }
    }
    return vec2<f32>(t, mat_id);
}

// Environment map (fake) for chrome reflections
fn getEnvMap(rd: vec3<f32>) -> vec3<f32> {
    let nrd = normalize(rd);
    let uv = vec2<f32>(atan2(nrd.z, nrd.x) / (2.0 * PI) + 0.5, nrd.y * 0.5 + 0.5);
    // Dark void with subtle cyan/purple glows
    var col = vec3<f32>(0.02, 0.02, 0.05);
    col += vec3<f32>(0.0, 0.5, 1.0) * pow(max(0.0, sin(uv.x * 10.0 + uv.y * 5.0)), 10.0) * 1.2;
    col += vec3<f32>(0.5, 0.0, 1.0) * pow(max(0.0, cos(uv.x * 7.0 - uv.y * 12.0)), 10.0) * 1.2;
    return col;
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let tex_coords = vec2<i32>(id.xy);

    if (tex_coords.x >= i32(dims.x) || tex_coords.y >= i32(dims.y)) { return; }

    let res = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(tex_coords) - 0.5 * res) / res.y;

    // Correct UV orientation (Y flipped in WGSL vs standard GLSL)
    uv.y = -uv.y;

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let audio = clamp(bass, 0.0, 2.0);

    // Cinematic camera setup
    let camRadius = 8.0;
    let camAngle = time * 0.1;
    let ro = vec3<f32>(sin(camAngle) * camRadius, sin(time * 0.05) * 2.0, cos(camAngle) * camRadius);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    // Camera matrix
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    // Ray direction with dispersion mapping
    let disp = max(u.zoom_params.w, 0.1) * 0.5;
    let rd = normalize(uv.x * cu + uv.y * cv + (1.0 / disp) * cw);

    // Render
    let rm = raymarch(ro, rd, time, audio);
    let t = rm.x;
    let mat_id = rm.y;

    var col = vec3<f32>(0.0);
    var alpha = 0.0;

    // Deep abyss background volumetric dust
    let dust = fbm(rd * 10.0 + time * 0.2) * 0.1;
    let bgCol = mix(vec3<f32>(0.01, 0.01, 0.03), vec3<f32>(0.0, 0.1, 0.2), rd.y * 0.5 + 0.5) + vec3<f32>(dust);
    col = bgCol;
    alpha = dust * 0.5;

    // Idea 1: Quantum dispersion trails lagging behind the serpent core
    let trailDist = length(cross(rd, ta - ro)) / length(rd);
    let trailGlow = exp(-trailDist * 2.0) * vec3<f32>(0.1, 0.3, 0.8) * bass * u.zoom_params.z;
    col += trailGlow;
    alpha += length(trailGlow);

    if (t < 20.0 && mat_id > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, time, audio);

        // Shading: Liquid Chrome
        let v = -rd;
        let ndotv = max(0.0, dot(n, v));

        // Fresnel reflection (Schlick)
        let f0 = vec3<f32>(0.8, 0.8, 0.9); // Silver base
        let fresnel = f0 + (1.0 - f0) * pow(clamp(1.0 - ndotv, 0.0, 1.0), 5.0);
        let groove = grooveAO(p, n, time, audio);

        // Reflected ray
        let r = reflect(rd, n);

        // Idea 2: Chromatic aberration in the reflection mapping based on audio
        let audioCa = bass * 0.05 * u.zoom_params.z;
        let envColR = getEnvMap(r + vec3<f32>(audioCa, 0.0, 0.0));
        let envColG = getEnvMap(r);
        let envColB = getEnvMap(r - vec3<f32>(audioCa, 0.0, 0.0));
        let envCol = vec3<f32>(envColR.r, envColG.g, envColB.b);

        // Specular highlight from core
        let lightDir = normalize(vec3<f32>(0.0) - p); // Core is at center
        let ndotl = max(0.0, dot(n, lightDir));
        let h = normalize(lightDir + v);
        let ndoth = max(0.0, dot(n, h));
        let spec = pow(ndoth, 64.0) * 2.0;

        // Core Volumetric Glow leaking through scales
        let coreHeat = u.zoom_params.z;
        let distToCore = length(p.xz) - 3.0; // rough distance to tube center
        let leakGlow = pow(max(0.0, 1.0 - abs(distToCore) * 1.5), 3.0) * coreHeat;
        let plasmaColor = vec3<f32>(0.0, 1.0, 1.0) * leakGlow * fbm(p * 2.0 - vec3<f32>(time));

        // Combine lighting
        let diffuse = vec3<f32>(0.1) * ndotl * groove; // very dark diffuse for chrome
        let hitCol = diffuse + envCol * fresnel * groove + vec3<f32>(spec) * mix(0.5, 1.0, groove) + plasmaColor;

        // Fog based on distance
        col = mix(hitCol, bgCol, 1.0 - exp(-0.02 * t * t));
        alpha = clamp(1.0 - exp(-0.02 * t * t) + 0.6, 0.0, 1.0);
    }

    // Temporal smoothing
    let prev = textureLoad(dataTextureC, tex_coords, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.92, 0.05 + bass * 0.02);
    alpha = mix(alpha, prev.a, 0.5);

    let displayColor = acesToneMap(col * 1.1);
    let finalAlpha = clamp(alpha * 1.2, 0.1, 0.95);
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), t < 20.0);

    // Output to texture
    textureStore(writeTexture, tex_coords, vec4<f32>(displayColor, finalAlpha));
    textureStore(writeDepthTexture, tex_coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, tex_coords, vec4<f32>(col, alpha));
}
