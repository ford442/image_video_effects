// ═══════════════════════════════════════════════════════════════
// Hyper Labyrinth - 4D Maze Visualization
// Category: generative
// Features: 4D geometry, raymarching, neon aesthetics
// ═══════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data

// ---------------------------------------------------
struct Uniforms {
    config: vec4<f32>, // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>, // x=Param1 (scale), y=Param2 (morph speed), z=Param3 (glow), w=Param4 (thickness)
    ripples: array<vec4<f32>, 50>,
};

// 4D Rotation in XW plane
fn rotate4D(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        p.x * c - p.w * s,
        p.y,
        p.z,
        p.x * s + p.w * c
    );
}

// Map function (SDF) - merged best of both
fn map(pos3: vec3<f32>) -> vec2<f32> {
    // Transform 3D pos to 4D (small w for "thickness")
    var p4 = vec4<f32>(pos3, 1.0);

    // 4D rotation driven by time/params
    let speed = mix(0.1, 2.0, u.zoom_params.y); // morph speed
    let time = u.config.x * speed;
    p4 = rotate4D(p4, time);

    // Extra YZ rotation for nice 3D orbiting feel (from main)
    let rotYZ = u.config.x * 0.1;
    let cy = cos(rotYZ);
    let sy = sin(rotYZ);
    let tempY = p4.y * cy - p4.z * sy;
    let tempZ = p4.y * sy + p4.z * cy;
    p4.y = tempY;
    p4.z = tempZ;

    // Gyroid-based 4D maze
    let scale = mix(1.0, 5.0, u.zoom_params.x);
    let q = p4 * scale;
    let val = sin(q.x) * cos(q.y) + sin(q.y) * cos(q.z) + sin(q.z) * cos(q.w) + sin(q.w) * cos(q.x);

    // Wall thickness
    let thickness = mix(0.1, 1.2, u.zoom_params.w);
    let d = (abs(val) - thickness * 0.5) / scale; // proper scale-corrected distance

    return vec2<f32>(d * 0.5, 1.0); // material ID = 1.0 for walls
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

// Raymarch with material support (kept from feature for future extensibility)
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var m = 0.0; // 0 = miss
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        if (d < 0.001 || t > 50.0) {
            if (d < 0.001) { m = res.y; }
            break;
        }
        t += d;
    }
    return vec2<f32>(t, m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // === CAMERA (best of both: main's clean spherical + feature's organic drift) ===
    let mouse = u.zoom_config.yz;
    let angleX = (mouse.x - 0.5) * 6.2832;
    let angleY = (mouse.y - 0.5) * 3.1416;
    let camDist = 8.0;

    var ro = vec3<f32>(
        camDist * cos(angleY) * sin(angleX),
        camDist * sin(angleY),
        camDist * cos(angleY) * cos(angleX)
    );

    // Gentle camera drift for more life
    let time = u.config.x;
    let drift = vec3<f32>(sin(time * 0.1), cos(time * 0.15), sin(time * 0.07)) * 0.6;
    ro += drift;

    let target = vec3<f32>(0.0);
    let fwd = normalize(target - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    var color = vec3<f32>(0.0);

    if (mat > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let diff = max(dot(n, lightDir), 0.0);
        let amb = 0.12;

        // Dark metallic base
        var surfCol = vec3<f32>(0.06, 0.05, 0.09);

        // === NEON GLOW / VEINS (feature's beautiful pattern + main's consistency) ===
        let glowIntensity = mix(0.6, 3.5, u.zoom_params.z);

        let speed = mix(0.1, 2.0, u.zoom_params.y);
        let time4d = u.config.x * speed;

        var p4 = vec4<f32>(p, 1.0);
        p4 = rotate4D(p4, time4d);

        // Match the map's extra rotation
        let rotYZ = u.config.x * 0.1;
        let cy = cos(rotYZ);
        let sy = sin(rotYZ);
        let tempY = p4.y * cy - p4.z * sy;
        let tempZ = p4.y * sy + p4.z * cy;
        p4.y = tempY;
        p4.z = tempZ;

        let scale = mix(1.0, 5.0, u.zoom_params.x);
        let q = p4 * scale * 2.0;
        let pattern = sin(q.x) * sin(q.y) * sin(q.z) * sin(q.w);

        let pulse = 0.5 + 0.5 * sin(time * 2.2 + p.x * 1.3 + p.z * 0.7);

        var glowCol = vec3<f32>(0.0, 0.85, 1.0); // cyan
        if (pattern > 0.0) {
            glowCol = vec3<f32>(1.0, 0.25, 0.9); // magenta
        }

        let patternFactor = smoothstep(0.35, 0.55, abs(pattern));
        surfCol += glowCol * patternFactor * glowIntensity * pulse;

        // Cyber rim lighting
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        surfCol += vec3<f32>(0.3, 0.5, 1.2) * fresnel * 2.8;

        color = surfCol * (diff * 0.85 + amb);

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.065);
        let fogColor = vec3<f32>(0.008, 0.008, 0.022);
        color = mix(color, fogColor, fogAmount);
    } else {
        // Deep void background
        color = vec3<f32>(0.0, 0.0, 0.045);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 50.0, 0.0, 0.0, 0.0));
}