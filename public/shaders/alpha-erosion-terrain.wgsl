// ═══════════════════════════════════════════════════════════════════
//  Alpha Erosion Terrain
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-11-01
//  Ideas: alluvial fans where slope flattens; stream incision where water concentrates; talus slump (thermal erosion, mass-conserving); hillshaded relief with wet sheen
//  A packing: raw (height, water, sediment, erosion)
// ═══════════════════════════════════════════════════════════════════
//  RGBA Channels:
//    R = Terrain height (from image luminance, can change)
//    G = Water depth (0.0 to 1.0+)
//    B = Sediment carried by water (0.0 to 1.0)
//    A = Accumulated erosion amount (history of material removed)
//  Why f32: Hydraulic erosion requires tracking millimeter-scale
//  height changes over thousands of iterations. 8-bit would make
//  the terrain either flat or cliff with no gradual valleys.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

// 2026-11-01 Idea 1 helper: flux into a cell from one neighbour when the height
// difference exceeds the angle of repose. Built from previous-frame heights and
// the pair-averaged water, so the neighbour computes the exact opposite value
// (mass moves, it is not created).
fn slumpFlux(h0: f32, w0: f32, n: vec4<f32>, talus: f32) -> f32 {
    let wet = 0.4 + min(0.5 * (w0 + n.g), 1.0);
    return wet * (max(n.r - h0 - talus, 0.0) - max(h0 - n.r - talus, 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

    // Read previous state
    let prevState = stateAt(coord, dims);
    var height = prevState.r;
    var water = prevState.g;
    var sediment = prevState.b;
    var erosion = prevState.a;

    // Seed on first frame from image luminance
    if (time < 0.1) {
        let sourceLuma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        height = sourceLuma;
        water = 0.0;
        sediment = 0.0;
        erosion = 0.0;
    }

    height = clamp(height, 0.0, 2.0);
    water = clamp(water, 0.0, 2.0);
    sediment = clamp(sediment, 0.0, 2.0);
    erosion = clamp(erosion, 0.0, 2.0);

    // === PARAMETERS ===
    let rainRate = mix(0.001, 0.01, u.zoom_params.x) * (1.0 + audio.x * 0.7);
    let erosionRate = mix(0.01, 0.1, u.zoom_params.y) * (1.0 + audio.z * 0.35);
    let depositionRate = mix(0.01, 0.1, u.zoom_params.z);
    let sedimentCapacity = mix(0.25, 2.5, u.zoom_params.w);

    // === NEIGHBOR SAMPLES ===
    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    // === HEIGHT GRADIENT ===
    let gradX = (right.r - left.r) / (2.0 * ps.x);
    let gradY = (up.r - down.r) / (2.0 * ps.y);
    let slope = length(vec2<f32>(gradX, gradY));

    // === WATER FLOW ===
    // Water flows downhill
    let waterCapacity = slope * water * erosionRate * sedimentCapacity;
    let sedimentExcess = sediment - waterCapacity;

    // Erode if carrying too little sediment
    if (sedimentExcess < 0.0 && water > 0.01) {
        let erodeAmount = min(-sedimentExcess * 0.1, height * 0.01);
        height -= erodeAmount;
        sediment += erodeAmount;
        erosion += erodeAmount;
    }
    // Deposit if carrying too much
    else if (sedimentExcess > 0.0) {
        let depositAmount = sedimentExcess * depositionRate;
        height += depositAmount;
        sediment -= depositAmount;
    }

    // Idea 1 — alluvial fans: extra deposit where slope flattens and sediment is high
    let fanGate = smoothstep(0.45, 0.08, slope) * smoothstep(0.08, 0.35, sediment);
    let fanDeposit = sediment * depositionRate * fanGate * 0.35;
    height += fanDeposit;
    sediment -= fanDeposit;

    // ── 2026-11-01 Idea 1: talus slump (thermal erosion) ───────────────
    // Hydraulic erosion's partner: banks steeper than the angle of repose fail
    // and slide downhill, faster when saturated. Speed rides Erosion Rate.
    let talus = 0.03;
    let slumpK = erosionRate * 0.08;
    let slumpNet = slumpK * (slumpFlux(prevState.r, prevState.g, left, talus)
                           + slumpFlux(prevState.r, prevState.g, right, talus)
                           + slumpFlux(prevState.r, prevState.g, down, talus)
                           + slumpFlux(prevState.r, prevState.g, up, talus));
    height += slumpNet;
    erosion += max(-slumpNet, 0.0);

    // === WATER MOVEMENT (advect toward lower neighbors) ===
    var flowOut = 0.0;
    let myTotalHeight = height + water * 0.1;
    let lTotal = left.r + left.g * 0.1;
    let rTotal = right.r + right.g * 0.1;
    let dTotal = down.r + down.g * 0.1;
    let uTotal = up.r + up.g * 0.1;

    flowOut += max(0.0, myTotalHeight - lTotal) * 0.1;
    flowOut += max(0.0, myTotalHeight - rTotal) * 0.1;
    flowOut += max(0.0, myTotalHeight - dTotal) * 0.1;
    flowOut += max(0.0, myTotalHeight - uTotal) * 0.1;

    water += rainRate;
    water -= flowOut;
    water = max(water, 0.0);

    // Idea 2 — stream incision: extra downcut where water concentrates
    let incision = water * flowOut * erosionRate * 0.45 * smoothstep(0.04, 0.18, slope);
    height -= incision;
    erosion += incision;
    sediment += incision * 0.35;

    // Sediment moves with water
    sediment *= 0.995; // Some sediment settles

    // === MOUSE RAIN ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseRain = smoothstep(0.15, 0.0, mouseDist) * mouseDown;
    water += mouseRain * 0.3;

    // === RIPPLE STORMS ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let storm = exp(-abs(rDist - age * 0.2) * 52.0 - age * 1.4);
            water += storm * (0.16 + audio.x * 0.18);
            sediment += storm * audio.y * 0.035;
        }
    }

    water = clamp(water, 0.0, 2.0);
    height = clamp(height, 0.0, 2.0);
    sediment = clamp(sediment, 0.0, 2.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(height, water, sediment, erosion));

    // === VISUALIZATION ===
    // Height = terrain color
    let lowColor = vec3<f32>(0.2, 0.15, 0.1);    // Deep brown
    let midColor = vec3<f32>(0.4, 0.35, 0.2);    // Earth
    let highColor = vec3<f32>(0.8, 0.8, 0.75);   // Stone/snow

    var terrainColor: vec3<f32>;
    if (height < 0.3) {
        terrainColor = mix(lowColor, midColor, height / 0.3);
    } else if (height < 0.7) {
        terrainColor = mix(midColor, highColor, (height - 0.3) / 0.4);
    } else {
        terrainColor = highColor;
    }

    // ── 2026-11-01 Idea 2: hillshaded relief ───────────────────────────
    // Lambert from a low north-west sun on the height gradient already loaded
    // for the solver (flat ground = 1.0), so incised channels and fans read as
    // relief and not only as colour.
    let reliefGrad = vec2<f32>(right.r - left.r, up.r - down.r) * 12.0;
    let reliefN = normalize(vec3<f32>(-reliefGrad.x, -reliefGrad.y, 1.0));
    let sunDir = normalize(vec3<f32>(-0.55, -0.55, 0.63));
    let hillshade = clamp(dot(reliefN, sunDir) / 0.63, 0.0, 1.6);
    terrainColor = terrainColor * mix(1.0, hillshade, 0.7);

    // Water overlay
    let waterColor = vec3<f32>(0.2, 0.4, 0.6);
    let waterVis = min(water, 1.0);
    var displayColor = mix(terrainColor, waterColor, waterVis * 0.6);

    // Sediment = muddy brown tint
    let sedimentColor = vec3<f32>(0.5, 0.4, 0.2);
    displayColor = mix(displayColor, sedimentColor, min(sediment, 0.5));

    // Alluvial fan visual: pale silt apron on flattened deposits
    let fanVis = smoothstep(0.45, 0.08, slope) * smoothstep(0.08, 0.4, sediment);
    displayColor = mix(displayColor, vec3<f32>(0.72, 0.62, 0.42), fanVis * 0.35);

    // Erosion = reddish scars
    let erosionColor = vec3<f32>(0.6, 0.3, 0.2);
    displayColor = mix(displayColor, erosionColor, min(erosion * 0.5, 0.3));

    // Stream incision visual: darker wet channel
    let channelVis = smoothstep(0.05, 0.22, water) * smoothstep(0.03, 0.16, slope);
    displayColor = mix(displayColor, vec3<f32>(0.12, 0.18, 0.22), channelVis * 0.4);

    // Idea 2 (cont.): wet sheen — tight glint from the water-surface gradient.
    let waterN = normalize(vec3<f32>(-(right.g - left.g) * 3.0, -(up.g - down.g) * 3.0, 1.0));
    let sunHalf = normalize(sunDir + vec3<f32>(0.0, 0.0, 1.0));
    let waterSpec = pow(max(dot(waterN, sunHalf), 0.0), 48.0);
    displayColor += vec3<f32>(0.85, 0.93, 1.0) * waterSpec * waterVis * 0.6;

    displayColor += audio * vec3<f32>(0.05, 0.08, 0.12) * waterVis;

    let alpha = clamp(water * 0.4 + sediment * 0.22 + erosion * 0.55, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(aces(displayColor), alpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
