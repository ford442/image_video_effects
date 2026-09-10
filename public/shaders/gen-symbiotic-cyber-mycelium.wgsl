// ----------------------------------------------------------------
// Symbiotic Cyber-Mycelium
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Data Speed, .y = Network Density, .z = Growth Twist, .w = Infection Bloom
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

// Branchless cosine palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

// Cheap FBM noise for SDF perturbation
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                       dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                       dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                       dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                       dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
    return p - c * round(p / c);
}

fn map(p: vec3<f32>) -> vec2<f32> { // returns vec2(sdf, material_id)
    var pos = p;

    // Audio Reactivity (Density)
    let audioBass = extraBuffer[0];
    let densityMod = 1.0 + audioBass * 0.5;

    // Mouse Interaction: Infection Field
    // Map mouse UV (0..1) to scene coords (-1..1) roughly
    let mousePos = vec2<f32>((u.zoom_config.y * 2.0 - 1.0) * (u.config.z / u.config.w), -(u.zoom_config.z * 2.0 - 1.0));
    // Project mouse onto z-plane for 3D interaction (assume interaction occurs at z ~ 3.0)
    let infectionCenter = vec3<f32>(mousePos.x * 3.0, mousePos.y * 3.0, p.z);

    let distToMouse = length(p.xy - infectionCenter.xy);
    let infectionStr = u.zoom_params.w * max(0.0, 1.0 - distToMouse / 2.0); // u.zoom_params.w = Infection Bloom

    // Domain Twisting based on Z
    let twistFactor = u.zoom_params.z; // Growth Twist
    let twr = rot(pos.z * twistFactor * 0.1);
    let pxy = twr * pos.xy;
    pos = vec3<f32>(pxy.x, pxy.y, pos.z);

    // Infinite Domain Repetition
    let cellSpace = 4.0 / (u.zoom_params.y * densityMod); // u.zoom_params.y = Network Density
    let q = opRep(pos, vec3<f32>(cellSpace, cellSpace, cellSpace));

    // Fractal branching cylinders (Mycelial threads)
    let cylRadius = 0.05 + noise(pos * 5.0) * 0.02 + infectionStr * 0.05;

    let dCylX = length(q.yz) - cylRadius;
    let dCylY = length(q.xz) - cylRadius;
    let dCylZ = length(q.xy) - cylRadius;

    var dCyl = smin(dCylX, dCylY, 0.2);
    dCyl = smin(dCyl, dCylZ, 0.2);

    // Data Nodes (Spheres)
    let dSphere = length(q) - (0.15 + infectionStr * 0.1);

    // Combine
    let d = smin(dCyl, dSphere, 0.3);

    // Add some noise to final SDF for organic bumpiness
    let finalD = d + noise(pos * 2.0) * 0.05;

    // Material ID: 1.0 for threads, 2.0 for nodes
    let mat = select(1.0, 2.0, dSphere < dCyl + 0.1);

    return vec2<f32>(finalD, mat);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = vec2<i32>(textureDimensions(writeTexture));
    let coord = vec2<i32>(global_id.xy);

    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }

    let resolution = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;

    // Audio Reactivity (Speed)
    let audioTreble = extraBuffer[133]; // Smooth treble

    let time = u.config.x;
    let dataSpeed = u.zoom_params.x * (1.0 + audioTreble); // Data Speed

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, time * 2.0); // Move forward
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var res = vec2<f32>(-1.0, -1.0);
    var d = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        res = map(p);
        d = res.x;
        if (d < 0.001 || t > 20.0) { break; }
        t += d * 0.7; // slight under-relaxation for safety with twisted SDF
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Base shading
        let lig = normalize(vec3<f32>(0.5, 0.8, -0.2));
        let dif = clamp(dot(n, lig), 0.0, 1.0);
        let amb = 0.5 + 0.5 * dot(n, vec3<f32>(0.0, 1.0, 0.0));

        // SSS Hack (Subsurface Scattering)
        let sssDist = 0.1;
        let sssVal = map(p + n * sssDist).x;
        let sss = smoothstep(0.0, sssDist, sssVal);

        // Color mapping
        var baseCol = vec3<f32>(0.1, 0.1, 0.1);
        if (res.y == 1.0) { // Threads
            baseCol = vec3<f32>(0.05, 0.15, 0.2); // Dark blue/green
        } else { // Nodes
            baseCol = vec3<f32>(0.2, 0.1, 0.3); // Dark purple
        }

        col = baseCol * (dif * 0.5 + amb * 0.5) + vec3<f32>(0.0, 0.5, 0.2) * (1.0 - sss) * 2.0;

        // Data Pulses (Bloom)
        let distAlongFibers = length(p.xy);
        let pulsePhase = fract(distAlongFibers * 5.0 - time * dataSpeed);
        let pulseBloom = smoothstep(0.8, 1.0, pulsePhase) * smoothstep(1.0, 0.8, pulsePhase + 0.1);

        // Mouse infection strength at surface hit
        let mousePos = vec2<f32>((u.zoom_config.y * 2.0 - 1.0) * (u.config.z / u.config.w), -(u.zoom_config.z * 2.0 - 1.0));
        let infectionCenter = vec3<f32>(mousePos.x * 3.0, mousePos.y * 3.0, p.z);
        let distToMouseHit = length(p.xy - infectionCenter.xy);
        let hitInfectionStr = u.zoom_params.w * max(0.0, 1.0 - distToMouseHit / 2.0);

        let glowColor = palette(distAlongFibers * 0.1 - time * 0.1 + hitInfectionStr * 0.5);

        // Combine emission
        let emissionStr = (pulseBloom * 5.0 + hitInfectionStr * 3.0) * select(1.0, 2.0, res.y == 2.0); // Nodes pulse brighter
        col += glowColor * emissionStr;

        // Fog
        col = mix(col, vec3<f32>(0.0, 0.02, 0.05), 1.0 - exp(-0.05 * t));
    } else {
        col = vec3<f32>(0.0, 0.02, 0.05); // Background color
    }

    // Tonemapping and gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
