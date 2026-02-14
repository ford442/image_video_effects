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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: array<vec4<f32>, 50>,
};

// Hyper Labyrinth - Generative Shader
// 3D slice of a 4D maze structure with neon aesthetics.

// 4D Rotation
fn rotate4D(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    // Rotate in XW plane
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
    // We use a small w component to give it "thickness" in 4D space
    var p4 = vec4<f32>(pos3, 1.0);

    // 2. Apply 4D rotation driven by time/params
    // u.zoom_params.y controls morph speed (time multiplier)
    let speed = mix(0.1, 2.0, u.zoom_params.y);
    let time = u.config.x * speed;

    // Rotate in XW and maybe YW or ZW for more complexity
    p4 = rotate4D(p4, time);

    // Also rotate in YZ plane for standard 3D rotation feel
    let rotYZ = u.config.x * 0.1;
    let cy = cos(rotYZ);
    let sy = sin(rotYZ);
    let tempY = p4.y * cy - p4.z * sy;
    let tempZ = p4.y * sy + p4.z * cy;
    p4.y = tempY;
    p4.z = tempZ;

    // 3. Maze generation logic (Gyroid / Trigonometric)
    // Formula: sin(x)cos(y) + sin(y)cos(z) + sin(z)cos(w) + sin(w)cos(x) = 0

    // Scale controls the density of the maze
    let scale = mix(1.0, 5.0, u.zoom_params.x);
    let q = p4 * scale;

    let val = sin(q.x)*cos(q.y) + sin(q.y)*cos(q.z) + sin(q.z)*cos(q.w) + sin(q.w)*cos(q.x);

    // Thickness threshold
    let thickness = mix(0.1, 1.2, u.zoom_params.w); // Wall thickness
    // Distance estimation for gyroid is roughly |val| / gradient_magnitude.
    // Approximating gradient magnitude as 1.5 or scale-dependent.
    // For visual purposes, abs(val) - thickness works well.

    let d = (abs(val) - thickness * 0.5) / scale; // Divide by scale to correct distance

    // Material ID: 1.0 for walls
    return vec2<f32>(d * 0.5, 1.0);
}

// Calculate normal for shading
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
    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let d = map(p).x;
        if(d < 0.001 || t > 50.0) { break; }
        t += d;
    }
    return vec2<f32>(t, 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera Setup
    // Mouse controls orbit angles
    let mouse = u.zoom_config.yz; // 0..1
    let angleX = (mouse.x - 0.5) * 6.28; // Full rotation
    let angleY = (mouse.y - 0.5) * 3.14; // Elevation

    let camDist = 8.0;

    // Spherical to Cartesian for camera position
    let cx = camDist * cos(angleY) * sin(angleX);
    let cy = camDist * sin(angleY);
    let cz = camDist * cos(angleY) * cos(angleX);

    let ro = vec3<f32>(cx, cy, cz);
    let target = vec3<f32>(0.0, 0.0, 0.0);

    let fwd = normalize(target - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);

    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch
    let t_res = raymarch(ro, rd);
    let t = t_res.x;

    var color = vec3<f32>(0.0);

    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Basic lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let amb = 0.1;

        // Base color - Dark metallic
        let baseColor = vec3<f32>(0.1, 0.1, 0.15);

        // Glow calculation
        // We can re-evaluate the map function without thickness threshold to get "center" distance
        // Or assume surface is at threshold.
        // Let's use position to drive color pattern.

        // Neon Glow logic
        // Use proximity to integer coordinates or 4D value for coloring

        // Re-calculate raw 4D value for coloring
        let speed = mix(0.1, 2.0, u.zoom_params.y);
        let time = u.config.x * speed;
        var p4 = vec4<f32>(p, 1.0);
        p4 = rotate4D(p4, time);
        // ... apply rotations used in map ...
        let rotYZ = u.config.x * 0.1;
        let cy_rot = cos(rotYZ);
        let sy_rot = sin(rotYZ);
        let tempY = p4.y * cy_rot - p4.z * sy_rot;
        let tempZ = p4.y * sy_rot + p4.z * cy_rot;
        p4.y = tempY;
        p4.z = tempZ;

        let scale = mix(1.0, 5.0, u.zoom_params.x);
        let q = p4 * scale;
        let val = sin(q.x)*cos(q.y) + sin(q.y)*cos(q.z) + sin(q.z)*cos(q.w) + sin(q.w)*cos(q.x);

        // Glow intensity based on how close 'val' is to 0 (center of wall) vs surface?
        // Actually, surface is where |val| - thickness/2 = 0.
        // So |val| is constant on surface.
        // Let's use the gradient or normal to drive color.

        // Palette based on normal
        let palette = vec3<f32>(0.5) + 0.5 * cos(vec3<f32>(0.0, 2.0, 4.0) + p.y * 2.0 + time);

        // Param 3: Glow Intensity
        let glowParam = u.zoom_params.z;
        let glowColor = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(p.z * 0.5 + time) * 0.5 + 0.5);

        // Rim lighting for neon edge effect
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        color = baseColor * (diff + amb) + glowColor * fresnel * (1.0 + glowParam * 5.0);

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.05);
        color = mix(color, vec3<f32>(0.0, 0.0, 0.05), fogAmount);
    } else {
        // Background
        color = vec3<f32>(0.0, 0.0, 0.05);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Write depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 50.0, 0.0, 0.0, 0.0));
}
