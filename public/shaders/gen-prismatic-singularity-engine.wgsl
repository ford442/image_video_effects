// ----------------------------------------------------------------
// Prismatic Singularity Engine
// Category: generative
// ----------------------------------------------------------------

#include "_prelude.wgsl"

// --- Constants & Helpers ---

const PI = 3.14159265359;
const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;

// 2D Rotation Matrix
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Polynomial smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Base Gyroid function
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let pp = p * scale;
    return abs(dot(sin(pp), cos(pp.zxy)) + bias) / scale - thickness;
}

// Complex multi-layered gyroid
fn map_gyroid(p: vec3<f32>, t: f32) -> f32 {
    let g1 = sdGyroid(p, 5.0, 0.03, 0.0);
    let g2 = sdGyroid(p + vec3<f32>(t * 0.1, t * 0.2, t * 0.3), 10.0, 0.01, 0.0);
    let g3 = sdGyroid(p - vec3<f32>(t * 0.3, t * 0.1, t * 0.2), 20.0, 0.005, 0.0);
    return smin(smin(g1, g2, 0.1), g3, 0.05);
}

// ----------------------------------------------------------------
// Core SDF Mapping
// ----------------------------------------------------------------
// p: input position
// ch: channel index (0=R, 1=G, 2=B) for chromatic aberration
fn map(p: vec3<f32>, ch: i32) -> f32 {
    let mass = u.zoom_params.x;     // Singularity Mass (1.5, 0.1, 5.0)
    let twist = u.zoom_params.y;    // Twist Factor (4.0, 0.0, 10.0)
    let spec = u.zoom_params.z;     // Spectral Bleed (0.05, 0.0, 0.2)

    let time = u.config.x;

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    var q = p;

    // --- Mouse Interaction: Localized space-time bending ---
    if (u.zoom_config.w > 0.5) {
        // Map mouse UV (0..1, y=0 top) to screen space (-aspect..aspect, -1..1)
        let res = u.config.zw;
        let aspect = res.x / res.y;

        let mx = (u.zoom_config.y * 2.0 - 1.0) * aspect;
        let my = -(u.zoom_config.z * 2.0 - 1.0);
        let mPos = vec3<f32>(mx, my, 0.0);

        let distToMouse = length(q.xy - mPos.xy);
        // Pull effect
        let pullStr = smoothstep(2.0, 0.0, distToMouse);
        q = mix(q, vec3<f32>(mPos.xy, q.z), pullStr * 0.5);
    }

    // --- Rotational Distortion (Whirlpool) ---
    // Twist based on inverse distance to origin
    let distToCore = length(q);
    let invDist = 1.0 / (distToCore + 0.1);

    let rotSpeed = time * 0.5 * (1.0 + bass * 0.5);

    let qxy = q.xy * rot2D(invDist * twist + rotSpeed);
    q = vec3<f32>(qxy, q.z);

    let qxz = q.xz * rot2D(time * 0.2);
    q = vec3<f32>(q.x, q.y, qxz.y); // using qxz.y as new z, qxz.x as new x
    q = vec3<f32>(qxz.x, q.y, qxz.y);

    // Spectral offset (Chromatic Aberration)
    let offset = spec * f32(ch - 1); // ch=0 -> -spec, ch=1 -> 0, ch=2 -> +spec
    q += vec3<f32>(offset, offset, offset);

    // --- Core Shapes ---
    // Central Singularity Sphere (black hole)
    // Audio modulates the size of the event horizon
    let r_horizon = mass * 0.5 * (1.0 + bass * 0.2);
    let sdSphere = length(q) - r_horizon;

    // Gyroid Noise Structure (compressed near center)
    // Scale gyroid frequency based on distance to core
    let freq = mix(2.0, 0.5, smoothstep(0.0, 5.0, distToCore));
    let gyroid = map_gyroid(q * freq, time);

    // Combine
    let d = smin(sdSphere, gyroid, 0.5);

    return d;
}

// ----------------------------------------------------------------
// Raymarching
// ----------------------------------------------------------------

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, ch: i32) -> f32 {
    var dO = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p, ch);
        dO += dS;
        if(dO > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }
    return dO;
}

fn get_normal(p: vec3<f32>, ch: i32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, ch) - map(p - e.xyy, ch),
        map(p + e.yxy, ch) - map(p - e.yxy, ch),
        map(p + e.yyx, ch) - map(p - e.yyx, ch)
    );
    return normalize(n);
}

// ----------------------------------------------------------------
// Main Compute Shader
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let time = u.config.x;

    // Normalized device coordinates (-1 to 1)
    var uv = (vec2<f32>(id.xy) / res.xy) * 2.0 - 1.0;
    uv.y = -uv.y; // Flip Y so +y is up

    // Aspect ratio correction
    let aspect = res.x / res.y;
    uv.x *= aspect;

    // --- Camera Setup ---
    let ro = vec3<f32>(0.0, 0.0, -8.0); // Ray Origin
    let rd = normalize(vec3<f32>(uv, 1.0)); // Ray Direction

    // --- Render per Channel (Chromatic Aberration) ---
    var finalColor = vec3<f32>(0.0);
    var minDepth = MAX_DIST;

    // Render Red channel
    let dR = raymarch(ro, rd, 0);
    if(dR < MAX_DIST) {
        let p = ro + rd * dR;
        let n = get_normal(p, 0);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        // Base color for R
        let baseCol = vec3<f32>(1.0, 0.1, 0.2);
        finalColor.x = baseCol.x * diff;

        // Add glow based on distance to center
        let dist = length(p);
        finalColor.x += smoothstep(3.0, 0.0, dist) * 0.5;
        minDepth = min(minDepth, dR);
    }

    // Render Green channel
    let dG = raymarch(ro, rd, 1);
    if(dG < MAX_DIST) {
        let p = ro + rd * dG;
        let n = get_normal(p, 1);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let baseCol = vec3<f32>(0.1, 1.0, 0.3);
        finalColor.y = baseCol.y * diff;

        let dist = length(p);
        finalColor.y += smoothstep(3.0, 0.0, dist) * 0.5;
        minDepth = min(minDepth, dG);
    }

    // Render Blue channel
    let dB = raymarch(ro, rd, 2);
    if(dB < MAX_DIST) {
        let p = ro + rd * dB;
        let n = get_normal(p, 2);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let baseCol = vec3<f32>(0.2, 0.3, 1.0);
        finalColor.z = baseCol.z * diff;

        let dist = length(p);
        finalColor.z += smoothstep(3.0, 0.0, dist) * 0.5;
        minDepth = min(minDepth, dB);
    }

    // Deep void background
    if(minDepth >= MAX_DIST) {
        finalColor = vec3<f32>(0.02, 0.01, 0.05) * (1.0 - length(uv) * 0.5);
    }

    // Audio reactive flash
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    finalColor += finalColor * treble * 0.3;

    // Tone mapping
    finalColor = finalColor / (1.0 + finalColor);
    // Gamma correction
    finalColor = pow(finalColor, vec3<f32>(1.0 / 2.2));

    // --- Outputs ---
    let coord = vec2<i32>(id.xy);
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));

    // Output depth
    var outDepth = 0.0;
    if(minDepth < MAX_DIST) {
        outDepth = 1.0 / minDepth;
    }
    textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));

    // dataTextureA (example: save normals or position, here just saving final color for simplicity)
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, 1.0));
}
