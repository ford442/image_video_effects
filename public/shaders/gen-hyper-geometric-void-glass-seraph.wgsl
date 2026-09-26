// ----------------------------------------------------------------
// Hyper-Geometric Void-Glass Seraph
// Category: generative
// ----------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Folding Scale, .y = Glass Refraction, .z = Singularity Mass, .w = Chromatic Aberration
  ripples: array<vec4<f32>, 50>,
};

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

    // KIFS Fractal folding
    var pFold = p * warpFactor;
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

        // Chromatic aberration splits the color slightly based on normal and refrVector
        let ca = u.zoom_params.w * 0.1;

        let colR = 0.5 + 0.5 * cos(6.28 * (dot(refrVector + vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.0));
        let colG = 0.5 + 0.5 * cos(6.28 * (dot(refrVector, vec3<f32>(1.0)) * 0.5 + 0.33));
        let colB = 0.5 + 0.5 * cos(6.28 * (dot(refrVector - vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.67));

        let glassBase = vec3<f32>(colR, colG, colB);

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

    // Gamma correction
    let finalCol = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, id.xy, vec4<f32>(finalCol, 1.0));
}
