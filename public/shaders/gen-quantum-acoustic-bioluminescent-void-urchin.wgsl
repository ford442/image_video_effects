// ----------------------------------------------------------------
// Quantum-Acoustic Bioluminescent Void-Urchin
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
    resolution: vec2<f32>,
    time: f32,
    frame: u32,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    view_matrix: mat4x4<f32>,
    proj_matrix: mat4x4<f32>,
    camera_pos: vec3<f32>,
    config: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI = 3.14159265359;

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise3D(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (3.0 - 2.0 * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    let res = mix(mix(mix(fract(sin(n + 0.0) * 43758.5453),
                          fract(sin(n + 1.0) * 43758.5453), f_smooth.x),
                      mix(fract(sin(n + 57.0) * 43758.5453),
                          fract(sin(n + 58.0) * 43758.5453), f_smooth.x), f_smooth.y),
                  mix(mix(fract(sin(n + 113.0) * 43758.5453),
                          fract(sin(n + 114.0) * 43758.5453), f_smooth.x),
                      mix(fract(sin(n + 170.0) * 43758.5453),
                          fract(sin(n + 171.0) * 43758.5453), f_smooth.x), f_smooth.y), f_smooth.z);
    return res;
}

fn map(p_in: vec3<f32>) -> vec2<f32> { // returns vec2(dist, material_id)
    var p = p_in;

    // Sliders
    let density = u.zoom_params.x * 2.0 + 0.5; // Spine Density and Length (0.5->1.5)
    let audioMult = u.zoom_params.y * 2.0;
    let voidFluid = u.zoom_params.w;

    let audioBase = plasmaBuffer[0].x * audioMult;

    // Fluid Void Distortion
    let warpTime = u.time * 0.2;
    p += vec3<f32>(
        noise3D(p * 0.5 + vec3<f32>(warpTime, 0.0, 0.0)),
        noise3D(p * 0.5 + vec3<f32>(0.0, warpTime, 0.0)),
        noise3D(p * 0.5 + vec3<f32>(0.0, 0.0, warpTime))
    ) * voidFluid * 0.5;

    // Mouse Interaction (Bend spines towards mouse)
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let mouse3D = vec3<f32>(mouse.x * 3.0, mouse.y * -3.0, 0.0);
    let distToMouse = length(p - mouse3D);
    let bendForce = smoothstep(3.0, 0.0, distToMouse) * 1.5;
    if (distToMouse < 3.0) {
        let dir = normalize(mouse3D - p);
        p += dir * bendForce * 0.3;
    }

    // Core sphere
    let coreRadius = 1.0 + audioBase * 0.2 + noise3D(p * 2.0 + u.time) * 0.1;
    let coreSDF = length(p) - coreRadius;

    // Spines (Polar repetition)
    let radius = length(p);
    let theta = acos(p.y / radius);
    let phi = atan2(p.z, p.x);

    let polarReps = 10.0 * density;
    let polarGridTheta = floor(theta * polarReps / PI);
    let polarGridPhi = floor(phi * polarReps / (2.0 * PI));

    let noiseVal = noise3D(vec3<f32>(polarGridTheta, polarGridPhi, u.time * 0.1));
    let spineLength = 1.5 + noiseVal * 1.0 + audioBase * 1.5;

    // Convert back to local spine coordinates
    let localTheta = fract(theta * polarReps / PI) * PI / polarReps - PI / (2.0 * polarReps);
    let localPhi = fract(phi * polarReps / (2.0 * PI)) * 2.0 * PI / polarReps - PI / polarReps;

    let localY = radius * cos(localTheta);
    let localX = radius * sin(localTheta) * cos(localPhi);
    let localZ = radius * sin(localTheta) * sin(localPhi);
    let localP = vec3<f32>(localX, localY, localZ);

    // Spine SDF (Cone-like)
    let spineRadius = 0.1 * (1.0 - smoothstep(1.0, spineLength, radius));
    let spineSDF = length(localP.xz) - spineRadius;
    let spineBound = max(spineSDF, radius - spineLength);

    // Membrane webbing
    let memNoise = noise3D(p * 3.0 - vec3<f32>(0.0, u.time * 0.5, 0.0)) * 0.2;
    let membraneSDF = length(p) - (1.2 + audioBase * 0.3 + memNoise);

    // Combine core, spines, and membrane
    let bodySDF = smin(coreSDF, spineBound, 0.5);
    let urchinSDF = smin(bodySDF, membraneSDF, 0.3);

    // Gravitational Plankton
    let planktonScale = 4.0;
    let plP = p * planktonScale + vec3<f32>(u.time, -u.time * 0.5, u.time * 0.2);
    let plID = floor(plP);
    let plLocal = fract(plP) - 0.5;
    let h = hash33(plID);
    var plSDF = length(plLocal) - (0.05 * h.x);
    plSDF /= planktonScale;

    // Plankton repulsion by audio
    let distToCore = length(p);
    if (distToCore < 2.5 + audioBase) {
        plSDF += 0.2 * (2.5 + audioBase - distToCore);
    }

    if (urchinSDF < plSDF) {
        return vec2<f32>(urchinSDF, 1.0); // Material 1: Urchin
    } else {
        return vec2<f32>(plSDF, 2.0); // Material 2: Plankton
    }
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let coord = vec2<i32>(GlobalInvocationID.xy);
    let res = vec2<f32>(u.resolution);
    if (f32(coord.x) >= res.x || f32(coord.y) >= res.y) {
        return;
    }

    var uv = (vec2<f32>(coord) - 0.5 * res) / min(res.x, res.y);

    let time = u.time;
    let audioBase = plasmaBuffer[0].x * u.zoom_params.y * 2.0;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, 6.0 - audioBase * 0.5);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Mouse rotation
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let rotXMat = rotX(mouse.y * PI);
    let rotYMat = rotY(-mouse.x * PI + time * 0.2);
    ro = rotXMat * rotYMat * ro;
    rd = rotXMat * rotYMat * rd;

    // Raymarching
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);

    let maxSteps = 100;
    let maxDist = 20.0;
    let surfDist = 0.001;

    var hit = false;
    var matID = 0.0;
    var p = vec3<f32>(0.0);

    for (var i = 0; i < maxSteps; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d.x < surfDist) {
            hit = true;
            matID = d.y;
            break;
        }
        if (t > maxDist) {
            break;
        }
        t += d.x;

        // Volumetric glow accumulation
        if (d.y == 1.0) { // Glow from urchin
            let glowCol = mix(vec3<f32>(0.1, 0.0, 0.5), vec3<f32>(0.0, 0.8, 0.8), u.zoom_params.z);
            glow += glowCol * (0.01 / (1.0 + d.x * d.x * 20.0)) * (1.0 + audioBase * 2.0);
        } else if (d.y == 2.0) { // Glow from plankton
            glow += vec3<f32>(1.0, 0.8, 0.2) * (0.005 / (1.0 + d.x * d.x * 50.0));
        }
    }

    if (hit) {
        let n = calcNormal(p);
        let v = -rd;

        let lightDir = normalize(vec3<f32>(1.0, 2.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        if (matID == 1.0) { // Urchin Material
            let baseColor = mix(vec3<f32>(0.05, 0.0, 0.2), vec3<f32>(0.0, 0.3, 0.4), clamp(length(p) * 0.2, 0.0, 1.0));
            let emitColor = mix(vec3<f32>(0.1, 0.0, 0.5), vec3<f32>(0.0, 0.9, 0.7), u.zoom_params.z);

            // Bioluminescence
            let lum = smoothstep(0.5, 2.5, length(p)) * (0.5 + audioBase);
            let emit = emitColor * lum + fresnel * vec3<f32>(0.5, 1.0, 1.0);

            col = baseColor * (diff * 0.5 + 0.5) + emit;

        } else if (matID == 2.0) { // Plankton Material
            col = vec3<f32>(1.0, 0.9, 0.3) * (1.0 + audioBase * 2.0);
        }

        // Soft shadows / Subsurface faux
        let ao = clamp(map(p + n * 0.1).x / 0.1, 0.0, 1.0);
        col *= ao;
    }

    // Add volumetric glow
    col += glow;

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
