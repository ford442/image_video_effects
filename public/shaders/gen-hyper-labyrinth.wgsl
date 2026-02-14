// ═══════════════════════════════════════════════════════════════
//  Hyper Labyrinth - 4D Maze Visualization
//  Category: generative
//  Features: 4D geometry, raymarching, neon aesthetics
// ═══════════════════════════════════════════════════════════════

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

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
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

// Map function (SDF)
fn map(pos3: vec3<f32>) -> vec2<f32> {
    // 1. Transform 3D pos to 4D (w depends on time or constant)
    // We can use a fixed w or modulate it
    var p4 = vec4<f32>(pos3, 1.0);

    // 2. Apply 4D rotation driven by time/params
    // u.zoom_params.y is Morph Speed
    let speed = mix(0.1, 2.0, u.zoom_params.y);
    let time = u.config.x * speed;

    // Rotate in XW and YW for more complexity
    p4 = rotate4D(p4, time);

    // 3. Maze generation logic (Gyroid)
    // u.zoom_params.x is Scale/Density
    let scale = mix(1.0, 5.0, u.zoom_params.x);
    let q = p4 * scale;

    let val = sin(q.x)*cos(q.y) + sin(q.y)*cos(q.z) + sin(q.z)*cos(q.w) + sin(q.w)*cos(q.x);

    // Thickness threshold
    // u.zoom_params.w is Wall Thickness
    let thickness = mix(0.1, 1.2, u.zoom_params.w);
    let d = abs(val) - thickness * 0.5;

    // Scale distance back
    // 0.5 factor is a conservative estimate for Lipschitz constant of gyroid
    return vec2<f32>(d * 0.5 / scale, 1.0); // 1.0 = material ID
}

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
    var t = 0.0;
    var m = -1.0;
    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        if(d < 0.001 || t > 50.0) {
             if (d < 0.001) { m = res.y; }
             break;
        }
        t += d;
    }
    if (t > 50.0) { m = -1.0; }
    return vec2<f32>(t, m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Camera Setup
    // Mouse controls orbit
    let mouse = u.zoom_config.yz;

    // Orbit camera parameters
    let radius = 6.0;
    let theta = mouse.x * 6.2831;
    let phi = mix(0.1, 3.14159 * 0.9, mouse.y); // Limit phi to avoid gimbal lock at poles

    let camPos = vec3<f32>(
        radius * sin(phi) * cos(theta),
        radius * cos(phi),
        radius * sin(phi) * sin(theta)
    );

    // Slight movement over time
    let drift = vec3<f32>(sin(time * 0.1), cos(time * 0.15), sin(time * 0.07));
    let ro = camPos + drift;

    let target = vec3<f32>(0.0, 0.0, 0.0);

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

        // Basic lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let diff = max(dot(n, lightDir), 0.0);

        // Base color (Dark metallic)
        var surfCol = vec3<f32>(0.05, 0.05, 0.08);

        // 4D coloring / Glow
        // We can re-evaluate the gyroid value to see how close we are to "center" of the wall
        // But map() returns distance to surface.
        // Let's use the normal or position to drive color.

        // Use normal to mix colors
        let n_mix = n * 0.5 + 0.5;

        // Neon Glow logic
        // u.zoom_params.z is Glow Intensity
        let glowIntensity = mix(0.5, 3.0, u.zoom_params.z);

        // Create "veins" of light
        // Use a secondary pattern on the surface
        let scale = mix(1.0, 5.0, u.zoom_params.x);
        let p4 = rotate4D(vec4<f32>(p, 1.0), time);
        let q = p4 * scale * 2.0;
        let pattern = sin(q.x)*sin(q.y)*sin(q.z)*sin(q.w);

        // Pulse glow
        let pulse = 0.5 + 0.5 * sin(time * 2.0 + p.x + p.z);

        var glowCol = vec3<f32>(0.0, 0.8, 1.0); // Cyan
        if (pattern > 0.0) {
            glowCol = vec3<f32>(1.0, 0.2, 0.8); // Magenta
        }

        // Apply glow to "crevices" or peaks of the pattern
        let patternFactor = smoothstep(0.4, 0.5, abs(pattern));

        surfCol += glowCol * patternFactor * glowIntensity * pulse;

        // Add rim lighting for "Cyber" look
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        surfCol += vec3<f32>(0.2, 0.4, 1.0) * fresnel * 2.0;

        color = surfCol * (diff * 0.8 + 0.2);

        // Fog
        let fogDist = length(p - ro);
        let fogAmount = 1.0 - exp(-fogDist * 0.08);
        let fogColor = vec3<f32>(0.01, 0.01, 0.02);
        color = mix(color, fogColor, fogAmount);
    } else {
        // Background
        color = vec3<f32>(0.01, 0.01, 0.02);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Depth write
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 50.0, 0.0, 0.0, 0.0));
}
