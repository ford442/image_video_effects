// ═══════════════════════════════════════════════════════════════════
//  Vitreous Quantum-Lotus Singularity
//  Category: generative
//  Tags: ["organic", "quantum", "cosmic", "fractal", "flower", "refraction", "audio-reactive"]
// ═══════════════════════════════════════════════════════════════════

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
  resolution: vec2<f32>,
  time: f32,
  frame: u32,
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  view_matrix: mat4x4<f32>,
  proj_matrix: mat4x4<f32>,
  camera_pos: vec3<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// Rotation matrix 2D
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Polynomial smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Fractal noise / volumetric dust
fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    return fract(dot(q, vec3<f32>(137.5, 311.7, 193.3)));
}

// Distance map
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Spacetime distortion & mouse interaction
    let mouse = u.zoom_config.yz;
    p -= vec3<f32>(mouse.x * 3.0, mouse.y * 3.0, 0.0);

    let time = u.time;
    p.xy = rot(time * 0.1) * p.xy;
    p.yz = rot(time * 0.05) * p.yz;

    let petalComplexity = mix(1.0, 10.0, u.zoom_params.x);
    let singularityMass = mix(0.1, 5.0, u.zoom_params.y);

    // Gravitational singularity warping
    let l = length(p);
    let strength = singularityMass;
    if (l > 0.0) {
        let warp = 1.0 + (strength / (l * l + 0.1));
        // Soft warp applied conditionally to avoid exploding space
        p = p * mix(1.0, warp, 0.2);
    }

    // Central Singularity Sphere
    let singularity = length(p) - (singularityMass * 0.5);

    // Polar folding for lotus petals
    var a = atan2(p.y, p.x);
    let r = length(p.xy);

    // Number of petals
    let petals = petalComplexity * 2.0;
    a = (a * petals / (PI * 2.0)) % 1.0;
    if (a < 0.0) { a += 1.0; } // positive modulo
    a = a * PI * 2.0 / petals;

    // Convert back to cartesian
    var folded = vec3<f32>(cos(a)*r, sin(a)*r, p.z);

    // Petal shaping using smooth-min iterated folds
    var d = 100.0;
    let iterations = i32(petalComplexity);

    var scale = 1.0;
    var fp = folded;
    for (var i = 0; i < iterations; i++) {
        fp.x = abs(fp.x) - 0.5 * scale;
        fp.y = fp.y - 0.2 * scale;
        fp.xy = rot(0.2) * fp.xy;

        // Single petal SDF
        let hw = 0.2 * scale;
        let hl = 0.8 * scale;
        let ht = 0.05 * scale;
        let px = clamp(fp.x, -hw, hw);
        let py = clamp(fp.y, -hl, hl);
        let pz = clamp(fp.z, -ht, ht);

        let box = length(fp - vec3<f32>(px, py, pz)) - 0.01;

        d = smin(d, box, 0.2 * scale);
        scale *= 0.8;
    }

    // Combine singularity and petals
    return smin(d, singularity, 0.5);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<i32>(u.resolution);
    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = (vec2<f32>(coords) - u.resolution * 0.5) / u.resolution.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    let mouse = u.zoom_config.yz;
    ro.x += (mouse.x - 0.5) * 2.0;
    ro.y += (mouse.y - 0.5) * 2.0;

    // Raymarching
    var dO = 0.0;
    var dS: f32;
    var p: vec3<f32>;
    var steps = 0;
    for(var i=0; i<MAX_STEPS; i++) {
        p = ro + rd * dO;
        dS = map(p);
        dO += dS;
        if(dO > MAX_DIST || abs(dS) < SURF_DIST) {
            steps = i;
            break;
        }
    }

    // Shading
    var col = vec3<f32>(0.0);

    // Parameters
    let audioReactiveLuminescence = plasmaBuffer[0].x * mix(0.0, 3.0, u.zoom_params.w);
    let refractionIndex = mix(1.0, 2.5, u.zoom_params.z);

    if (dO < MAX_DIST) {
        let n = calcNormal(p);

        // Chromatic Refraction / Dispersion setup
        let refDirR = refract(rd, n, 1.0 / refractionIndex);
        let refDirG = refract(rd, n, 1.0 / (refractionIndex * 1.02));
        let refDirB = refract(rd, n, 1.0 / (refractionIndex * 1.04));

        // Fake environment / transmission color
        let envR = dot(refDirR, vec3<f32>(0.0, 1.0, 0.0)) * 0.5 + 0.5;
        let envG = dot(refDirG, vec3<f32>(1.0, 0.5, 0.0)) * 0.5 + 0.5;
        let envB = dot(refDirB, vec3<f32>(0.0, 0.5, 1.0)) * 0.5 + 0.5;

        var baseColor = vec3<f32>(envR, envG, envB) * 0.5;

        // Specular
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let viewDir = normalize(ro - p);
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), 32.0);
        baseColor += vec3<f32>(spec) * 0.8;

        // Audio reactive veins/pulses
        let r_polar = length(p.xy);
        let pulse = sin(r_polar * 10.0 - u.time * 5.0) * 0.5 + 0.5;
        let glowCol = mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(1.0, 0.8, 0.0), pulse);

        baseColor += glowCol * audioReactiveLuminescence * pow(pulse, 4.0);

        col = baseColor;
    }

    // Quantum Dust / Volumetric glow
    let dustIntensity = 0.1;
    var dustCol = vec3<f32>(0.0);
    for(var i=1; i<20; i++) {
        let tp = ro + rd * (f32(i) * MAX_DIST / 20.0);
        let dens = hash31(tp + u.time*0.1);
        if (dens > 0.95) {
            dustCol += vec3<f32>(0.2, 0.5, 1.0) * (dens - 0.95) * 20.0 * audioReactiveLuminescence;
        }
    }

    col += dustCol * dustIntensity;

    // Fog
    col = mix(col, vec3<f32>(0.01, 0.01, 0.03), 1.0 - exp(-0.02 * dO));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
