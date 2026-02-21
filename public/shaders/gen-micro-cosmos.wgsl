// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Density, y=FluidSpeed, z=GlowIntensity, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// Micro-Cosmos - Generative Shader

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p/r);
    let k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

// Smooth Min for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 2D Rotation
fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Hash function for random values
fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.543))) * 43758.5453);
}

// Scene Map function
fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let time = u.config.x;

    // Zoom params mapping
    let densityParams = u.zoom_params.x; // 0.0 - 1.0
    let flowSpeed = u.zoom_params.y;     // 0.0 - 1.0

    // Global Movement (Fluid Drift)
    p.y += time * (0.2 + flowSpeed * 0.5);
    p.x += sin(time * 0.1) * 0.5 + time * flowSpeed * 0.1;

    // Domain Repetition
    // Adjust grid size based on density. Higher density -> smaller grid cells.
    let gridSize = mix(6.0, 3.0, densityParams);

    let id = floor(p / gridSize);
    let q = (fract(p / gridSize) - 0.5) * gridSize;

    // Randomization per cell
    let rand = hash(id);

    // Vary position within cell
    let offset = (vec3<f32>(rand, fract(rand * 12.3), fract(rand * 45.6)) - 0.5) * gridSize * 0.4;
    var localP = q - offset;

    // Random rotation
    localP.xy = rotate2D(localP.xy, time * (0.1 + rand * 0.2) + rand * 6.28);
    localP.xz = rotate2D(localP.xz, time * (0.05 + rand * 0.1));

    // Cell Body (Ellipsoid)
    // Random scale
    let scale = 0.5 + rand * 0.5;
    let r = vec3<f32>(1.0, 1.5, 0.8) * scale;

    // Wobble effect
    let wobble = sin(localP.x * 3.0 + time * 2.0) * sin(localP.y * 3.0 + time) * sin(localP.z * 3.0) * 0.1 * flowSpeed;

    var d = sdEllipsoid(localP, r) + wobble;

    // Organelles (Spheres inside)
    let organellePos = localP - vec3<f32>(0.2, 0.1, 0.0) * scale;
    let d_organelle = sdSphere(organellePos, 0.3 * scale);

    // Material ID: 1.0 = Cell Membrane, 2.0 = Organelle
    var mat = 1.0;

    // Use smin to blend slightly if they intersect
    let bump = sin(localP.x * 10.0) * sin(localP.y * 10.0) * sin(localP.z * 10.0) * 0.02;
    d += bump;

    return vec2<f32>(d, mat);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.1;
    var mat = 0.0;
    for(var i=0; i<80; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 50.0) { break; }
        t += d * 0.8; // Understep for better organic shapes
    }
    return vec2<f32>(t, mat);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera Setup
    let time = u.config.x;

    // Mouse Interaction for Camera
    let mouse = u.zoom_config.yz;
    let rotX = (mouse.x - 0.5) * 4.0;
    let rotY = (mouse.y - 0.5) * 2.0;

    // Camera Position - drifting slowly
    let ro = vec3<f32>(sin(time * 0.1) * 2.0, 0.0, -8.0 + time * 0.5);
    // Look At
    let ta = vec3<f32>(0.0, 0.0, time * 0.5);

    // Camera Basis
    let fw = normalize(ta - ro);
    let rt = normalize(cross(fw, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(rt, fw);

    // Apply mouse rotation to ray direction
    let rd_pre = normalize(fw + rt * uv.x + up * uv.y);
    var rd = rd_pre;

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    // Environment/Fluid Color (Deep Blue/Purple)
    let colorShift = u.zoom_params.w;
    var bgColor = vec3<f32>(0.02, 0.05, 0.1);
    // Apply color shift
    bgColor = mix(bgColor, vec3<f32>(0.1, 0.02, 0.08), colorShift); // Shift to purple

    var color = bgColor;

    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting vectors
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let viewDir = -rd;

        // Basic Diffuse
        let diff = max(dot(n, lightDir), 0.0);

        // Rim Light (Fresnel) - Crucial for microscopic look
        let rim = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);
        let glowIntensity = u.zoom_params.z;

        // Base Color of Cell
        var objColor = vec3<f32>(0.4, 0.8, 0.9); // Cyan-ish
        if (colorShift > 0.5) {
             objColor = vec3<f32>(0.9, 0.4, 0.8); // Magenta-ish
        }

        // Translucency / SSS approximation
        // Invert normal dot light for "backlighting"
        let sss = max(0.0, dot(-n, lightDir)) * 0.5;

        // Combine
        color = objColor * (diff * 0.2 + 0.1) + // Ambient + Diffuse
                vec3<f32>(0.8, 0.9, 1.0) * rim * glowIntensity * 1.5 + // Rim Glow
                objColor * sss * 0.5; // Backlight

        // Inner Organelle Glow (Fake)
        let innerGlow = sin(p.x * 20.0) * sin(p.y * 20.0) * sin(p.z * 20.0);
        if (innerGlow > 0.8) {
             color += vec3<f32>(1.0, 0.8, 0.4) * 0.5; // Orange specks
        }

        // Distance Fog (Fluid density)
        let fogAmount = 1.0 - exp(-t * 0.08);
        color = mix(color, bgColor, fogAmount);
    }

    // Background Particles (Marine Snow)
    let speckle = hash(vec3<f32>(uv.x, uv.y, time * 0.1));
    if (speckle > 0.995) {
        color += vec3<f32>(0.5);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 50.0, 0.0, 0.0, 0.0));
}
