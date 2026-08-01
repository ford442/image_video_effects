// ═══════════════════════════════════════════════════════════════════
//  Ethereal Bismuth-Resonance Void-Owl
//  Category: generative
//  Tags: ["crystal", "bismuth", "avian", "iridescent", "void", "quantum"]
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

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D hash
fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.173, 29.771, 33.319));
    return fract(dot(q, q.yzx + 19.19));
}

// Simple 3D noise
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n = i.x + i.y * 157.0 + 113.0 * i.z;

    let v0 = mix(hash31(i + vec3<f32>(0.0,0.0,0.0)), hash31(i + vec3<f32>(1.0,0.0,0.0)), u.x);
    let v1 = mix(hash31(i + vec3<f32>(0.0,1.0,0.0)), hash31(i + vec3<f32>(1.0,1.0,0.0)), u.x);
    let v2 = mix(hash31(i + vec3<f32>(0.0,0.0,1.0)), hash31(i + vec3<f32>(1.0,0.0,1.0)), u.x);
    let v3 = mix(hash31(i + vec3<f32>(0.0,1.0,1.0)), hash31(i + vec3<f32>(1.0,1.0,1.0)), u.x);

    let a = mix(v0, v1, u.y);
    let b = mix(v2, v3, u.y);

    return mix(a, b, u.z);
}

// smin
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn box(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdf(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    let audioBass = plasmaBuffer[0].x * 0.5 + 0.5;
    let complexity = u.zoom_params.x; // zoom_params.x: Crystal Complexity (Fold Iterations) (default: 0.5)
    let audioReactivityScale = u.zoom_params.y; // zoom_params.y: Audio Reactivity Scale (default: 0.5)

    let mouse = u.zoom_config.yz;
    let mouseDist = length(p.xy - (mouse * 2.0 - 1.0) * 5.0);

    // Gravitational lens distortion around mouse (the singularity)
    if (mouseDist < 3.0) {
        let twistAmount = (3.0 - mouseDist) * 0.5;
        p = vec3<f32>(rot(twistAmount) * p.xy, p.z);
    }

    var d = 1000.0;
    var matId = 0.0;

    // Background / orbital debris field
    let debrisDensity = u.zoom_params.w; // zoom_params.w: Orbital Debris Density (default: 0.5)

    // Orbital debris (floating monoliths)
    var p_debris = p;
    // Rotate debris based on time and distance from center
    let r = length(p.xz);
    p_debris = vec3<f32>(rot(u.time * 0.2 + r * 0.1) * p_debris.xz, p_debris.y).xzy;

    // Use modular space for debris
    let spacing = mix(6.0, 2.0, debrisDensity);
    let id_debris = floor(p_debris / spacing);
    p_debris = p_debris - (id_debris + 0.5) * spacing;

    // Only place debris sparsely
    let hashDebris = hash31(id_debris);
    if (hashDebris > 0.8 - debrisDensity * 0.3) {
        let debris_d = box(p_debris, vec3<f32>(0.2, 0.8, 0.2));
        if (debris_d < d) {
            d = debris_d;
            matId = 3.0; // Debris material
        }
    }

    // --- The Owl ---
    var p_owl = p;

    // Core singularity (heart/eyes)
    let heartSize = 0.3 + audioBass * 0.2 * audioReactivityScale;
    let heart = length(p_owl - vec3<f32>(0.0, 1.0, 0.0)) - heartSize;
    if (heart < d) {
        d = heart;
        matId = 2.0; // Core material
    }

    // Bismuth Step-Growth Geometry (The Skeleton / Feathers)
    // We use domain folding and box-framing to create the characteristic bismuth look

    // Symmetrical body
    p_owl.x = abs(p_owl.x);

    // Base shape
    var body = box(p_owl - vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.5, 2.0, 1.0));

    let iterations = i32(mix(2.0, 6.0, complexity));
    var scale = 1.0;

    var d_bismuth = 1000.0;
    var p_b = p_owl;

    for(var i=0; i<iterations; i++) {
        p_b = p_b - vec3<f32>(0.5, 0.2, 0.1) * scale;
        p_b = vec3<f32>(rot(0.2) * p_b.xy, p_b.z);
        p_b = vec3<f32>(p_b.x, rot(0.1) * p_b.yz);
        p_b = abs(p_b);

        // Characteristic square/step-like hollows of bismuth
        let stepBox = box(p_b, vec3<f32>(0.8, 0.8, 0.1) * scale);
        // Cut out the center to make it hollow/step-like
        let hole = box(p_b, vec3<f32>(0.6, 0.6, 0.2) * scale);
        let part = max(stepBox, -hole);

        d_bismuth = smin(d_bismuth, part, 0.1 * scale);

        scale *= 0.7;
    }

    // Audio reactive quantum feathers
    // Distort the structure based on audio and height
    let featherDistortion = sin(p_b.y * 10.0 - u.time * 2.0) * cos(p_b.x * 10.0 + u.time) * 0.1 * audioBass * audioReactivityScale;
    d_bismuth += featherDistortion;

    // Limit to rough owl shape
    let owlMask = box(p_owl, vec3<f32>(2.0, 2.5, 1.5)) - 0.5;
    d_bismuth = max(d_bismuth, owlMask);

    if (d_bismuth < d) {
        d = d_bismuth;
        matId = 1.0; // Bismuth material
    }

    return vec2<f32>(d * 0.6, matId); // Multiply distance by factor < 1 to prevent raymarching artifacts with heavy distortion/folding
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let h = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        sdf(p + h.xyy).x - sdf(p - h.xyy).x,
        sdf(p + h.yxy).x - sdf(p - h.yxy).x,
        sdf(p + h.yyx).x - sdf(p - h.yyx).x
    ));
}

// Custom iridescence function
fn getIridescence(dot_nv: f32, shift: f32) -> vec3<f32> {
    // Cycle through cyan, magenta, yellow, gold
    let t = dot_nv * 3.0 + shift * 5.0 + u.time * 0.5;
    let r = 0.5 + 0.5 * cos(t);
    let g = 0.5 + 0.5 * cos(t + 2.094); // +120 deg
    let b = 0.5 + 0.5 * cos(t + 4.188); // +240 deg

    // Bias towards neon cyan/magenta/gold
    return mix(vec3<f32>(r, g, b), vec3<f32>(1.0, 0.2, 0.8), 0.3) * vec3<f32>(0.8, 1.0, 1.2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let uv = (vec2<f32>(id.xy) * 2.0 - u.resolution) / min(u.resolution.x, u.resolution.y);

    // Camera setup
    let camPos = vec3<f32>(0.0, 0.0, 8.0);
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fw = normalize(lookAt - camPos);
    let ri = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fw));
    let up = cross(fw, ri);

    let rd = normalize(uv.x * ri + uv.y * up + 1.5 * fw);

    var ro = camPos;
    var p = ro;

    var t = 0.0;
    var matId = 0.0;
    var d = 0.0;

    // Subsurface scattering / glow accumulation
    var glow = vec3<f32>(0.0);
    let maxSteps = 100;
    var hit = false;

    for(var i=0; i<maxSteps; i++) {
        p = ro + rd * t;
        let res = sdf(p);
        d = res.x;
        matId = res.y;

        if (d < 0.005) {
            hit = true;
            break;
        }

        // Accumulate glow based on proximity
        if (d < 0.5) {
             let g = 0.02 / (0.01 + d * d);
             if (matId == 2.0) {
                 glow += vec3<f32>(0.1, 0.8, 1.0) * g * 0.1; // Core glow
             } else if (matId == 1.0) {
                 glow += vec3<f32>(1.0, 0.2, 0.8) * g * 0.02; // Bismuth subtle glow
             } else if (matId == 3.0) {
                 glow += vec3<f32>(0.9, 0.8, 0.2) * g * 0.05; // Debris glow
             }
        }

        t += d;
        if (t > 20.0) { break; }
    }

    var col = vec3<f32>(0.0);

    let audioBass = plasmaBuffer[0].x * 0.5 + 0.5;

    // Volumetric aurora fog (Void Ether)
    var fogCol = vec3<f32>(0.0);
    for(var i=1; i<5; i++) {
        let fi = f32(i);
        let fogP = ro + rd * (t * (fi / 5.0)); // sample along the ray
        let n = noise3D(fogP * 0.2 + vec3<f32>(0.0, u.time * -0.5, u.time * 0.2));
        let fogColor = mix(vec3<f32>(0.0, 0.2, 0.5), vec3<f32>(0.8, 0.0, 0.5), n);
        fogCol += fogColor * n * 0.05 * (1.0 - (fi / 5.0));
    }
    col += fogCol;

    if (hit) {
        let n = calcNormal(p);
        let v = -rd;
        let dot_nv = clamp(dot(n, v), 0.0, 1.0);

        // Base lighting
        let l1 = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let l2 = normalize(vec3<f32>(-1.0, -0.5, -1.0));

        let diff1 = clamp(dot(n, l1), 0.0, 1.0);
        let diff2 = clamp(dot(n, l2), 0.0, 1.0);

        let shift = u.zoom_params.z; // zoom_params.z: Iridescence Shift

        if (matId == 1.0) {
            // Bismuth material
            let iridescence = getIridescence(dot_nv, shift);
            col += iridescence * diff1 * 0.8;
            col += iridescence * diff2 * 0.3;

            // Rim light
            let rim = 1.0 - dot_nv;
            col += vec3<f32>(0.5, 1.0, 1.0) * pow(rim, 4.0) * 0.5;

        } else if (matId == 2.0) {
            // Core singularity
            col += vec3<f32>(0.0, 1.0, 1.0) * 2.0 * (0.5 + 0.5 * sin(u.time * 5.0));
        } else if (matId == 3.0) {
            // Debris
            col += vec3<f32>(1.0, 0.8, 0.2) * diff1;
            // Glowing edges
            let rim = 1.0 - dot_nv;
            col += vec3<f32>(1.0, 0.5, 0.0) * pow(rim, 2.0);
        }
    }

    // Add subsurface scattering / bloom
    col += glow;

    // Tone mapping
    col = col / (1.0 + col);

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
