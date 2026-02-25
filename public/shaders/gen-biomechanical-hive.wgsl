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
    zoom_params: vec4<f32>,  // x=Density, y=PulseSpeed, z=Biomass, w=HueShift
    ripples: array<vec4<f32>, 50>,
};

// Biomechanical Hive - Generative Shader

// Helper Functions
fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn hash(p: vec3<f32>) -> f32 {
    let p3 = fract(p * 0.1031);
    let d = dot(p3, vec3<f32>(p3.y + 19.19, p3.z + 19.19, p3.x + 19.19));
    return fract((p3.x + p3.y) * p3.z + d); // Fixed hash function logic
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        val += amp * noise(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return val;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735027);
    let p_abs = abs(p);
    var p_mod = p_abs;
    p_mod.x -= 2.0 * min(dot(k.xy, p_mod.xy), 0.0) * k.x;
    p_mod.y -= 2.0 * min(dot(k.xy, p_mod.xy), 0.0) * k.y;
    // Wait, the standard swizzle logic is trickier in WGSL without full swizzle support on assignment
    // Re-implementing carefully

    // Correct logic for p.xy -= ...
    let dot_k_p = dot(k.xy, p_abs.xy);
    let offset = 2.0 * min(dot_k_p, 0.0);
    var p_xy = p_abs.xy - vec2<f32>(offset * k.x, offset * k.y);

    let d = vec2<f32>(
       length(p_xy - vec2<f32>(clamp(p_xy.x, -k.z*h.x, k.z*h.x), h.x)) * sign(p_xy.y - h.x),
       p_abs.z - h.y
    );
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Scene Map
fn map(p: vec3<f32>) -> vec2<f32> {
    // Parameters
    let density = mix(4.0, 10.0, u.zoom_params.x); // Zoom/Scale
    let pulseSpeed = u.zoom_params.y;
    let biomass = u.zoom_params.z;

    // Domain Repetition
    // We want infinite repetition.
    // Let's just do a simple modulo for now, maybe with some offset
    let cell_size = 12.0 / density; // Base size
    let q = p;

    // Hexagonal offset logic for Z rows?
    // Let's just use a rectangular grid of hex prisms that touch
    // Hex width is sqrt(3) * radius
    // Hex height is 2 * radius
    // We want them packed.
    // Let's just use standard mod for simplicity and rely on smin to blend

    let spacing = vec3<f32>(cell_size * 2.0, cell_size * 2.0, cell_size * 4.0);
    let id = floor((p + spacing * 0.5) / spacing);
    let local_p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;

    // Rotate local_p based on ID to create variation?
    // local_p.xy = rotate2D(local_p.xy, id.z * 1.0);

    // 1. Base Geometry: Hex Prism
    // Orient along Z
    let hex_h = vec2<f32>(cell_size * 0.8, cell_size * 1.8);
    // Rotate 90 deg around X to make it a tunnel?
    // No, let's keep it as pillars for now, or rotate p

    // Let's make it a tunnel structure: infinite in Z, tiled in XY
    // But we are inside?
    // If we are inside, we need negative SDF or just walls.

    // Let's invert the logic: We have a block of space, and we subtract hex prisms to make tunnels?
    // Or we place hex prisms and we travel between them?
    // The prompt says "structure composed of hexagonal cells". "Claustrophobic".
    // "Walls are ribbed... centers glow".

    // Let's model a single cell interior.
    // Modulo position to be inside a cell.
    // To make it infinite, we just repeat the cell.

    let hex_tunnel_p = vec3<f32>(local_p.x, local_p.y, p.z); // Infinite Z for the prism
    // But we want cells, not infinite tubes? "Hexagonal cells".
    // So repeated in Z too.

    // Create hollow cells by inverting the SDF
    // Inside the hex prism, sdHexPrism is negative. We want positive distance (empty space) inside.
    // So d = -sdHexPrism.
    // The "walls" are where sdHexPrism is positive (outside the prism).
    // We make the prism slightly smaller than the grid cell to leave thick walls.

    let d_hex = sdHexPrism(local_p, hex_h * 0.9);
    let d_base = -d_hex; // Inverted: Positive inside, Negative in walls

    // 2. Pipes/Ribs
    // Rings around the hex prism
    let rib_freq = 10.0;
    let rib_amp = 0.05;
    let ribs = sin(local_p.z * rib_freq) * rib_amp;

    // 3. Organic Displacement
    let time = u.config.x * pulseSpeed;
    let pulse = sin(time * 2.0) * 0.5 + 0.5; // 0..1
    let noise_val = fbm(p * 2.0 + vec3<f32>(0.0, 0.0, time * 0.2));
    let displacement = noise_val * biomass * 0.5;

    // Breathing effect
    let breathing = sin(time + p.z) * 0.05;

    // Combine
    let d_organic = d_base + ribs + displacement + breathing;

    // 4. Smooth Blend with some inner structure?
    // Let's add a "core" sphere in the middle of the hex
    let d_core = length(local_p) - cell_size * 0.3;

    // Connect core to walls with "tendrils"
    // Tendrils are just noise?

    // Final blending
    let d = smin(d_organic, d_core, 0.3);

    // Material
    // If close to core, mat = 2.0 (Glow)
    // Else mat = 1.0 (Biomechanical Wall)
    var mat = 1.0;

    // Fix material logic: d_organic is the field we are marching.
    // d_core is the sphere SDF (positive outside, negative inside).
    // We want the core to be an object inside the hollow cell.
    // So the core is SOLID (d < 0 inside? No, standard object is d > 0 outside).
    // Wait, we inverted the world!
    // Wall: d_base < 0. Empty space: d_base > 0.
    // We raymarch in empty space (d > 0).
    // If we hit a wall, d -> 0.
    // Now we want a glowing core in the center.
    // A sphere object in the center.
    // Standard sphere: d_sphere = length(p) - r.
    // Outside sphere: d > 0. Inside sphere: d < 0.
    // So the sphere is a "solid" object in our empty space.
    // So we just take min(d_organic, d_sphere).
    // d_organic defines the room walls. d_sphere defines the central ball.
    // Both are positive in the empty air between them.

    let d_sphere_core = length(local_p) - cell_size * 0.2;

    // Combine walls and core
    // d_organic is distance to walls (inverted).
    // d_sphere_core is distance to sphere.
    // We want the union of walls and sphere as obstacles.
    // Union of obstacles = min(d_walls, d_sphere).

    let d_final = min(d_organic, d_sphere_core);

    if (d_sphere_core < d_organic) {
         mat = 2.0;
    }

    return vec2<f32>(d_final, mat);
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
    var mat = 0.0;
    for(var i=0; i<128; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
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

    // Camera
    let mouse = u.zoom_config.yz; // 0..1
    let time = u.config.x;

    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = (mouse.y - 0.5) * 3.14;

    // Move camera through the hive
    let cam_pos = vec3<f32>(0.0, 0.0, time * 2.0);
    // Add some mouse offset to look around but stay near center
    // The cell center is at (0,0) in local coords.

    let ro = cam_pos;

    // Look direction
    let forward = normalize(vec3<f32>(sin(yaw), sin(pitch), cos(yaw)));
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    var color = vec3<f32>(0.0);
    let fogColor = vec3<f32>(0.01, 0.01, 0.02); // Very dark

    if (t < 100.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

        // Pulsating light from the core
        let pulse = sin(u.config.x * u.zoom_params.y * 5.0) * 0.5 + 0.5;

        // Base Material Color
        // Metallic/Organic Dark
        var baseColor = vec3<f32>(0.1, 0.1, 0.15);
        if (mat == 2.0) {
            // Core Glow
            let hueShift = u.zoom_params.w;
            let hue = 0.1 + hueShift; // Amber default
            // HSV to RGB roughly
            // Amber: 0.1 -> Yellow/Orange
            // Green: 0.3
            // Red: 0.0
            // Let's just mix colors
            let coreColor1 = vec3<f32>(1.0, 0.6, 0.1); // Amber
            let coreColor2 = vec3<f32>(0.1, 1.0, 0.2); // Green
            let coreColor3 = vec3<f32>(1.0, 0.1, 0.2); // Red

            var mixColor = coreColor1;
            if (hueShift > 0.3) { mixColor = mix(coreColor1, coreColor2, (hueShift - 0.3) * 3.0); }
            if (hueShift > 0.6) { mixColor = mix(coreColor2, coreColor3, (hueShift - 0.6) * 3.0); }

            baseColor = mixColor * (1.0 + pulse);

            // Add noise texture to core
            baseColor += fbm(p * 5.0) * 0.2;
        } else {
            // Wall
            // Shiny, slimy
            // Specular
            let ref = reflect(rd, n);
            let spec = pow(max(dot(ref, lightDir), 0.0), 16.0);
            baseColor += vec3<f32>(1.0) * spec * 0.5;

            // Rim
            let rim = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
            baseColor += vec3<f32>(0.2, 0.3, 0.4) * rim;
        }

        // Diffuse
        let diff = max(dot(n, lightDir), 0.0);
        color = baseColor * (diff * 0.8 + 0.2);

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.05);
        color = mix(color, fogColor, fogAmount);

    } else {
        color = fogColor;
    }

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
