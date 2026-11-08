// ═══════════════════════════════════════════════════════════════════
//  Evolutionary Cellular Gardens
//  Category: generative
//  Features: audio-reactive, mouse-driven, click-reactive, temporal-feedback,
//            generated-depth, semantic-alpha, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-08
//  Ideas: scale-mismatch sporulation where fine lives and coarse is dead; nutrient-facing rhizoids toward the spring well; cell-wall membranes between differing fine cells; colony growth rings from A.a age; generation-tick birth flashes and death embers (fine cells that flipped since the previous generation); glider migrations (hashed mid-cells host a 4-phase Conway glider stepping one fine cell diagonally per generation)
//  A packing: trail RGB + colonyAge in A.a; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Continuous Conway-like rules, parameterized
// state: 0=dead, 1=alive; birthRange and survivalRange are evolving
fn cellularState(uv: vec2<f32>, cellScale: f32, t: f32,
                 birthThreshLow: f32, birthThreshHigh: f32,
                 survLow: f32, survHigh: f32,
                 mutationFreq: f32) -> f32 {
    let cell = floor(uv * cellScale);

    // Evolving cellular state using temporal hash
    let timeSlot = floor(t * mutationFreq);
    let state = hash13(vec3<f32>(cell, timeSlot));

    // Neighbor sum (Moore neighborhood approximated via smooth hash)
    var neighborSum = 0.0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            if (i == 0 && j == 0) { continue; }
            let neighbor = cell + vec2<f32>(f32(i), f32(j));
            let nState = hash13(vec3<f32>(neighbor, timeSlot));
            neighborSum += step(0.5, nState);
        }
    }

    // Birth rule: dead cell becomes alive if neighborSum in [birthLow, birthHigh]
    let wasDead = step(state, 0.5);
    let born = wasDead * step(birthThreshLow, neighborSum) * step(neighborSum, birthThreshHigh);

    // Survival rule: alive cell survives if neighborSum in [survLow, survHigh]
    let wasAlive = 1.0 - wasDead;
    let survives = wasAlive * step(survLow, neighborSum) * step(neighborSum, survHigh);

    return clamp(born + survives, 0.0, 1.0);
}

// Multi-scale cellular garden: layers at different scales
fn cellularGarden(uv: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
                  scale: f32, evolutionSpeed: f32) -> vec4<f32> {
    // Evolving rule parameters: driven by audio bands
    // Bass drives birth rules (tectonic growth), treble drives death/refinement
    let birthLow  = 2.5 + bass * 1.5;       // ~2.5..4
    let birthHigh = 3.5 + bass * 1.0;       // ~3.5..4.5
    let survLow   = 2.0 + mids * 1.0;       // ~2..3
    let survHigh  = 4.0 - treble * 1.5;     // ~2.5..4

    // Fine-grain layer (high frequency cells)
    let fine = cellularState(uv, scale * 20.0, t, birthLow, birthHigh,
                              survLow, survHigh, evolutionSpeed * 3.0);

    // Mid-grain layer
    let mid = cellularState(uv, scale * 8.0, t, birthLow - 0.5, birthHigh + 0.5,
                             survLow - 0.3, survHigh + 0.3, evolutionSpeed * 1.5);

    // Coarse structural layer (long-lived)
    let coarse = cellularState(uv, scale * 3.0, t, birthLow + 0.5, birthHigh + 1.0,
                                survLow + 0.5, survHigh - 0.5, evolutionSpeed * 0.5);

    // Organic blend: coral/plant-like layering
    let organic = fine * 0.3 + mid * 0.5 + coarse * 0.8;

    return vec4<f32>(fine, mid, coarse, organic);
}

// Species color: each "species" has a distinct color mapped from its birth parameters
fn speciesColor(fine: f32, mid: f32, coarse: f32, uv: vec2<f32>,
                t: f32, bass: f32, mids: f32, treble: f32) -> vec3<f32> {
    // Fine species: bioluminescent blue-green
    let col1 = vec3<f32>(0.1 + treble * 0.3, 0.8 + mids * 0.2, 0.5);

    // Mid species: coral pink-orange
    let col2 = vec3<f32>(0.9 + bass * 0.1, 0.3 + mids * 0.3, 0.2);

    // Coarse: deep purple structural
    let col3 = vec3<f32>(0.3 + bass * 0.2, 0.1, 0.6 + treble * 0.3);

    // Temporal color cycling from genetic pressure
    let pulse = 0.5 + 0.5 * sin(t * 1.5 + bass * PI);

    var col = col3 * coarse;
    col = mix(col, col2, mid);
    col = mix(col, col1, fine * treble);
    col *= pulse * 0.4 + 0.6;

    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouseDown = u.zoom_config.w;

    let cellScale     = u.zoom_params.x * 1.5 + 0.5;  // 0.5..2.0
    let evolutionSpd  = u.zoom_params.y * 0.5 + 0.1;  // 0.1..0.6
    let invasiveForce = u.zoom_params.z;               // 0..1 invasive species strength
    let glow          = u.zoom_params.w * 2.0 + 0.5;  // 0.5..2.5

    // Rescue: the old spring attractor + click edge lived in extraBuffer[133..138],
    // which the host re-uploads (zeroed) every frame, so the nutrient well sat
    // pinned near (0,0) and the click burst never fired. Stateless now: the well
    // is the live pointer and the burst rides the newest engine click ripple.
    let rawMouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let sm = rawMouse;
    var clickT = -10.0;
    var clickPos = rawMouse;
    let nClicks = min(u32(u.config.y), 50u);
    for (var ci = 0u; ci < nClicks; ci++) {
        let rp = u.ripples[ci];
        if (rp.z > clickT && rp.z <= t) { clickT = rp.z; clickPos = vec2<f32>(rp.x * aspect, rp.y); }
    }

    // Mouse nutrient attractor (gravity well: lagged, not 1:1)
    let mousePos = sm;
    let mouseDist = length(uvA - mousePos);

    // Click colony-burst: bounded expanding growth front
    let clickAge = max(t - clickT, 0.0);
    let clickEnergy = select(0.0, exp(-clickAge * 1.2), clickT > 0.0 && clickAge < 3.0);
    let burstRing = exp(-pow((length(uvA - clickPos) - clickAge * 0.5) * 12.0, 2.0)) * clickEnergy;

    // Mouse interaction: within radius, plant invasive species or protected zone
    let mouseRadius = 0.12 + bass * 0.05;
    let inMouseZone = smoothstep(mouseRadius, mouseRadius * 0.5, mouseDist);

    // Invasive species disturbs local cellular rules; click burst seeds a
    // vigorous growth front; engine ripples act as spore-seed nutrient bumps
    var nutrientBump = inMouseZone * invasiveForce * 1.5 + burstRing * invasiveForce * 2.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = t - rp.z;
        if (age > 0.0 && age < 3.0) {
            let d2 = distance(uv, rp.xy);
            nutrientBump += exp(-d2 * d2 * 60.0) * exp(-age * 2.0) * 1.2;
        }
    }
    let localBassBoost = bass + nutrientBump;
    let localMidsBoost = mids + inMouseZone * invasiveForce * 0.5 + burstRing * 0.4;
    let localTreble = treble * (1.0 - inMouseZone * invasiveForce * 0.3);

    let localEvolution = evolutionSpd * (1.0 + bass * 0.35 + inMouseZone * invasiveForce * 0.5);

    // Compute multi-scale garden
    let garden = cellularGarden(uvA, t, localBassBoost, localMidsBoost,
                                 localTreble, cellScale, localEvolution);

    let fine   = garden.x;
    let mid    = garden.y;
    let coarse = garden.z;
    let organic = garden.w;

    // ── Temporal feedback memory: colony age + bioluminescent trails ──
    let px = vec2<i32>(global_id.xy);
    let prev = textureLoad(dataTextureC, px, 0); // non-filtering history read
    // Colony age: long-lived occupation becomes "established" (slow approach)
    let colonyAge = clamp(mix(prev.a, clamp(organic, 0.0, 1.0), 0.05), 0.0, 1.0);

    // Background: deep ocean-like darkness
    var color = vec3<f32>(0.01, 0.03, 0.05);

    // Add cellular layers
    let specCol = speciesColor(fine, mid, coarse, uvA, t, bass, mids, treble);
    color = mix(color, specCol, clamp(organic, 0.0, 1.0));

    // Established colonies mature: richer body, golden structural patina
    color *= 0.8 + colonyAge * 0.45;
    color += vec3<f32>(0.9, 0.7, 0.3) * colonyAge * coarse * 0.15;

    // Glow: bioluminescent inner light
    let bioluminescence = fine * treble * glow * 0.5;
    color += vec3<f32>(0.1, 0.8, 0.6) * bioluminescence;

    // Idea 1 — scale-mismatch sporulation: fine alive, coarse dead
    let sporulate = fine * (1.0 - coarse) * (0.35 + treble * 0.5);
    color += vec3<f32>(0.55, 1.0, 0.35) * sporulate * glow * 0.32;

    // Idea 2 — nutrient-facing rhizoids: established colonies send filaments to the well
    let toNutrient = mousePos - uvA;
    let nutLen = max(length(toNutrient), 0.0001);
    let nutDir = toNutrient / nutLen;
    let alongN = dot(uvA - mousePos, nutDir);
    let acrossN = abs(dot(uvA - mousePos, vec2<f32>(-nutDir.y, nutDir.x)));
    let rhizoid = exp(-acrossN * 72.0) * smoothstep(-0.02, 0.18, -alongN)
                * colonyAge * invasiveForce * (0.45 + bass * 0.35);
    color += vec3<f32>(0.18, 0.72, 0.32) * rhizoid;

    // Idea 3 — cell-wall membranes: walls on fine-cell edges where the neighbour across the edge
    // is in a different state (same rule set as the fine layer in cellularGarden)
    let fineScale = cellScale * 20.0;
    let fineCell = floor(uvA * fineScale);
    let fineF = fract(uvA * fineScale) - 0.5;
    let stepX = select(-1.0, 1.0, fineF.x > 0.0);
    let stepY = select(-1.0, 1.0, fineF.y > 0.0);
    let fbLow = 2.5 + localBassBoost * 1.5;
    let fbHigh = 3.5 + localBassBoost * 1.0;
    let fsLow = 2.0 + localMidsBoost * 1.0;
    let fsHigh = 4.0 - localTreble * 1.5;
    let nX = cellularState((fineCell + vec2<f32>(stepX, 0.0) + 0.5) / fineScale, fineScale, t,
                           fbLow, fbHigh, fsLow, fsHigh, localEvolution * 3.0);
    let nY = cellularState((fineCell + vec2<f32>(0.0, stepY) + 0.5) / fineScale, fineScale, t,
                           fbLow, fbHigh, fsLow, fsHigh, localEvolution * 3.0);
    let edgeX = smoothstep(0.36, 0.5, abs(fineF.x));
    let edgeY = smoothstep(0.36, 0.5, abs(fineF.y));
    let membrane = max(edgeX * abs(fine - nX), edgeY * abs(fine - nY));
    color += vec3<f32>(0.55, 0.85, 0.75) * membrane * (0.12 + mid * 0.1 + treble * 0.15) * (0.6 + glow * 0.2);

    // Idea 5 — generation tick: cells that flipped since the previous generation
    // flash (births, warm) or smoulder (deaths, ash ember), decaying over the tick.
    let genFreq = localEvolution * 3.0;
    let genPhase = fract(t * genFreq);
    let finePrev = cellularState(uvA, fineScale, t - 1.0 / max(genFreq, 0.01),
                                 fbLow, fbHigh, fsLow, fsHigh, genFreq);
    let birthFlash = fine * (1.0 - finePrev) * exp(-genPhase * 5.0);
    let deathEmber = finePrev * (1.0 - fine) * exp(-genPhase * 2.5);
    color += vec3<f32>(1.0, 0.85, 0.45) * birthFlash * (0.35 + bass * 0.4) * glow * 0.5;
    color += vec3<f32>(0.45, 0.12, 0.05) * deathEmber * 0.6;

    // Idea 6 — glider migrations: a hashed subset of mid-scale cells host a
    // Conway glider (4 phases), drifting one fine cell diagonally per generation.
    let gTile = floor(uvA * cellScale * 2.0);
    let gh = hash12(gTile + vec2<f32>(17.0, 3.0));
    var gliderLit = 0.0;
    if (gh > 0.3) {
        let gen = floor(t * genFreq);
        let span = 10.0;                         // fine cells per tile
        let local = floor(fract(uvA * cellScale * 2.0) * span);
        let dir = vec2<f32>(select(-1.0, 1.0, gh > 0.65), 1.0);
        let shift = floor((gen + gh * 40.0) / 4.0);
        let phase = i32((gen + gh * 40.0) % 4.0);
        // glider origin wraps inside the tile
        let org = (vec2<f32>(1.0) + dir * shift) - span * floor((vec2<f32>(1.0) + dir * shift) / span);
        var g = local - org;
        g = g - span * floor((g + vec2<f32>(span * 0.5)) / span);
        if (dir.x < 0.0) { g.x = 2.0 - g.x; }
        if (g.x >= 0.0 && g.x <= 2.0 && g.y >= 0.0 && g.y <= 2.0) {
            let bit = i32(g.x) + 3 * i32(g.y);   // row 0 = top (uv.y grows downward)
            // 3x3 glider masks, row-major from the top, the 4 phases of a SE glider
            var mask = 0x1E2u;                                // .#. ..# ###
            if (phase == 1) { mask = 0x0B5u; }               // #.# .## .#.
            if (phase == 2) { mask = 0x1ACu; }               // ..# #.# .##
            if (phase == 3) { mask = 0x0F1u; }               // #.. .## ##.
            gliderLit = f32((mask >> u32(bit)) & 1u);
        }
    }
    color = mix(color, vec3<f32>(0.85, 1.0, 0.7) * (1.1 + treble * 0.6), gliderLit * 0.85);

    // Idea 4 — colony growth rings: established colonies band like lichen as colonyAge crosses ring levels
    let ringPhase = fract(colonyAge * 9.0);
    let growthRing = (1.0 - smoothstep(0.0, 0.09, abs(ringPhase - 0.5))) * smoothstep(0.2, 0.45, colonyAge);
    color = color * (1.0 - growthRing * 0.18) + vec3<f32>(0.85, 0.65, 0.3) * growthRing * clamp(organic, 0.0, 1.0) * 0.16;

    // Coarse structure silhouette shading
    let shadowEdge = smoothstep(0.4, 0.6, coarse) - smoothstep(0.6, 0.8, coarse);
    color += vec3<f32>(0.5 + bass * 0.3, 0.3, 0.7) * shadowEdge * mids * 0.4;

    // Mouse zone highlight (invasive species pulse)
    color += vec3<f32>(0.9, 0.2, 0.3) * inMouseZone * invasiveForce *
             (0.5 + 0.5 * sin(t * 8.0)) * 0.5;

    // Click colony-burst bloom along the growth front
    color += vec3<f32>(0.4, 0.9, 0.5) * burstRing * invasiveForce * 0.9;

    // Temporal evolution shimmer: high-band plasma energy drives sparkle.
    let shimmer = hash13(vec3<f32>(uvA * 50.0, floor(t * localEvolution * 4.0)));
    color += vec3<f32>(0.2, 0.5, 0.3) * shimmer * treble * 0.2;

    // Vignette
    let v = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5) * 1.3);
    color *= v;

    // ── Feedback trails: history bioluminesces and guides future growth ──
    var trail = prev.rgb * 0.93 + color * 0.09;
    trail = min(trail, vec3<f32>(2.5));
    textureStore(dataTextureA, px, vec4<f32>(trail, colonyAge));
    color += trail * 0.12 * (0.5 + treble * 0.5);

    let outColor = acesToneMap(max(color * glow, vec3<f32>(0.0)));

    // Generated depth: structural relief (coarse skeleton highest, age adds)
    let depth = clamp(coarse * 0.5 + mid * 0.3 + fine * 0.15 + colonyAge * 0.2, 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Semantic alpha: colony density + bioluminescent intensity
    let alpha = clamp(0.2 + clamp(organic, 0.0, 1.0) * 0.55 + gliderLit * 0.25 + birthFlash * 0.2 + bioluminescence * 0.4 + burstRing * 0.3, 0.0, 1.0);
    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, alpha));
}
