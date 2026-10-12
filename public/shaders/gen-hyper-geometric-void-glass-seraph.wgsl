// ═══════════════════════════════════════════════════════════════════
//  Hyper-Geometric Void-Glass Seraph
//  Category: generative
//  Features: upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: inner void core rotation; chromatic dispersion tied to KIFS iterations
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// zoom_params: .x = Folding Scale, .y = Glass Refraction, .z = Singularity Mass, .w = Chromatic Aberration

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D rotation based on a 2D angle (mouse input)
fn rot3D(p: vec3<f32>, angle: vec2<f32>) -> vec3<f32> {
    let rx = rot(angle.y);
    let ry = rot(angle.x);
    var p2 = p;

    let pyz = rx * vec2<f32>(p2.y, p2.z);
    p2.y = pyz.x;
    p2.z = pyz.y;

    let pxz = ry * vec2<f32>(p2.x, p2.z);
    p2.x = pxz.x;
    p2.z = pxz.y;

    return p2;
}

fn map(p_in: vec3<f32>, time: f32) -> vec2<f32> {
    var p = p_in;

    // Global rotation driven by mouse
    let mouseAngle = vec2<f32>((u.zoom_config.y - 0.5) * 6.28, (u.zoom_config.z - 0.5) * 3.14);
    p = rot3D(p, mouseAngle);

    // The central singularity
    let singRadius = u.zoom_params.z * 0.5;
    var dSing = length(p) - singRadius;

    // Space inversion (rough approximation of bending) near the singularity
    let distToCenter = length(p);
    let warpFactor = 1.0 + (u.zoom_params.z * 0.5) / (distToCenter + 0.1);

    // Idea 1: Inner void core rotation - twist space based on proximity to the singularity
    let twist = smoothstep(1.5, 0.0, dSing) * time * 2.5;
    let pRot = rot3D(p, vec2<f32>(-twist, twist * 0.5));

    // KIFS Fractal folding
    var pFold = pRot * warpFactor;
    let foldScale = u.zoom_params.x;
    var iters = 0.0;

    for(var i = 0; i < 6; i = i + 1) {
        pFold = abs(pFold) - vec3<f32>(1.0) * foldScale;
        let r = rot(time * 0.1 + f32(i) * 0.2);

        let pxy = r * vec2<f32>(pFold.x, pFold.y);
        pFold.x = pxy.x;
        pFold.y = pxy.y;

        let pyz = r * vec2<f32>(pFold.y, pFold.z);
        pFold.y = pyz.x;
        pFold.z = pyz.y;

        iters = iters + 1.0;
    }

    // KIFS distance estimator
    let dKifs = length(pFold) * pow(foldScale, -iters) - 0.05;

    // Combine the structures. Max for intersection to cut the fractal out around singularity
    // Min to show both, let's do a smooth min to merge them
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (dKifs - dSing) / k, 0.0, 1.0);
    let d = mix(dKifs, dSing, h) - k * h * (1.0 - h);

    // Return distance and material ID (iterations used for edge glow)
    return vec2<f32>(d, iters);
}

fn getNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time).x - map(p - e.xyy, time).x,
        map(p + e.yxy, time).x - map(p - e.yxy, time).x,
        map(p + e.yyx, time).x - map(p - e.yyx, time).x
    );
    return normalize(n);
}

// Simulated refraction and chromatic aberration
fn renderGlass(ro: vec3<f32>, rd: vec3<f32>, time: f32) -> vec3<f32> {
    var p: vec3<f32>;
    var dO: f32 = 0.0;
    var hit: bool = false;
    var res: vec2<f32>;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        p = ro + rd * dO;
        res = map(p, time);
        dO = dO + res.x;
        if (res.x < SURF_DIST) {
            hit = true;
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p, time);
        let viewDir = normalize(ro - p);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));

        // Fresnel Schlick approximation
        let f0 = 0.04;
        let cosTheta = max(dot(n, viewDir), 0.0);
        let fresnel = f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);

        // Specular highlight
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), 32.0);

        // Refraction color (mocked with a gradient based on depth and normal)
        let refrIndex = u.zoom_params.y;
        let refrVector = refract(-viewDir, n, 1.0 / (1.0 + refrIndex));

        // Idea 2: chromatic dispersion tied to KIFS iterations (fractal depth)
        let kifsDepth = res.y;
        let ca = u.zoom_params.w * 0.1 * (1.0 + kifsDepth * 0.8);

        let colR = 0.5 + 0.5 * cos(6.28 * (dot(refrVector + vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.0));
        let colG = 0.5 + 0.5 * cos(6.28 * (dot(refrVector, vec3<f32>(1.0)) * 0.5 + 0.33));
        let colB = 0.5 + 0.5 * cos(6.28 * (dot(refrVector - vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.67));

        let rawGlass = vec3<f32>(colR, colG, colB);
        let deepViolet = vec3<f32>(0.4, 0.0, 0.8);
        let glassBase = mix(rawGlass, deepViolet, smoothstep(3.0, 6.0, kifsDepth));

        // Edge glow based on iteration count (res.y)
        let edgeGlow = smoothstep(5.0, 6.0, res.y) * vec3<f32>(0.0, 1.0, 1.0); // Cyan glow

        // Combine
        col = mix(glassBase, vec3<f32>(1.0), fresnel) + vec3<f32>(spec) + edgeGlow * 0.5;

        // Attenuate by distance
        col = col * exp(-0.1 * dO);
    }

    return col;
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let uv = vec2<f32>(id.xy) / vec2<f32>(dimensions);
    let uv_centered = (uv - 0.5) * 2.0;
    let aspect = f32(dimensions.x) / f32(dimensions.y);
    let p_screen = vec2<f32>(uv_centered.x * aspect, uv_centered.y);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(p_screen, 1.0));

    // Audio reactivity modulating time
    let bass = extraBuffer[0];
    let time = u.config.x + bass * 0.2;

    let col = renderGlass(ro, rd, time);

    let finalCol = acesToneMap(col);
    let alpha = clamp(length(col), 0.05, 0.98);

    textureStore(dataTextureA, id.xy, vec4<f32>(finalCol, alpha));
    textureStore(writeTexture, id.xy, vec4<f32>(finalCol, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(clamp(1.0 - col.g, 0.0, 1.0), 0.0, 0.0, 0.0));
}
