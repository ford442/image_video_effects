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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Density, y=FluidSpeed, z=GlowIntensity, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// Micro-Cosmos - Generative Shader

var<private> g_audio: vec3<f32>;

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p/r);
    let k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
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
    var time = u.config.x;

    // Zoom params mapping
    let densityParams = u.zoom_params.x; // 0.0 - 1.0
    let flowSpeed = u.zoom_params.y;     // 0.0 - 1.0

    // Audio-driven helical current and fast forward transport. Both are
    // closed-form, avoiding fixed-per-frame integration.
    let currentAngle = time * (0.8 + flowSpeed * 1.4 + g_audio.y * 0.35) + p.z * 0.22;
    let currentXZ = rotate2D(p.xz, currentAngle * 0.28);
    p.x = currentXZ.x + sin(currentAngle) * (0.35 + g_audio.x * 0.18);
    p.z = currentXZ.y + time * (1.2 + flowSpeed * 1.8);
    p.y += time * (0.45 + flowSpeed * 0.9) + cos(currentAngle) * (0.25 + g_audio.z * 0.12);

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
    let temp_localP_xy = rotate2D(localP.xy, time * (0.7 + flowSpeed + rand * 0.6 + g_audio.y * 0.2) + rand * 6.28);
    localP.x = temp_localP_xy.x;
    localP.y = temp_localP_xy.y;

    let temp_localP_xz = rotate2D(localP.xz, time * (0.45 + flowSpeed * 0.7 + rand * 0.35));
    localP.x = temp_localP_xz.x;
    localP.z = temp_localP_xz.y;


    // Cell Body (Ellipsoid)
    // Random scale
    let scale = 0.5 + rand * 0.5;
    let r = vec3<f32>(1.0, 1.5, 0.8) * scale;

    // Wobble effect
    let wobble = sin(localP.x * 3.0 + time * 2.0) * sin(localP.y * 3.0 + time) * sin(localP.z * 3.0) * 0.1 * flowSpeed;

    var d = sdEllipsoid(localP, r) + wobble;

    // Note: Organelles are handled via procedural shading (fake inner glow) rather than SDF geometry
    // to simulate translucency without complex transparency sorting.

    // Small surface bump for organic texture
    let bump = sin(localP.x * 10.0) * sin(localP.y * 10.0) * sin(localP.z * 10.0) * 0.02;
    d += bump;

    // Material ID: 1.0 = Cell Membrane
    var mat = 1.0;

    return vec2<f32>(d, mat);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
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
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 50.0) { break; }
        t += d * 0.8; // Understep for better organic shapes
    }
    return vec2<f32>(t, mat);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let screenUV = vec2<f32>(global_id.xy) / resolution;

    // Camera Setup
    var time = u.config.x;
    g_audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    // Mouse Interaction for Camera
    var mouse = u.zoom_config.yz;
    let rotX = (mouse.x - 0.5) * 4.0;
    let rotY = (mouse.y - 0.5) * 2.0;

    // Camera Position - drifting slowly
    let flowSpeed = u.zoom_params.y;
    let ro = vec3<f32>(sin(time * 0.75) * (1.0 + g_audio.y * 0.25), cos(time * 0.55) * 0.4, -8.0 + time * (1.4 + flowSpeed * 0.8));
    // Look At
    let ta = vec3<f32>(sin(time * 0.65) * 0.5, cos(time * 0.5) * 0.3, time * (1.4 + flowSpeed * 0.8));

    // Camera Basis
    let fw = normalize(ta - ro);
    let rt = normalize(cross(fw, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(rt, fw);

    // Apply mouse rotation to ray direction
    // Simple look offset based on mouse
    let rd_pre = normalize(fw + rt * uv.x + up * uv.y);
    // Applying mouse rotation (optional, but requested in plan features "mouse-driven")
    // Here we use mouse to perturb the ray direction slightly
    let rd = normalize(rd_pre + rt * (mouse.x - 0.5) * 0.5 + up * (mouse.y - 0.5) * 0.5);

    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;

    // Environment/Fluid Color (Deep Blue/Purple)
    let colorShift = u.zoom_params.w;
    var bgColor = vec3<f32>(0.02, 0.05, 0.1);
    // Apply color shift
    bgColor = mix(bgColor, vec3<f32>(0.1, 0.02, 0.08), colorShift); // Shift to purple

    var color = bgColor;

    if (t < 50.0) {
        var p = ro + rd * t;
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

        let membraneRunner = pow(max(0.0, sin(atan2(p.y, p.x) * 7.0 + p.z * 9.0 - time * (15.0 + flowSpeed * 3.0))), 10.0);
        color += vec3<f32>(0.2, 0.9, 1.0) * membraneRunner * (0.15 + g_audio.x * 0.4) * glowIntensity;

        // Inner Organelle Glow (Fake)
        // Use world position to create procedural noise inside
        let innerGlow = sin(p.x * 20.0) * sin(p.y * 20.0) * sin(p.z * 20.0);
        if (innerGlow > 0.8) {
             color += vec3<f32>(1.0, 0.8, 0.4) * 0.5 * glowIntensity; // Orange specks
        }

        // Distance Fog (Fluid density)
        let fogAmount = 1.0 - exp(-t * 0.08);
        color = mix(color, bgColor, fogAmount);
    }

    // Smooth traveling marine snow with fixed particle identities.
    var marineSnow = 0.0;
    for (var si = 0; si < 12; si++) {
        let fs = f32(si);
        let seed = hash(vec3<f32>(fs, fs * 3.1, 7.2));
        let travel = fract(seed + time * (0.06 + flowSpeed * 0.035 + seed * 0.025));
        let snowPos = vec2<f32>(fract(seed * 7.31 + sin(time * 0.7 + fs) * 0.04), 1.1 - travel * 1.2);
        let delta = (screenUV - snowPos) * vec2<f32>(resolution.x / resolution.y, 1.0);
        marineSnow += exp(-dot(delta, delta) * 9000.0) * (0.35 + seed * 0.65);
    }
    color += vec3<f32>(0.35, 0.55, 0.7) * marineSnow;

    // Clicks spawn short-lived microbe blooms instead of mutating persistent state.
    var bloom = 0.0;
    let aspectFix = vec2<f32>(resolution.x / resolution.y, 1.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.2) { continue; }
        let delta = (screenUV - ripple.xy) * aspectFix;
        let radius = length(delta);
        let membrane = exp(-abs(radius - age * 0.32) * 80.0);
        let colonies = pow(max(0.0, sin(atan2(delta.y, delta.x) * 9.0 + age * 14.0)), 12.0) * exp(-abs(radius - age * 0.24) * 35.0);
        bloom += (membrane + colonies * 0.7) * (1.0 - age / 2.2);
    }
    color += vec3<f32>(0.25, 1.0, 0.7) * bloom * (0.35 + u.zoom_params.z * 0.2);

    // Helical advection turns prior membranes into visible organism wakes.
    let currentDir = normalize(vec2<f32>(cos(time * 0.8), sin(time * 0.8)) + vec2<f32>(0.001));
    let historyUV = clamp(screenUV - currentDir * (0.004 + flowSpeed * 0.005), vec2<f32>(0.002), vec2<f32>(0.998));
    let previous = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0).rgb;
    let temporal = clamp(max(color, previous * 0.89), vec3<f32>(0.0), vec3<f32>(5.0));
    let hit = t < 50.0;
    let depth = select(1.0, clamp(t / 50.0, 0.0, 0.995), hit);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(temporal, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(temporal, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
