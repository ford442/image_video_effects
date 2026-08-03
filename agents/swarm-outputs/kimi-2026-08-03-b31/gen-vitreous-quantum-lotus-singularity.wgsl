// ═══════════════════════════════════════════════════════════════════
//  Vitreous Quantum-Lotus Singularity  (visualist upgrade b31)
//  Category: generative
//  Tags: ["organic", "quantum", "cosmic", "fractal", "flower", "refraction", "audio-reactive", "sdf", "thin-film"]
//  Upgrade: canonical uniforms fix, slider mapping fix, thin-film
//           iridescent glass petals, per-petal cell variation, radial
//           vein inlay, 3-point lighting + Fresnel, ACES, real depth.
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1, y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // x=Petal Complexity, y=Singularity Mass, z=Refraction Index, w=Audio Pulse Glow
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Fractal noise / volumetric dust
fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    return fract(dot(q, vec3<f32>(137.5, 311.7, 193.3)));
}

// Thin-film interference for the vitreous petal shell
fn thinFilm(dot_nv: f32, film: f32, time: f32) -> vec3<f32> {
    let optical = (1.0 - dot_nv) * 4.0 + film * 3.0 + time * 0.15;
    let r = 0.5 + 0.5 * cos(optical * 1.8 + 0.0);
    let g = 0.5 + 0.5 * cos(optical * 2.1 + 2.094);
    let b = 0.5 + 0.5 * cos(optical * 2.4 + 4.188);
    // Bias toward cool vitreous hues (cyan/violet/rose)
    return mix(vec3<f32>(r, g, b), vec3<f32>(0.6, 0.3, 1.0), 0.25) * vec3<f32>(0.8, 1.05, 1.2);
}

// Distance map: returns vec2(distance, materialId) — 1=petals, 2=singularity
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Spacetime distortion & mouse interaction
    let mouse = u.zoom_config.yz;
    p -= vec3<f32>(mouse.x * 3.0, mouse.y * 3.0, 0.0);

    let time = u.config.x;
    p = vec3<f32>(rot(time * 0.1) * p.xy, p.z);
    p = vec3<f32>(p.x, rot(time * 0.05) * p.yz);

    // Sliders are RAW values (see JSON defaults)
    let petalComplexity = clamp(u.zoom_params.x, 1.0, 10.0);
    let singularityMass = clamp(u.zoom_params.y, 0.1, 5.0);

    // Gravitational singularity warping
    let l = length(p);
    if (l > 0.0) {
        let warp = 1.0 + (singularityMass / (l * l + 0.1));
        p = p * mix(1.0, warp, 0.2);
    }

    // Central Singularity Sphere
    let singularity = length(p) - (singularityMass * 0.5);

    // Polar folding for lotus petals
    var a = atan2(p.y, p.x);
    let r = length(p.xy);

    let petals = petalComplexity * 2.0;
    a = (a * petals / (PI * 2.0)) % 1.0;
    if (a < 0.0) { a += 1.0; }
    a = a * PI * 2.0 / petals;

    var folded = vec3<f32>(cos(a) * r, sin(a) * r, p.z);

    // Petal shaping using smooth-min iterated folds
    var d = 100.0;
    let iterations = i32(petalComplexity);

    var scale = 1.0;
    var fp = folded;
    for (var i = 0; i < iterations; i++) {
        fp.x = abs(fp.x) - 0.5 * scale;
        fp.y = fp.y - 0.2 * scale;
        fp = vec3<f32>(rot(0.2) * fp.xy, fp.z);

        let hw = 0.2 * scale;
        let hl = 0.8 * scale;
        let ht = 0.05 * scale;
        let px = clamp(fp.x, -hw, hw);
        let py = clamp(fp.y, -hl, hl);
        let pz = clamp(fp.z, -ht, ht);

        let petalBox = length(fp - vec3<f32>(px, py, pz)) - 0.01;

        d = smin(d, petalBox, 0.2 * scale);
        scale *= 0.8;
    }

    let combined = smin(d, singularity, 0.5);
    let matId = select(1.0, 2.0, singularity < d);
    return vec2<f32>(combined, matId);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Radial vein inlay: symmetry-folded spokes + concentric arcs that trace
// the lotus vasculature across the glass petals (2D polar ornament).
fn veinInlay(p: vec3<f32>, petals: f32, time: f32) -> f32 {
    let r = length(p.xy);
    let ang = atan2(p.y, p.x);
    // Fold angle into the petal symmetry; veins sit on the fold boundaries
    let spokes = abs(sin(ang * petals)) * r;
    let arcs = abs(fract(r * 2.5 - time * 0.3) - 0.5) * 0.4;
    let vein = min(spokes * 0.6, arcs);
    let fade = 1.0 - smoothstep(0.5, 3.5, r); // veins live on the bloom, not the void
    return (1.0 - smoothstep(0.0, 0.05, vein)) * fade;
}

// Cheap 3-tap ambient occlusion along the normal (petal crevice shading)
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sc = 1.0;
    for (var i = 1; i < 4; i++) {
        let h = 0.1 * f32(i);
        occ += (h - map(p + n * h).x) * sc;
        sc *= 0.7;
    }
    return clamp(1.0 - 1.5 * occ, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let uv = (vec2<f32>(id.xy) - res * 0.5) / res.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let mouse = u.zoom_config.yz;
    ro.x += (mouse.x - 0.5) * 2.0;
    ro.y += (mouse.y - 0.5) * 2.0;

    // Raymarching
    var dO = 0.0;
    var dS = 0.0;
    var matId = 0.0;
    var p = ro;
    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dm = map(p);
        dS = dm.x;
        matId = dm.y;
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }

    var col = vec3<f32>(0.0);
    var depth = 0.0;
    var nrm = vec3<f32>(0.0);
    var matTag = 0.0;

    // Parameters (raw slider values)
    let audioPulseGlow = clamp(u.zoom_params.w, 0.0, 3.0);
    let audioReactiveLuminescence = plasmaBuffer[0].x * audioPulseGlow;
    let mids = plasmaBuffer[0].y;
    let refractionIndex = clamp(u.zoom_params.z, 1.0, 2.5);
    let petalComplexity = clamp(u.zoom_params.x, 1.0, 10.0);

    if (dO < MAX_DIST) {
        let n = calcNormal(p);
        nrm = n;
        matTag = matId;
        let v = -rd;
        let dot_nv = clamp(dot(n, v), 0.0, 1.0);

        // Per-petal cell variation: quantize polar cell of the hit point
        let cellSeed = hash31(floor(vec3<f32>(atan2(p.y, p.x) * petalComplexity, length(p.xy) * 3.0, p.z * 3.0)));

        // Chromatic Refraction / Dispersion (signature look, kept)
        let refDirR = refract(rd, n, 1.0 / refractionIndex);
        let refDirG = refract(rd, n, 1.0 / (refractionIndex * 1.02));
        let refDirB = refract(rd, n, 1.0 / (refractionIndex * 1.04));
        let envR = dot(refDirR, vec3<f32>(0.0, 1.0, 0.0)) * 0.5 + 0.5;
        let envG = dot(refDirG, vec3<f32>(1.0, 0.5, 0.0)) * 0.5 + 0.5;
        let envB = dot(refDirB, vec3<f32>(0.0, 0.5, 1.0)) * 0.5 + 0.5;

        // 3-point lighting rig
        let keyL = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let fillL = normalize(vec3<f32>(-0.7, 0.3, 0.6));
        let backL = normalize(vec3<f32>(0.2, -0.8, 0.8));
        let diffKey = clamp(dot(n, keyL), 0.0, 1.0);
        let diffFill = clamp(dot(n, fillL), 0.0, 1.0);
        let diffBack = clamp(dot(n, backL), 0.0, 1.0);

        if (matId < 1.5) {
            // Vitreous petal: dispersion base + thin-film skin
            var baseColor = vec3<f32>(envR, envG, envB) * 0.5;
            let film = thinFilm(dot_nv, cellSeed * 2.0, time);
            baseColor = mix(baseColor, film, 0.45);
            baseColor *= 0.85 + cellSeed * 0.3;

            col += baseColor * (0.25 + diffKey * 0.75);
            col += baseColor.bgr * diffFill * 0.25;
            col += film * diffBack * 0.3; // translucent back-light through glass

            // Blinn-Phong specular
            let halfDir = normalize(keyL + v);
            let spec = pow(clamp(dot(n, halfDir), 0.0, 1.0), 48.0);
            col += vec3<f32>(1.0) * spec * 0.8;

            // Fresnel rim: glass edge lights up
            col += film * pow(1.0 - dot_nv, 3.0) * (0.8 + mids * 0.4);

            // Radial vein inlay glowing with the audio pulse
            let veins = veinInlay(p, petalComplexity, time);
            let pulse = sin(length(p.xy) * 10.0 - time * 5.0) * 0.5 + 0.5;
            let glowCol = mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(1.0, 0.8, 0.0), pulse);
            col += glowCol * (veins * 0.8 + pow(pulse, 4.0) * 0.3) * audioReactiveLuminescence;
        } else {
            // Singularity core: event-horizon disc + photon ring
            let ring = pow(1.0 - dot_nv, 2.0);
            col += vec3<f32>(0.05, 0.0, 0.1) * diffKey; // near-black horizon
            col += vec3<f32>(0.6, 0.3, 1.0) * ring * 2.0 * (0.6 + plasmaBuffer[0].x * 0.6);
            col += vec3<f32>(1.0, 0.9, 0.6) * pow(ring, 6.0) * audioPulseGlow;
        }

        depth = clamp(1.0 - dO / MAX_DIST, 0.0, 1.0);
    }

    // Quantum Dust / Volumetric glow
    var dustCol = vec3<f32>(0.0);
    for (var i = 1; i < 20; i++) {
        let tp = ro + rd * (f32(i) * MAX_DIST / 20.0);
        let dens = hash31(tp + time * 0.1);
        if (dens > 0.95) {
            dustCol += vec3<f32>(0.2, 0.5, 1.0) * (dens - 0.95) * 20.0 * audioReactiveLuminescence;
        }
    }
    col += dustCol * 0.1;

    // Fog
    col = mix(col, vec3<f32>(0.01, 0.01, 0.03), 1.0 - exp(-0.02 * dO));

    // ACES filmic tonemap + gamma
    col = acesToneMap(col * 1.15);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha: void stays faint, glass bloom is near-solid
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + select(0.05, 0.45, dO < MAX_DIST), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(nrm * 0.5 + 0.5, matTag * 0.25));
}
