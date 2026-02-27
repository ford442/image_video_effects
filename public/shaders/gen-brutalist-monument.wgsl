// ═══════════════════════════════════════════════════════════════
//  Brutalist Monument - Generative Shader
//  Category: Generative
//  Description: Massive concrete architecture in an atmospheric void.
// ═══════════════════════════════════════════════════════════════

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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=SunAngle, y=FogDensity, z=ArtifactScale, w=Complexity
    ripples: array<vec4<f32>, 50>,
};

// --- SDF Primitives ---

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

// --- Transformations ---

fn rotateY(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

fn rotateX(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

// --- Noise & Random ---

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// --- Scene Map ---

fn map(p: vec3<f32>) -> vec2<f32> {
    // Parameters
    let complexity = u.zoom_params.w; // 0..1
    let artifactScale = u.zoom_params.z; // 0..1
    let time = u.config.x;

    // 1. Infinite Architecture (Pillars/Slabs)
    // Repetition
    let cellSize = 8.0;
    let cellId = floor((p.xz + cellSize * 0.5) / cellSize);

    // Domain repetition for pillars
    // We only repeat in XZ plane
    let q = p;
    var local_xz = (fract((p.xz + cellSize * 0.5) / cellSize) - 0.5) * cellSize;

    // Height variation based on noise
    let h_noise = noise(cellId * 0.1 + vec2<f32>(complexity * 5.0));
    let pillar_height = 2.0 + h_noise * 15.0 + complexity * 10.0;

    // Don't spawn pillar in the center (where the artifact is)
    // Let's clear a clearing of 3x3 cells
    let center_dist = length(cellId);
    var pillar_d = 1000.0;

    if (center_dist > 2.0) {
        let pillar_pos = vec3<f32>(local_xz.x, p.y - pillar_height * 0.5 + 5.0, local_xz.y); // Shift down so top is at varied heights
        // Make pillars blocky
        let width = 1.0 + noise(cellId * 0.5) * 2.0;
        pillar_d = sdBox(pillar_pos, vec3<f32>(width, pillar_height, width));
    }

    // Ground plane
    let ground_d = p.y + 5.0; // Floor at y = -5.0

    // Combine architecture
    var d_arch = min(pillar_d, ground_d);

    // 2. Floating Artifact
    let artifact_pos = vec3<f32>(0.0, 2.0 + sin(time * 0.5) * 1.0, 0.0);
    var p_art = p - artifact_pos;

    // Rotate artifact
    p_art = rotateY(p_art, time * 0.5);
    p_art = rotateX(p_art, time * 0.3);

    let scale = 1.0 + artifactScale * 2.0;
    // An octahedron or a box
    let d_artifact = sdOctahedron(p_art, scale);

    // Subtract a sphere from artifact for visual interest?
    // let d_sub = sdSphere(p_art, scale * 1.2);
    // d_artifact = max(d_artifact, -d_sub);

    // Combine scene
    // Material ID: 1.0 = Concrete, 2.0 = Artifact

    var d = d_arch;
    var mat = 1.0;

    if (d_artifact < d) {
        d = d_artifact;
        mat = 2.0;
    }

    return vec2<f32>(d, mat);
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
    for(var i=0; i<150; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;
        if(d < 0.002 || t > 150.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

fn softShadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32) -> f32 {
    var res = 1.0;
    var t = mint;
    for(var i=0; i<32; i++) {
        let h = map(ro + rd * t).x;
        if(h < 0.001) { return 0.0; }
        res = min(res, k * h / t);
        t += h;
        if(t > maxt) { break; }
    }
    return res;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Parameters
    let sunAngle = u.zoom_params.x * 3.14159; // 0 to PI
    let fogDensity = u.zoom_params.y; // 0..1
    let time = u.config.x;

    // Camera Control
    let mouse = u.zoom_config.yz; // 0..1

    // Orbit camera logic
    let radius = 20.0;
    let cam_h = 5.0 + mouse.y * 20.0;
    let cam_angle = mouse.x * 6.28 + time * 0.1;

    let ro = vec3<f32>(sin(cam_angle) * radius, cam_h, cos(cam_angle) * radius);
    let ta = vec3<f32>(0.0, 2.0, 0.0); // Look at artifact

    // Camera Basis
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    // Background / Fog Color
    let bg_color = vec3<f32>(0.05, 0.05, 0.06); // Dark Grey/Blue

    var color = bg_color;

    if (t < 150.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let sun_dir = normalize(vec3<f32>(sin(sunAngle), cos(sunAngle), 0.5));
        let diff = max(dot(n, sun_dir), 0.0);

        // Shadows
        var shadow = 1.0;
        // Cheap shadow check if needed, maybe skip for performance or use softShadow
        if (diff > 0.0) {
            shadow = softShadow(p + n * 0.01, sun_dir, 0.1, 20.0, 16.0);
        }

        // Ambient
        let ambient = vec3<f32>(0.02, 0.02, 0.03);

        // Material Coloring
        var albedo = vec3<f32>(0.2); // Concrete Grey
        var rough = 0.9;

        if (mat == 2.0) {
            // Artifact: Gold or Black Monolith?
            // Let's go Gold/Brass
            albedo = vec3<f32>(0.8, 0.6, 0.2);
            rough = 0.2;

            // Emission?
            // let emit = 0.2;
            // albedo += emit;
        } else {
             // Concrete Texture (Simulated by noise in map? or just here)
             let n_tex = noise(p.xz * 0.5);
             albedo = vec3<f32>(0.2 + n_tex * 0.1);
        }

        // Specular
        let view_dir = normalize(ro - p);
        let half_vec = normalize(sun_dir + view_dir);
        let spec = pow(max(dot(n, half_vec), 0.0), 32.0 * (1.0 - rough));

        // Combine Light
        let light_color = vec3<f32>(1.0, 0.95, 0.9); // Warm Sun

        let diffuse_light = albedo * diff * light_color * shadow;
        let specular_light = vec3<f32>(1.0) * spec * shadow * (1.0 - rough); // More spec for smooth

        color = ambient + diffuse_light + specular_light;

        // Fog
        // Exponential fog
        let fog_amount = 1.0 - exp(-t * (0.02 + fogDensity * 0.05));
        // Height fog?
        // let height_fog = exp(-p.y * 0.1);

        color = mix(color, bg_color, fog_amount);

    }

    // Vignette
    let vign = 1.0 - length(uv) * 0.3;
    color = color * vign;

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 150.0, 0.0, 0.0, 0.0));
}
