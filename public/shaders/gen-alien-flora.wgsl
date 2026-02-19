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
    zoom_params: vec4<f32>,  // x=Density, y=SwaySpeed, z=GlowIntensity, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// Alien Flora - Generative Shader

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
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
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Scene Map function
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Terrain
    // Simple rolling hills using sine waves
    // Modulate frequency slightly
    let terrainHeight = sin(p.x * 0.2) * sin(p.z * 0.2) * 2.0 + sin(p.x * 0.5 + p.z * 0.3) * 0.5;
    let d_terrain = p.y - terrainHeight;

    // 2. Vegetation (Domain Repetition)
    // Density parameter controls cell size. Default 1.0 -> cell_size 8.0
    // Range 0.0 to 1.0. Let's map it to cell size.
    // Higher density = smaller cell size.
    // density 0.0 -> cell size 16.0
    // density 1.0 -> cell size 4.0
    let density = mix(16.0, 4.0, u.zoom_params.x);
    let cell_size = density;

    let id = floor(p.xz / cell_size);
    let q_xz = (fract(p.xz / cell_size) - 0.5) * cell_size;

    // Get random value for this cell
    let rand = hash(id);

    // Local coordinates for the plant
    // Plant grows from the ground (terrainHeight at the center of the cell)
    // We need to sample terrain height at the center of the cell to place the plant correctly
    let cell_center = (id + 0.5) * cell_size;
    let ground_y = sin(cell_center.x * 0.2) * sin(cell_center.y * 0.2) * 2.0 + sin(cell_center.x * 0.5 + cell_center.y * 0.3) * 0.5;

    // Plant base position relative to current point p
    // q.y is relative to the ground at the cell center
    var q = vec3<f32>(q_xz.x, p.y - ground_y, q_xz.y);

    // Only render plants if rand is above threshold (to vary density)
    // But since we use density to control cell size, we can just render every cell
    // Maybe vary size based on rand.

    // Swaying Motion
    // Wind direction and strength
    let time = u.config.x;
    let swaySpeed = u.zoom_params.y;

    // Sway based on height (q.y) and random phase
    let swayAmount = 0.5 * (q.y * 0.1) * (q.y * 0.1); // Sway more at top
    let sway = vec3<f32>(
        sin(time * swaySpeed + id.x) * swayAmount,
        0.0,
        cos(time * swaySpeed * 0.8 + id.y) * swayAmount
    );

    // Deform domain for swaying
    // Simple shear
    q.x -= sway.x;
    q.z -= sway.z;

    // Mushroom/Plant SDF
    // Stem
    let stemHeight = 2.0 + rand * 3.0; // Random height 2.0 to 5.0
    let stemRadius = 0.2 + rand * 0.1;
    // Offset y so base is at 0
    let p_stem = q - vec3<f32>(0.0, stemHeight * 0.5, 0.0);
    let stem = sdCappedCylinder(p_stem, stemHeight * 0.5, stemRadius);

    // Cap
    let capRadius = 1.0 + rand * 1.5;
    let capHeight = 0.5 + rand * 0.5;
    // Cap sits on top of stem
    let p_cap = q - vec3<f32>(0.0, stemHeight, 0.0);
    // Deform cap to look like mushroom
    // Ellipsoid-ish
    let d_cap_sphere = length(p_cap * vec3<f32>(1.0, 2.0, 1.0)) - capRadius;
    // Cut bottom of sphere
    let d_cap_cut = max(d_cap_sphere, -p_cap.y); // Hemisphere
    let cap = d_cap_cut;

    // Blend stem and cap
    let d_plant = smin(stem, cap, 0.3);

    // Combine terrain and plant
    // d_terrain is plane deformation.
    // We need to match material ID.
    // Let's say 1.0 is terrain, 2.0 is plant (bioluminescent)

    var d = d_terrain;
    var mat = 1.0;

    if (d_plant < d) {
        d = d_plant;
        mat = 2.0; // Glowing material
    }

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
    var t = 0.1; // Start a bit away to avoid self-intersection artifacts near 0
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

    // Camera Setup
    // Mouse control: X for rotation (yaw), Y for pitch/height
    let mouse = u.zoom_config.yz; // 0..1

    // Camera Orbit
    let time = u.config.x * 0.1;
    let yaw = (mouse.x - 0.5) * 10.0 + time;
    let pitch = (mouse.y - 0.5) * 2.0 + 0.5; // Pitch range
    let dist = 10.0;

    // Target position (look at)
    let target = vec3<f32>(0.0, 2.0, time * 10.0); // Move forward slowly

    // Camera position relative to target
    // We want to move continuously forward
    let ro = vec3<f32>(
        target.x + sin(yaw) * dist,
        target.y + pitch * 5.0 + 2.0, // Height based on mouse Y
        target.z + cos(yaw) * dist
    );

    let forward = normalize(target - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    var color = vec3<f32>(0.0);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1); // Dark blueish fog

    if (t < 100.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let diff = max(dot(n, lightDir), 0.0);

        // Color Palette
        var baseColor = vec3<f32>(0.1, 0.3, 0.1); // Dark green terrain

        if (mat == 2.0) { // Plant
            // Bioluminescent colors
            // Vary color based on position/ID
            // Use zoom_params.w for Color Shift
            let shift = u.zoom_params.w;
            let hue = fract(p.x * 0.1 + p.z * 0.1 + shift);

            // Simple hue to rgb
            let k = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
            let p_col = abs(fract(vec3<f32>(hue) + k) * 6.0 - 3.0);
            let hueColor = clamp(p_col - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));

            baseColor = mix(vec3<f32>(0.2, 0.8, 0.9), hueColor, 0.5); // Cyan base mix

            // Glow intensity
            let glow = u.zoom_params.z;
            baseColor = baseColor * glow; // Emissive
        }

        // Shading
        let ambient = vec3<f32>(0.05, 0.1, 0.1);
        color = baseColor * (diff * 0.5 + 0.5); // Half-Lambertish

        // Rim light for atmosphere
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        color += vec3<f32>(0.5, 0.8, 1.0) * rim * 0.5;

        // Distance Fog
        let fogAmount = 1.0 - exp(-t * 0.05);
        color = mix(color, fogColor, fogAmount);

        // Add "volumetric" glow around plants (fake)
        // If material is plant, it glows.
        // We can add glow based on distance to plant in raymarch loop but that's expensive.
        // Here we just use the surface color.

    } else {
        // Sky / Background
        color = fogColor;
        // Simple starfield or gradient?
        color = mix(fogColor, vec3<f32>(0.0, 0.0, 0.05), rd.y * 0.5 + 0.5);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
