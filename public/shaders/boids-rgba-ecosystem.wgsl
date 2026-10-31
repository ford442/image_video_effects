// ═══════════════════════════════════════════════════════════════════
//  Boids RGBA Ecosystem
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, flocking, upgraded-rgba
//  Complexity: Very High
//  Chunks From: boids.wgsl (flocking velocity), alpha-multi-state-ecosystem.wgsl (RGBA ecosystem)
//  Created: 2026-04-18
//  By: Agent CB-11
//  Upgraded: 2026-10-31
//  Ideas: isotropic 9-point Laplacian diffusion; surface-tension flock boundary (curvature potential); predator pursuit / flocker evasion steering
//  A packing: raw (s1, s2, resource, toxin); A(0,0).r = sentinel -0.6875
// ═══════════════════════════════════════════════════════════════════
//  Boids-inspired flow-field combined with continuous multi-species
//  ecosystem. RGBA channels store species densities that advect,
//  flock, and compete in a shared environment.
//  R = Species 1 (flockers)
//  G = Species 2 (predators)
//  B = Resource / food
//  A = Toxin / waste
//  zoom_params: x=Flock Cohesion, y=Predation Rate, z=Diffusion Rate, w=Toxin Strength
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// A.r of the corner texel: marks C as this shader's own state (f16-exact, never a density).
const STATE_SENTINEL: f32 = -0.6875;
var<private> stateOwned: bool = false;

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash12 (from alpha-multi-state-ecosystem.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Exact history load. Foreign history (previous shader's A) reads as an empty field.
fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    if (!stateOwned) { return vec4<f32>(0.0, 0.0, 0.5, 0.0); }
    let q = clamp(p, vec2<i32>(0), dims - vec2<i32>(1));
    var v = textureLoad(dataTextureC, q, 0);
    if (q.x == 0 && q.y == 0) { v.r = 0.0; }
    return v;
}

// 5x5 history patch around this texel (row-major, centre = index 12).
var<private> patch5: array<vec4<f32>, 25>;

// Level-set curvature of flocker density at patch texel (cx, cy) in 1..3, from its own 3x3 Hessian.
// kappa = div(grad f / |grad f|); convex edges are negative. Masked to real interfaces only.
fn flockCurvature(cx: i32, cy: i32) -> f32 {
    let o = cy * 5 + cx;
    let f0 = patch5[o].r;
    let fe = patch5[o + 1].r;
    let fw = patch5[o - 1].r;
    let fn_ = patch5[o + 5].r;
    let fs = patch5[o - 5].r;
    let gx = (fe - fw) * 0.5;
    let gy = (fn_ - fs) * 0.5;
    let fxx = fe + fw - 2.0 * f0;
    let fyy = fn_ + fs - 2.0 * f0;
    let fxy = (patch5[o + 6].r - patch5[o + 4].r - patch5[o - 4].r + patch5[o - 6].r) * 0.25;
    let gg = gx * gx + gy * gy;
    let k = (fxx * gy * gy - 2.0 * gx * gy * fxy + fyy * gx * gx) / pow(gg + 1e-4, 1.5);
    return clamp(k, -1.0, 1.0) * smoothstep(0.01, 0.06, sqrt(gg));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;

    stateOwned = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).r == STATE_SENTINEL;

    // Read previous state
    let prevState = stateAt(coord, dims);
    var s1 = prevState.r;
    var s2 = prevState.g;
    var resourceVal = prevState.b;
    var toxin = prevState.a;

    // Seed on first frame, or whenever history is not ours (shader switched in later)
    let seeding = time < 0.1 || !stateOwned;
    if (seeding) {
        s1 = 0.0;
        s2 = 0.0;
        resourceVal = 0.5;
        toxin = 0.0;
        let n1 = hash12(uv * 100.0 + vec2<f32>(12.9898, 78.233));
        if (n1 > 0.92) { s1 = 0.8; }
        let n2 = hash12(uv * 100.0 + vec2<f32>(93.0, 17.0));
        if (n2 > 0.95) { s2 = 0.7; }
    }

    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resourceVal = clamp(resourceVal, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // 5x5 patch (centre uses this texel's own seeded values) and its 3x3 core n[]
    for (var k: i32 = 0; k < 25; k = k + 1) {
        patch5[k] = stateAt(coord + vec2<i32>(k % 5 - 2, k / 5 - 2), dims);
    }
    patch5[12] = vec4<f32>(s1, s2, resourceVal, toxin);
    var n: array<vec4<f32>, 9>;
    for (var k: i32 = 0; k < 9; k = k + 1) {
        n[k] = patch5[(k / 3 + 1) * 5 + (k % 3 + 1)];
    }

    // === PARAMETERS ===
    let flockCohesion = mix(0.01, 0.06, u.zoom_params.x);
    let predationRate = mix(0.01, 0.05, u.zoom_params.y);
    let diffK = 0.4 + 2.0 * u.zoom_params.z;       // 1.0 at the saved default 0.3
    let toxinK = mix(0.2, 1.8, u.zoom_params.w);   // 1.0 at the saved default 0.5
    let toxinDecay = 0.95;
    let resourceRegen = 0.001;

    // === FLOCKING AS CONSERVATIVE TAXIS ===
    // HEAD gathered along a velocity built from `normalize(off)/dist*ps.x` (~1 UV unit, so every cell
    // sampled the texture corner) with the sign inverted, and a gather can never feed a sink pixel.
    // Each species now moves up a steering potential phi: mass j->c = rho_j * max(0, phi_c - phi_j),
    // c->j the mirror term, so every exchange is paired and total mass is conserved.
    //   cohesion + separation: phi = coh * (rho - 0.35 rho^2)  (attracts, then crowds out above ~1.4)
    let coh = mix(0.6, 2.0, u.zoom_params.x);
    let pursue = 0.5 + predationRate * 10.0;
    let sigma = mix(0.1, 0.4, u.zoom_params.x);
    let phiC1 = coh * (s1 - 0.35 * s1 * s1) - s2 + sigma * flockCurvature(2, 2);
    let phiC2 = coh * (s2 - 0.35 * s2 * s2) + pursue * s1;
    var flux1 = 0.0;
    var flux2 = 0.0;
    for (var j: i32 = 0; j < 9; j = j + 1) {
        if (j == 4) { continue; }
        let ox = j % 3 - 1;
        let oy = j / 3 - 1;
        let wj = 1.0 / f32(ox * ox + oy * oy);
        let nj = n[j];
        // ── Idea 3: pursuit / evasion — predators climb the prey density, flockers descend the predator density
        // ── Idea 2: surface tension — sigma * curvature in the flocker potential lowers convex tips so ragged edges round into schools
        let phi1 = coh * (nj.r - 0.35 * nj.r * nj.r) - nj.g + sigma * flockCurvature(2 + ox, 2 + oy);
        let phi2 = coh * (nj.g - 0.35 * nj.g * nj.g) + pursue * nj.r;
        let d1 = clamp(phiC1 - phi1, -1.0, 1.0);
        let d2 = clamp(phiC2 - phi2, -1.0, 1.0);
        flux1 = flux1 + wj * (nj.r * max(d1, 0.0) - s1 * max(-d1, 0.0));
        flux2 = flux2 + wj * (nj.g * max(d2, 0.0) - s2 * max(-d2, 0.0));
    }
    let steer = select(0.12, 0.0, seeding);
    s1 = max(s1 + steer * flux1, 0.0);
    s2 = max(s2 + steer * flux2, 0.0);

    // ── Idea 1: isotropic 9-point Laplacian for every field (same scale as the old 5-point stencil)
    let c4 = vec4<f32>(s1, s2, resourceVal, toxin);
    let edges = n[1] + n[3] + n[5] + n[7];
    let corners = n[0] + n[2] + n[6] + n[8];
    let lap = (4.0 * edges + corners - 20.0 * c4) / 6.0;
    let lapS1 = lap.x;
    let lapS2 = lap.y;
    let lapResource = lap.z;
    let lapToxin = lap.w;

    // === ECOSYSTEM DYNAMICS ===
    // Species consume resourceVal to grow
    let food1 = s1 * resourceVal * flockCohesion;
    let food2 = s2 * resourceVal * flockCohesion * 0.8;

    // Predation: s2 eats s1
    let predation = s1 * s2 * predationRate;

    // Species produce toxin
    let toxinProduction1 = s1 * 0.005 * toxinK;
    let toxinProduction2 = s2 * 0.004 * toxinK;

    // Toxin hurts both species (HEAD fix: proportional to the density it poisons; the old absolute 0.02*toxin wiped out every cell below ~0.2)
    let toxinDamage1 = s1 * toxin * 0.1 * toxinK;
    let toxinDamage2 = s2 * toxin * 0.1 * toxinK;

    // Resource regeneration
    resourceVal += resourceRegen - food1 - food2;
    resourceVal += lapResource * 0.1 * diffK;

    // Species update
    s1 += food1 - predation - toxinDamage1 + lapS1 * 0.05 * diffK;
    s2 += food2 + predation * 0.3 - toxinDamage2 + lapS2 * 0.05 * diffK;

    // Toxin update
    toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01;
    toxin += lapToxin * 0.08 * diffK;
    toxin *= toxinDecay;

    // Natural death
    s1 *= 0.998;
    s2 *= 0.998;

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resourceVal = clamp(resourceVal, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === MOUSE INTERACTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    // Mouse adds resourceVal and removes toxin (nurturing)
    resourceVal += mouseInfluence * 0.5;
    toxin -= mouseInfluence * 0.3;
    toxin = max(toxin, 0.0);
    // Mouse attracts species 1 (flocking toward cursor)
    s1 += mouseInfluence * 0.3;

    // Ripples seed new life
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.04) {
            let strength = smoothstep(0.04, 0.0, rDist) * max(0.0, 1.0 - age);
            let isEven = select(1.0, 0.0, f32(i) % 2.0 < 1.0);
            s1 += strength * isEven * 0.5;
            s2 += strength * (1.0 - isEven) * 0.5;
        }
    }
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);

    // === STORE STATE === (corner texel carries the ownership sentinel)
    let isCorner = gid.x == 0u && gid.y == 0u;
    textureStore(dataTextureA, coord, vec4<f32>(select(s1, STATE_SENTINEL, isCorner), s2, resourceVal, toxin));

    // === VISUALIZATION ===
    // Species 1 = cyan/teal, Species 2 = magenta/pink, Resource = green, Toxin = dark purple
    let colorS1 = vec3<f32>(0.0, 0.8, 1.0) * min(s1, 1.0);
    let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
    let colorResource = vec3<f32>(0.2, 0.7, 0.2) * min(resourceVal, 1.0) * 0.3;
    let colorToxin = vec3<f32>(0.3, 0.0, 0.4) * min(toxin, 1.0) * 0.5;

    var displayColor = colorS1 + colorS2 + colorResource + colorToxin;

    // Highlight flow edges
    let s1Grad = length(vec2<f32>(n[5].r - n[3].r, n[7].r - n[1].r)) * 0.5;
    let s2Grad = length(vec2<f32>(n[5].g - n[3].g, n[7].g - n[1].g)) * 0.5;
    let edgeHighlight = (s1Grad + s2Grad) * 2.0;
    displayColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;
    displayColor = aces(max(displayColor, vec3<f32>(0.0)) * 1.1);

    // Alpha = total biomass (meaningful, not hardcoded)
    let biomass = min(s1 + s2, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(displayColor, biomass));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
