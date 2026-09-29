// ═══════════════════════════════════════════════════════════════════
//  Sentient Holographic Neuro-Lace Matrix
//  Category: generative
//  Features: raymarching, audio-reactive, mouse-driven, held-drag, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: breathing lace wave (bass-driven thickness swell travelling down the flight axis); bioluminescent depth fog (step-count-lit haze); held-mouse neuron bloom (camera-borne pull node with glow)
//  A packing: ACES display RGBA (alpha = fogged lace coverage raised by node glow); C is not read
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV (y=0 top), w=MouseDown
    zoom_params: vec4<f32>,  // x=Complexity, y=ColorShift, z=GrowthSpeed, w=Specular
    ripples: array<vec4<f32>, 50>,
};

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

const MAX_STEPS: i32 = 120;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 40.0;        // fog reaches ~95% here, so no distance moiré
const PULL_R: f32 = 2.0;           // HEAD pull radius
const PULL_DEPTH: f32 = 3.5;       // pull node rides this far ahead of the camera (> PULL_R: camera never warped)
const FOG_DENSITY: f32 = 0.075;
const GYROID_LIP: f32 = 1.7320508; // max |grad g| per unit scale (numpy-verified)

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Distance estimator for the neuro-lace.
// pull.xyz = camera-relative pull node, pull.w = pull strength (0.5 hover as HEAD, 1.0 held)
fn map(p_in: vec3<f32>, pull: vec4<f32>) -> f32 {
    var p = p_in;

    // Audio reactivity (plasmaBuffer[0].x = bass)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Mouse distortion: pull strands towards the node. Smooth radial gather so the
    // warp stays Lipschitz (<= 1 + w) and the distance is divided by that bound.
    var lip = 1.0;
    let toM = p - pull.xyz;
    let r2 = dot(toM, toM) / (PULL_R * PULL_R);
    if (r2 < 1.0) {
        let fall = (1.0 - r2) * (1.0 - r2);
        p = pull.xyz + toM * (1.0 + pull.w * fall);
        lip = 1.0 + pull.w;
    }

    // Gyroid-like intertwined lattice. The gyroid is already periodic, so HEAD's
    // fract() repeat (spacing 2 vs period 2pi/scale -> seams) is dropped. The y offset
    // puts the flight axis (x=0, y=0) on the channel line where g == 1 exactly.
    let scale = u.zoom_params.x * 2.0 + 1.0;
    let q = p + vec3<f32>(0.0, 1.5707963 / scale, 0.0);
    let g = dot(sin(q * scale), cos(q.zxy * scale));

    // Idea 1 — breathing lace wave: HEAD's pulse term, now a thickness swell whose
    // crests roll away down the flight axis (-z, faster than the camera); bass fattens them.
    let wave = 0.5 + 0.5 * sin(q.z * 0.9 + u.config.x * u.zoom_params.z * 2.0);
    let thick = 0.3 + (0.06 + 0.3 * bass) * wave;

    // Thin lace sheet |g| < thick, scaled by the gyroid + wave gradient bound
    let d = (abs(g) - thick) / (scale * GYROID_LIP + 0.17);
    return d / lip;
}

// Normal calculation
fn getNormal(p: vec3<f32>, pull: vec4<f32>) -> vec3<f32> {
    let d = map(p, pull);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy, pull),
        map(p - e.yxy, pull),
        map(p - e.yyx, pull)
    );
    return normalize(n);
}

// Main compute shader
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let res = vec2<f32>(dimensions);
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Camera setup (screen y grows downward -> flip for a y-up scene)
    let ro = vec3<f32>(0.0, 0.0, -3.0 - u.config.x * u.zoom_params.z * 0.5);
    let rd = normalize(vec3<f32>(uv.x, -uv.y, 1.0));

    // Idea 3 — held-mouse neuron bloom: the pull node sits under the cursor, PULL_DEPTH
    // ahead of the camera, so it travels with the flight instead of receding.
    let mUv = vec2<f32>((u.zoom_config.y - 0.5) * res.x / res.y, 0.5 - u.zoom_config.z);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let pullC = ro + normalize(vec3<f32>(mUv, 1.0)) * PULL_DEPTH;
    let pull = vec4<f32>(pullC, 0.5 + 0.5 * held);

    var p = ro;
    var t = 0.0;
    var steps: i32 = 0;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t;
        let d = map(p, pull);
        steps = i;
        if (d < SURF_DIST * (1.0 + t)) {
            hit = true;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d;
    }

    let colorShift = u.zoom_params.y;
    let baseColor = vec3<f32>(0.1, 0.5 + colorShift * 0.5, 0.8 - colorShift * 0.3);
    let nodeCol = mix(baseColor, vec3<f32>(0.85, 1.0, 1.0), 0.6);

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p, pull);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0) * u.zoom_params.w;

        // Ambient occlusion based on steps
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        col = baseColor * diff * ao + spec;

        // Idea 3 — the gathered lace around the held node is lit by it
        let toNode = pullC - p;
        let nodeLight = exp(-dot(toNode, toNode) * 0.7) * (0.3 + 0.7 * max(dot(n, normalize(toNode + vec3<f32>(1e-5))), 0.0));
        col += nodeCol * held * (0.5 + bass) * nodeLight;
    } else {
        // Background glow
        col = vec3<f32>(0.01, 0.02, 0.05);
    }

    // Idea 2 — bioluminescent depth fog: rays that grazed many strands (high step count)
    // light the haze in the lace colour; distant lace dissolves into it.
    let stepGlow = f32(steps) / f32(MAX_STEPS);
    let haze = vec3<f32>(0.01, 0.02, 0.05) + baseColor * (0.04 + 0.55 * stepGlow * stepGlow);
    let fog = select(1.0, 1.0 - exp(-t * FOG_DENSITY), hit);
    col = mix(col, haze, fog);

    // Idea 3 — the neuron node itself: a glow point in the air, hidden behind nearer lace
    let tc = max(dot(pullC - ro, rd), 0.0);
    let dRay = length(ro + rd * tc - pullC);
    let nodeVis = select(1.0, 0.0, hit && t < tc);
    let nodeGlow = held * (0.6 + 0.8 * bass) * (exp(-dRay * dRay * 10.0) * 1.5 + exp(-dRay * 2.5) * 0.25) * nodeVis;
    col += nodeCol * nodeGlow;

    // Post-processing (holographic scanlines)
    col *= 0.9 + 0.1 * sin(uv.y * 100.0 + u.config.x * 5.0);

    let outCol = acesFilm(max(col, vec3<f32>(0.0)));
    let coverage = select(0.0, 1.0 - fog, hit);
    let alpha = clamp(max(coverage, nodeGlow * 0.8 + stepGlow * 0.3), 0.0, 1.0);
    let rgba = vec4<f32>(outCol, alpha);

    let depth = select(1.0, clamp(t / MAX_DIST, 0.0, 1.0), hit);
    textureStore(writeTexture, id.xy, rgba);
    textureStore(dataTextureA, id.xy, rgba);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
