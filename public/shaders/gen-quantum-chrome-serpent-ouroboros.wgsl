// ----------------------------------------------------------------
// Quantum-Chrome Serpent Ouroboros
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Coil Tightness, y=Scale Density, z=Core Heat, w=Dispersion
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

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
    pos.x = pos.x * xz_rot[0].x + pos.z * xz_rot[1].x;
    pos.z = pos.x * xz_rot[0].y + pos.z * xz_rot[1].y;

    // Mouse interaction warps space
    let mx = (u.zoom_config.y * 2.0 - 1.0) * 2.0;
    let my = -(u.zoom_config.z * 2.0 - 1.0) * 2.0;
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

    // Audio reactivity makes scales flare and ripple
    let audioBump = audio * 0.3 * (1.0 + sin(theta * 5.0 - time * 2.0));
    r2 += scaleVal * 0.05 + audioBump;

    let d_torus = sdTorus(pos, vec2<f32>(r1, r2));

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
    col += vec3<f32>(0.0, 0.5, 1.0) * pow(max(0.0, sin(uv.x * 10.0 + uv.y * 5.0)), 4.0) * 0.1;
    col += vec3<f32>(0.5, 0.0, 1.0) * pow(max(0.0, cos(uv.x * 7.0 - uv.y * 12.0)), 4.0) * 0.1;
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
    let audio = u.config.y;

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
    let disp = u.zoom_params.w * 0.5;
    let rd = normalize(uv.x * cu + uv.y * cv + (1.0 / disp) * cw);

    // Render
    let rm = raymarch(ro, rd, time, audio);
    let t = rm.x;
    let mat_id = rm.y;

    var col = vec3<f32>(0.0);

    // Deep abyss background volumetric dust
    let dust = fbm(rd * 10.0 + time * 0.2) * 0.1;
    let bgCol = mix(vec3<f32>(0.01, 0.01, 0.03), vec3<f32>(0.0, 0.1, 0.2), rd.y * 0.5 + 0.5) + vec3<f32>(dust);
    col = bgCol;

    if (t < 20.0 && mat_id > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, time, audio);

        // Shading: Liquid Chrome
        let v = -rd;
        let ndotv = max(0.0, dot(n, v));

        // Fresnel reflection (Schlick)
        let f0 = vec3<f32>(0.8, 0.8, 0.9); // Silver base
        let fresnel = f0 + (1.0 - f0) * pow(1.0 - ndotv, 5.0);

        // Reflected ray
        let r = reflect(rd, n);

        // Environment map reflection
        let envCol = getEnvMap(r);

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
        let diffuse = vec3<f32>(0.1) * ndotl; // very dark diffuse for chrome
        col = diffuse + envCol * fresnel + vec3<f32>(spec) + plasmaColor;

        // Fog based on distance
        col = mix(col, bgCol, 1.0 - exp(-0.02 * t * t));
    }

    // Output to texture
    textureStore(writeTexture, tex_coords, vec4<f32>(col, 1.0));
}
