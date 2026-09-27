// ═══════════════════════════════════════════════════════════════════
//  Bismuth Hyper-Crystals
//  Category: generative
//  Features: raymarch, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: nucleation seed under the cursor (fold offset tightens near it, so the crystal is finest where it nucleates); fractional fold growth (fold n and n+1 blended by a growth cycle, new terraces emerge instead of popping); fold-lineage colour (abs-fold sign history offsets the iridescence phase, sibling blocks share a hue family)
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR for a light temporal blend
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Complexity, y=ColorShift, z=GrowthSpeed, w=Specular
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;
const NUCLEATION: f32 = 0.3;   // how far the fold offset tightens at the seed

// Per-invocation scene state, set once in main() (same for every map() call of a pixel).
var<private> gFolds: f32;      // fractional fold count (Idea 2)
var<private> gRot: mat2x2<f32>;
var<private> gSeed: vec3<f32>; // nucleation seed in world space (Idea 1)
var<private> gSeedR: f32;      // nucleation radius

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hopper crystal base (stepped box) — HEAD box + bismuth staircase. The staircase keeps
// floor(length(p)*10)/10 but its riser is a short smoothstep bevel, so the normal no longer spikes
// to a one-texel line at every terrace lip.
fn steppedBox(p: vec3<f32>) -> f32 {
    let q = abs(p) - vec3<f32>(1.0);
    let d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
    let s = length(p) * 10.0;
    let stair = floor(s) + smoothstep(0.3, 0.7, fract(s));
    return d - 0.1 * stair / 10.0;
}

// Bounding radius of the folded solid: n abs-folds of offset <= 1 fill a cube of half-size n+1.
fn crystalRadius(folds: f32) -> f32 {
    return (folds + 1.0) * 1.75 + 0.25;
}

// x = distance, y = fold lineage (Idea 3)
fn mapLineage(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Idea 1: nucleation seed — the fold offset (HEAD 1.0) tightens toward the seed, so the
    // terraces are finest where the crystal nucleates and coarsen outward.
    let toSeed = p_in - gSeed;
    let foldOff = 1.0 - NUCLEATION * exp(-dot(toSeed, toSeed) / (gSeedR * gSeedR));

    // Idea 2: fractional fold growth — run n+1 folds, keep the SDF after n, blend by the fraction.
    let nBase = floor(gFolds);
    let grow = gFolds - nBase;
    let n = i32(nBase);

    var dN: f32 = 0.0;
    var lineage: f32 = 0.0;
    var w: f32 = 0.5;

    // Domain repetition and folding
    for (var i = 0; i <= n; i = i + 1) {
        // Idea 3: fold lineage — which abs() planes flipped this generation (3 bits), earlier
        // generations weigh more so sibling blocks of one branch share a hue family.
        let b = step(vec3<f32>(0.0), p);
        let code = (b.x + 2.0 * b.y + 4.0 * b.z) / 8.0;
        lineage = lineage + code * w * select(1.0, grow, i == n);
        w = w * 0.5;

        p = abs(p) - foldOff;

        let pxz = gRot * vec2<f32>(p.x, p.z);
        p.x = pxz.x;
        p.z = pxz.y;

        if (i == n - 1) {
            dN = steppedBox(p);
        }
    }
    let dN1 = steppedBox(p);
    return vec2<f32>(mix(dN, dN1, grow), lineage);
}

fn map(p: vec3<f32>) -> f32 {
    return mapLineage(p).x;
}

fn getNormal(p: vec3<f32>, eps: f32) -> vec3<f32> {
    let e = vec2<f32>(eps, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

fn iridescence(thickness: f32, audio_phase: f32) -> vec3<f32> {
    // Thin film interference approximation
    let phase = thickness * 5.0 + u.zoom_params.y * 3.14 + audio_phase;
    return 0.5 + 0.5 * cos(6.28318 * (phase + vec3<f32>(0.0, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let coord = vec2<i32>(id.xy);

    let uv = (vec2<f32>(id.xy) + 0.5) / vec2<f32>(dimensions);
    let aspect = f32(dimensions.x) / f32(dimensions.y);
    // Screen top = +y (HEAD rendered upside down).
    let p_screen = vec2<f32>((uv.x - 0.5) * 2.0 * aspect, (0.5 - uv.y) * 2.0);

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let bass_mod = bass * 0.1;

    // GrowthSpeed keeps its HEAD role (xz rotation rate of every fold) and also paces the growth
    // cycle; both are time * slider, stateless (extraBuffer scratch does not persist).
    let growthPhase = time * u.zoom_params.z * 0.1;
    gRot = rot(growthPhase + bass_mod);
    // Idea 2: Complexity picks the fold count continuously; the growth cycle adds up to one more
    // generation (0 at GrowthSpeed 0, i.e. exactly the HEAD count x*5+3 without the integer pop).
    let growth = 0.5 - 0.5 * cos(growthPhase * 6.0);
    gFolds = u.zoom_params.x * 5.0 + 3.0 + growth;
    let R = crystalRadius(gFolds);

    // Camera: HEAD sat at z=-5, inside the solid for Complexity >= 0.2 (every ray hit at step 0,
    // one flat colour). Now a corner view scaled to the crystal so it is always outside.
    let camDist = R * 1.3;
    let fwd = normalize(vec3<f32>(-0.75, -0.7, 1.0));
    let ro = -fwd * camDist;
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let focal = 1.4;
    let rd = normalize(p_screen.x * right + p_screen.y * up + focal * fwd);

    // Idea 1: the pointer ray picks the nucleation seed just under the crystal's near surface.
    let mouseScreen = vec2<f32>((u.zoom_config.y - 0.5) * 2.0 * aspect, (0.5 - u.zoom_config.z) * 2.0);
    let mouseRd = normalize(mouseScreen.x * right + mouseScreen.y * up + focal * fwd);
    gSeed = ro + mouseRd * (camDist - 0.55 * R);
    gSeedR = 0.45 * R;

    // Raymarching, starting at the bounding-sphere entry.
    let bq = dot(ro, rd);
    let cq = dot(ro, ro) - R * R;
    let disc = bq * bq - cq;
    var dO: f32 = max(-bq - sqrt(max(disc, 0.0)), 0.0);
    let dFar = camDist + R;
    var hit: bool = false;
    var p: vec3<f32> = ro;
    var steps: i32 = 0;
    var minD: f32 = 1e3;

    if (disc > 0.0) {
        for (var i = 0; i < MAX_STEPS; i = i + 1) {
            steps = i;
            p = ro + rd * dO;
            let dS = map(p);
            minD = min(minD, dS);
            if (dS < SURF_DIST) {
                hit = true;
                break;
            }
            dO = dO + dS * 0.9;
            if (dO > min(dFar, MAX_DIST)) {
                break;
            }
        }
    }

    var col = vec3<f32>(0.0);
    var alpha: f32 = 0.0;
    var depth: f32 = 0.0;

    let bin = u32(abs(p.y) * 10.0) % 100u;
    let fft = extraBuffer[5u + bin];

    if (hit) {
        let n = getNormal(p, max(0.001, dO * 0.0015));
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));

        // Lighting
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);
        let halfDir = normalize(lightDir + viewDir);
        // Exponent floored: w=0 was pow(x,0)=1, a white sheet. Default 0.8 stays 80.
        let spec = pow(max(dot(n, halfDir), 0.0), max(u.zoom_params.w * 100.0, 2.0));

        // Idea 3: fold-lineage colour — same palette, phase offset by the fold branch.
        let lineage = mapLineage(p).y;

        // Iridescence based on position and normal
        let thickness = length(p) * 0.1 + dot(n, viewDir) * 0.5 + lineage * 0.4;
        let albedo = iridescence(thickness, fft * 0.5);

        col = albedo * (diff * 0.5 + 0.5) + vec3<f32>(spec);

        // Fake AO
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);
        col = col * ao;

        alpha = 1.0;
        depth = clamp(1.0 - (dO - (camDist - R)) / (2.0 * R), 0.0, 1.0);
    } else {
        // Near-miss rim: rays grazing the crystal carry a faint iridescent halo (alpha = glow).
        let rim = exp(-max(minD, 0.0) * 3.0) * select(0.0, 1.0, disc > 0.0);
        col = iridescence(0.5, fft * 0.5) * rim * 0.12;
        alpha = rim * 0.35;
    }

    // Light temporal blend from exact C history (A stores HDR, read back as HDR).
    let prev = textureLoad(dataTextureC, coord, 0);
    let hdr = mix(col, max(prev.rgb, vec3<f32>(0.0)), 0.12);
    let outAlpha = max(alpha, prev.a * 0.12);
    textureStore(dataTextureA, coord, vec4<f32>(hdr, outAlpha));

    let display = acesToneMap(hdr * 1.25);
    textureStore(writeTexture, coord, vec4<f32>(display, outAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
