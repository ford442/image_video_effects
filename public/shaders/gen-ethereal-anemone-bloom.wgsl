// ----------------------------------------------------------------
// Ethereal Anemone Bloom
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// --- Helpers ---

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)),
                   hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)),
                   hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pos = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// --- SDF Primitives ---

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Capped Cone
fn sdCappedCone(p: vec3<f32>, h: f32, r1: f32, r2: f32) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(r2, h);
    let k2 = vec2<f32>(r2 - r1, 2.0 * h);
    let ca = vec2<f32>(q.x - min(q.x, select(r2, r1, q.y < 0.0)), abs(q.y) - h);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    let s = select(1.0, -1.0, cb.x < 0.0 && ca.y < 0.0);
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// --- Map Function ---

fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Seabed (Infinite Organic Topography)
    let groundBase = -4.0;
    let groundNoise = fbm(p.xz * 0.2) * 2.0;
    let groundHeight = groundBase + groundNoise;
    let d_floor = p.y - groundHeight;

    // 2. Anemones (Domain Repetition)
    let tentacle_density = u.zoom_params.y; // 0.1 to 1.0
    // As density increases, cell size decreases (more clustered)
    let cell_size = mix(8.0, 2.0, tentacle_density);

    let id = floor(p.xz / cell_size);
    let q_xz = (fract(p.xz / cell_size) - 0.5) * cell_size;
    let h = hash(id);

    // Anemone base height from FBM at cell center
    let cell_center = (id + 0.5) * cell_size;
    let local_ground = groundBase + fbm(cell_center * 0.2) * 2.0;

    // Local coordinates relative to anemone base
    var q = vec3<f32>(q_xz.x, p.y - local_ground, q_xz.y);

    // Mouse Interaction (Vortex/Eddy)
    // Map mouse (0 to 1) to world space bounds roughly matching view
    let mouseWorldX = (u.zoom_config.y - 0.5) * 30.0;
    let mouseWorldZ = (u.zoom_config.z - 0.5) * 30.0;
    let mouseWorld = vec3<f32>(mouseWorldX, 0.0, mouseWorldZ);

    let distToMouse = length(p - mouseWorld);
    let mouseForce = exp(-distToMouse * 0.15) * 5.0 * select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Swaying Logic
    let time = u.config.x;
    let current_speed = u.zoom_params.x;
    let sway_amt = (q.y * 0.2) * current_speed;
    var sway = vec3<f32>(
        sin(time * 1.5 + h * 6.28 + p.y * 0.1) * sway_amt,
        0.0,
        cos(time * 1.2 + h * 6.28 + p.y * 0.1) * sway_amt
    );

    // Add mouse force (push away from mouse center)
    if (distToMouse > 0.1) {
        let dirToMouse = normalize(p - mouseWorld);
        sway += dirToMouse * mouseForce * (q.y * 0.1);
    }

    q.x -= sway.x;
    q.z -= sway.z;

    // Build multiple tentacles using smin
    var d_tentacles = 1000.0;
    let num_tentacles = 4;
    for(var i = 0; i < num_tentacles; i++) {
        let th = hash(id + vec2<f32>(f32(i), 0.0));
        let height = 3.0 + th * 2.0;

        // Offset each tentacle
        let angle = th * 6.28 + f32(i) * 1.57;
        let radius = 0.5 + th * 0.5;
        let offset = vec3<f32>(cos(angle)*radius, 0.0, sin(angle)*radius);

        // Cone centered vertically
        let p_cone = q - offset - vec3<f32>(0.0, height * 0.5, 0.0);
        let base_r = 0.4 + th * 0.2;
        let top_r = 0.05;

        let d = sdCappedCone(p_cone, height * 0.5, base_r, top_r);
        d_tentacles = smin(d_tentacles, d, 0.6);
    }

    var d = d_floor;
    var mat = 1.0; // Floor

    if (d_tentacles < d) {
        d = d_tentacles;
        mat = 2.0; // Base tentacle
        // Check if we are near the top of the tentacles
        if (q.y > 2.0) {
            mat = 3.0; // Glowing tip
        }
    }

    // Blend floor and tentacles to make it organic
    d = smin(d_floor, d_tentacles, 1.0);

    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.005;
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
    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;
        if(d < 0.002 || t > 80.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

// --- Compute Entry Point ---

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x * 0.2;

    // 1. Ray setup and camera matrix
    let ro = vec3<f32>(time * 2.0, -1.0, time * 2.0); // Moving camera
    let target = ro + vec3<f32>(cos(time*0.5), -0.2, sin(time*0.5));

    let forward = normalize(target - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    let rd = normalize(forward + right * uv.x + up * uv.y);

    // 2. Raymarching loop
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    // 3. Shading and color accumulation
    var color = vec3<f32>(0.0);
    let fogColor = vec3<f32>(0.0, 0.05, 0.12); // Deep water murk
    let water_murkiness = u.zoom_params.w;

    if (t < 80.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.2));
        let diff = max(dot(n, lightDir), 0.0);
        let ambient = 0.1;

        var baseColor = vec3<f32>(0.05, 0.08, 0.1); // seabed

        if (mat == 2.0 || mat == 3.0) {
            baseColor = vec3<f32>(0.1, 0.3, 0.4); // Deep fleshy cyan

            // Subsurface Scattering Approximation
            // Sample SDF slightly deeper into surface
            let sss_d = map(p - n * 0.4).x;
            let sss = clamp(0.5 + sss_d * 2.0, 0.0, 1.0);
            let sss_color = vec3<f32>(0.0, 0.5, 0.8) * sss;

            baseColor += sss_color;
        }

        var emissive = vec3<f32>(0.0);
        if (mat == 3.0) {
            // Bioluminescent Audio-Pulse at tips
            let glow_intensity = u.zoom_params.z;
            let audio_pulse = u.config.y; // Audio accumulator proxy

            // Shift colors between deep cyan and electric magenta based on height and time
            let hue = fract(p.y * 0.1 - time * 2.0);
            let k = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
            let p_col = abs(fract(vec3<f32>(hue) + k) * 6.0 - 3.0);
            let shiftColor = clamp(p_col - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));

            // Intense neon light driven by audio amplitude
            let pulse_factor = 1.0 + sin(audio_pulse * 10.0) * 0.5;
            emissive = shiftColor * glow_intensity * 2.0 * pulse_factor;
        }

        color = baseColor * (diff + ambient) + emissive;

        // 4. Volumetric fog application
        // Distance-based volumetric fog for deep-ocean feel
        let fogAmount = 1.0 - exp(-t * 0.02 * water_murkiness);
        color = mix(color, fogColor, fogAmount);
    } else {
        color = fogColor;
    }

    // Gamma correction
    color = pow(color, vec3<f32>(0.4545));

    // 5. writeTexture update
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 80.0, 0.0, 0.0, 0.0));
}
