// ----------------------------------------------------------------
// Chronomorphic Glass Tesseract
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
  zoom_params: vec4<f32>,  // .x = Shatter, .y = Refraction, .z = Color Shift, .w = Mouse Gravity
  ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Rotate 3D space
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// --- SDF & ALGORITHM ---
fn map(pos: vec3<f32>, time: f32, shatter: f32, audio: f32, mousePos: vec2<f32>, gravity: f32) -> f32 {
    var p = pos;

    // Mouse distortion (Gravity well)
    // Convert pos.xy to similar space, maybe pos is in -1 to 1?
    // mouse_uv is 0 to 1
    let mouseSpace = (mousePos - 0.5) * 2.0 * vec2<f32>(1.0, -1.0);
    let mouseDist = length(p.xy - mouseSpace);
    let g = gravity * 0.5 * exp(-mouseDist * 2.0);
    p *= 1.0 + g;
    p.z += g * 0.5;

    // Audio-reactive shatter
    let noise = hash12(p.xy * 10.0 + time) * 2.0 - 1.0;
    let shatterEffect = noise * shatter * 0.1 * audio;

    p = p + shatterEffect;

    // Recursive space folding
    for (var i = 0; i < 4; i++) {
        p = abs(p) - vec3<f32>(0.5 + sin(time * 0.2 + f32(i)) * 0.2 + audio * 0.1);
        let r = rot(time * 0.1 + f32(i));
        let pxy = r * p.xy;
        p = vec3<f32>(pxy.x, pxy.y, p.z);

        let pyz = rot(time * 0.15 - f32(i)) * p.yz;
        p = vec3<f32>(p.x, pyz.x, pyz.y);
    }

    // Box SDF
    let d = length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0))) - 0.1;
    return d;
}

fn getNormal(p: vec3<f32>, time: f32, shatter: f32, audio: f32, mousePos: vec2<f32>, gravity: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, shatter, audio, mousePos, gravity);
    let n = d - vec3<f32>(
        map(p - e.xyy, time, shatter, audio, mousePos, gravity),
        map(p - e.yxy, time, shatter, audio, mousePos, gravity),
        map(p - e.yyx, time, shatter, audio, mousePos, gravity)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Normalized coordinates (-1 to 1) with aspect ratio correction
    var p = uv * 2.0 - 1.0;
    p.y = -p.y; // Flip Y
    p.x *= f32(dims.x) / f32(dims.y);

    let time = u.config.x;

    // Read audio data from extraBuffer
    let bass = extraBuffer[0];
    let mid = extraBuffer[1];
    let audio = bass * 0.6 + mid * 0.4;

    // Read params
    let shatter = u.zoom_params.x;
    let refraction = u.zoom_params.y; // typically 1.33 for water, 1.5 for glass, etc.
    let colorShift = u.zoom_params.z;
    let gravity = u.zoom_params.w;
    let mousePos = u.zoom_config.yz;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.5);
    let lookAtTarget = vec3<f32>(0.0, 0.0, 0.0);
    let w = normalize(lookAtTarget - ro);
    let u_dir = normalize(cross(w, vec3<f32>(0.0, 1.0, 0.0)));
    let v_dir = cross(u_dir, w);
    var rd = normalize(p.x * u_dir + p.y * v_dir + 1.5 * w);

    // Rotate camera based on time
    let camRot = rot(time * 0.1);
    let ro_xz = camRot * ro.xz;
    let roRot = vec3<f32>(ro_xz.x, ro.y, ro_xz.y);

    let targetRot = vec3<f32>(0.0, 0.0, 0.0);
    let wRot = normalize(targetRot - roRot);
    let u_dirRot = normalize(cross(wRot, vec3<f32>(0.0, 1.0, 0.0)));
    let v_dirRot = cross(u_dirRot, wRot);
    let rdRot = normalize(p.x * u_dirRot + p.y * v_dirRot + 1.5 * wRot);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var pos = roRot;

    // Steps for volumetric/glass rendering
    var hit = false;
    var min_d = 1000.0;
    var i_step = 0;
    for (var i = 0; i < 100; i++) {
        pos = roRot + rdRot * t;
        d = map(pos, time, shatter, audio, mousePos, gravity);
        min_d = min(min_d, d);
        if (d < 0.001) {
            hit = true;
            i_step = i;
            break;
        }
        t += d * 0.5; // slow down for more precise folding
        if (t > 10.0) {
            break;
        }
    }

    var color = vec3<f32>(0.0);

    // Background color based on distance
    let bg_color = vec3<f32>(0.05, 0.0, 0.1) * (1.0 - length(p) * 0.5);
    color = bg_color;

    if (hit) {
        let n = getNormal(pos, time, shatter, audio, mousePos, gravity);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let refl = reflect(rdRot, n);
        let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);

        // Refraction (fake)
        let refractDir = refract(rdRot, n, 1.0 / refraction);
        let refractedPos = pos + refractDir * 0.1;
        let refractDist = map(refractedPos, time, shatter, audio, mousePos, gravity);
        let absorb = exp(-refractDist * 5.0);

        // Chromatic dispersion (simple offset)
        let r_refract = map(pos + refractDir * 0.1, time, shatter, audio, mousePos, gravity);
        let g_refract = map(pos + refractDir * 0.11, time, shatter, audio, mousePos, gravity);
        let b_refract = map(pos + refractDir * 0.12, time, shatter, audio, mousePos, gravity);

        let dispersionColor = vec3<f32>(r_refract, g_refract, b_refract) * 2.0;

        // Base color transition
        let baseColor1 = vec3<f32>(0.1, 0.3, 0.8); // quantum blue
        let baseColor2 = vec3<f32>(0.8, 0.2, 0.8); // striking purple
        let baseColor3 = vec3<f32>(1.0, 0.2, 0.5); // hot neon pink

        let colorMix = sin(length(pos) * 2.0 + time + colorShift * 3.14) * 0.5 + 0.5;
        let objColor = mix(mix(baseColor1, baseColor2, colorMix), baseColor3, sin(time * 0.5) * 0.5 + 0.5);

        // Subsurface scattering proxy (depth based)
        let sss = vec3<f32>(1.0, 0.5, 0.2) * (1.0 - t / 10.0) * 0.5;

        color = objColor * diff * 0.5 + spec * vec3<f32>(1.0) + dispersionColor * 0.2 + sss * absorb * 2.0;

        // Edge glow / Fresnel
        let fresnel = pow(1.0 - max(dot(n, -rdRot), 0.0), 3.0);
        color += objColor * fresnel * 2.0;
    } else {
        // Add some glowing aura around the object
        let glow = exp(-min_d * 2.0) * vec3<f32>(0.2, 0.5, 1.0) * (0.5 + audio * 0.5);
        color += glow;
    }

    // Tone mapping and gamma correction
    color = color / (1.0 + color);
    color = pow(color, vec3<f32>(1.0 / 2.2));

    let finalColor = vec4<f32>(color, 1.0);
    textureStore(writeTexture, global_id.xy, finalColor);

    // Write to required buffers
    let depth = min(t / 20.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, finalColor);
}