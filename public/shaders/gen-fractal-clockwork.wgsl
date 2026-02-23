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
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: array<vec4<f32>, 50>,
};

// Fractal Clockwork - Generative Shader

fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// SDF for a gear
// p: position relative to gear center (y is axis)
// teeth: number of teeth
// radius: main radius
// width: thickness
// toothDepth: depth of teeth
fn gearSDF(p: vec3<f32>, teeth: f32, radius: f32, width: f32, toothDepth: f32) -> f32 {
    // Basic cylinder
    let len = length(p.xz);
    let d_cyl = len - radius;

    // Teeth modulation
    // atan2 gives angle -PI to PI
    let angle = atan2(p.z, p.x);
    // Modulate radius with smooth teeth shape
    // using smoothstep for better shape than pure sin
    let sector = angle * teeth / 6.28318;
    let tooth = smoothstep(-0.2, 0.2, cos(angle * teeth)) * toothDepth;

    let d_gear = len - (radius + tooth);

    // Cap height (thickness)
    let d_cap = abs(p.y) - width;

    // Central hole
    let d_hole = 0.5 - len; // radius 0.5 hole

    // Combine: Intersection of cylinder+teeth and cap, minus hole
    let d_solid = max(d_gear, d_cap);
    return max(d_solid, d_hole);
}

// Scene Map function
fn map(p: vec3<f32>) -> vec2<f32> {
    // Param 1: Gear Density -> controls cell size
    // Default 1.0 -> cell_size 4.0
    // Range 0.5 to 2.0
    let density = u.zoom_params.x;
    let cell_size = 4.0 / density;

    // Domain repetition
    // Determine cell ID to alternate rotation
    let cell_id = floor(p.xz / cell_size);

    // Local coordinates within the cell
    // We want the gear centered in the cell
    let local_xz = (fract(p.xz / cell_size) - 0.5) * cell_size;
    var local_p = vec3<f32>(local_xz.x, p.y, local_xz.y);

    // Checkerboard parity
    // Check if sum of cell indices is even or odd
    let parity = (i32(cell_id.x) + i32(cell_id.y)) % 2;

    // Alternate rotation direction
    // If parity is 0, rotate one way, else the other
    let dir = select(1.0, -1.0, parity == 0);

    // Param 2: Rotation Speed
    let speed = u.zoom_params.y;
    let time = u.config.x * speed;

    // Apply rotation to the gear
    // We rotate the space in the opposite direction to rotate the object
    let rot_angle = time * dir;
    let rotated_xz = rotate2D(local_p.xz, rot_angle);
    local_p.x = rotated_xz.x;
    local_p.z = rotated_xz.y;

    // Gear parameters
    let teeth = 12.0;
    let radius = cell_size * 0.35; // Keep within cell
    let width = 0.2;
    let toothDepth = cell_size * 0.05;

    let d = gearSDF(local_p, teeth, radius, width, toothDepth);

    // Add a floor or ceiling? Maybe just infinite gears floating.
    // Let's add some vertical structure or just multiple layers.
    // For now, infinite field in XZ plane at y=0.

    // We can add a secondary layer of smaller gears offset vertically
    // to make it more 3D "clockwork"

    // Secondary layer
    let offset_y = 0.5;
    let cell_id2 = floor((p.xz + cell_size*0.5) / cell_size);
    let local_xz2 = (fract((p.xz + cell_size*0.5) / cell_size) - 0.5) * cell_size;
    var local_p2 = vec3<f32>(local_xz2.x, p.y - offset_y, local_xz2.y);

    let parity2 = (i32(cell_id2.x) + i32(cell_id2.y)) % 2;
    let dir2 = select(-1.0, 1.0, parity2 == 0); // Opposite logic to mesh?
    // Actually if we offset by half cell, we are in the "holes" of the first grid.

    let rot_angle2 = time * dir2 * 2.0; // Faster small gears
    let rotated_xz2 = rotate2D(local_p2.xz, rot_angle2);
    local_p2.x = rotated_xz2.x;
    local_p2.z = rotated_xz2.y;

    let d2 = gearSDF(local_p2, 8.0, radius * 0.6, width * 0.8, toothDepth);

    // Combine layers
    let final_d = min(d, d2);

    // Material ID: 1.0 = Metal
    return vec2<f32>(final_d, 1.0);
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
    var t = 0.0;
    for(var i=0; i<128; i++) {
        let p = ro + rd * t;
        let d = map(p).x;
        if(d < 0.001 || t > 100.0) { break; }
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
    // Mouse control
    let mouse = u.zoom_config.yz; // 0..1

    // Param 3: Metallic Shine (used in shading)
    // Param 4: Glow Intensity (used in shading)

    // Camera Position
    // We fly through the field or orbit?
    // "Camera flies through this dense, 3D mechanical world"
    // Let's move camera forward with time, and allow mouse to look around.

    let camSpeed = 1.0;
    let camPos = vec3<f32>(u.config.x * 0.5, 2.0 + sin(u.config.x * 0.2), u.config.x * 0.5);

    // Mouse look
    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = (mouse.y - 0.5) * 3.14;

    // Direction from mouse angles
    let cd = vec3<f32>(
        sin(yaw) * cos(pitch),
        sin(pitch),
        cos(yaw) * cos(pitch)
    );

    let ro = camPos;
    let forward = normalize(cd);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarch
    let t_res = raymarch(ro, rd);
    let t = t_res.x;

    var color = vec3<f32>(0.0);

    if (t < 100.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

        // Diffuse
        let diff = max(dot(n, lightDir), 0.0);

        // Specular (Metallic)
        let viewDir = normalize(ro - p);
        let reflectDir = reflect(-lightDir, n);
        let spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);

        // Environment reflection (fake)
        let ref = reflect(rd, n);
        let env = 0.5 + 0.5 * sin(ref.y * 10.0 + u.config.x); // Stripy reflection

        // Metallic parameter
        let metallic = u.zoom_params.z;

        // Base Color: Copper/Brass/Gold
        let copper = vec3<f32>(0.72, 0.45, 0.20);
        let gold = vec3<f32>(1.0, 0.84, 0.0);
        let steel = vec3<f32>(0.8, 0.8, 0.9);

        // Vary color based on position (e.g. y level or cell)
        let baseColor = mix(copper, steel, step(0.0, p.y));

        // Combine lighting
        // Metallic look: Diffuse contributes less, Specular and Reflection more
        let ambient = 0.1 * baseColor;
        let diffuseColor = baseColor * diff * (1.0 - metallic);
        let specularColor = vec3<f32>(1.0) * spec * metallic;
        let envColor = baseColor * env * metallic * 0.5;

        color = ambient + diffuseColor + specularColor + envColor;

        // Glow (Param 4)
        // Add glow near the gears or in the "energy" parts
        // Let's say the edges glow or there is a mist
        let glowIntensity = u.zoom_params.w;
        let glow = vec3<f32>(0.0, 0.5, 1.0) * glowIntensity * 0.1 / (t * 0.1);
        // Or better: based on iteration count or distance field trap?
        // Simple distance fog glow
        color += glow;

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.02);
        let fogColor = vec3<f32>(0.05, 0.02, 0.01); // Dark industrial fog
        color = mix(color, fogColor, fogAmount);

    } else {
        // Background
        color = vec3<f32>(0.05, 0.02, 0.01);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
