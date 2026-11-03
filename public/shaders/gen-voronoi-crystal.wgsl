// ═══════════════════════════════════════════════════════════════════
//  Voronoi Crystal
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-01
//  Ideas: triple-junction grain corners; L∞ facet flats; dislocation glide lines; annealing front bloom; crystalline structural faults; piezoelectric charge flashes; Michel–Lévy polarised-light grain tint (§12.2F); grain-local twin lamellae; misorientation-weighted grain boundaries
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
const TAU: f32 = 6.28318530718;

// Hash function for pseudo-random values
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// 2D rotation
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Smooth Voronoi with animated seeds. Also returns the nearest seed's grain-local
// vector and the second-nearest grain's hash (second-pass ideas 5–7 promote them).
struct Voro {
    m: vec4<f32>,
    local: vec2<f32>,
    nb: f32,
}

fn voronoiCrystal(uv: vec2<f32>, t: f32, crystalCount: f32, irregularity: f32) -> Voro {
    let n = floor(uv * crystalCount);
    let f = fract(uv * crystalCount);
    
    var f1 = 10.0;  // Distance to closest seed
    var f2 = 10.0;  // Distance to second closest
    var f3 = 10.0;  // Idea 1 — third nearest (triple junctions)
    var cellId = vec2<f32>(0.0);
    var seedPos = vec2<f32>(0.0);
    var cell2 = n;
    var localVec = vec2<f32>(0.0);
    
    // Search neighborhood
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let cell = n + g;
            
            // Animated seed position with irregularity
            let baseSeed = hash22(cell);
            let anim = vec2<f32>(
                sin(t * 0.3 + baseSeed.x * 6.28) * irregularity,
                cos(t * 0.2 + baseSeed.y * 6.28) * irregularity
            );
            let o = baseSeed + anim;
            
            // Add some rotation based on cell
            let angle = t * 0.1 + baseSeed.x * 3.14;
            let r = g + o - f;
            let rotated = rot2(angle) * r;
            
            // Distance with optional stretching
            let stretch = mix(1.0, 0.5 + baseSeed.y, irregularity);
            let euclid = length(vec2<f32>(rotated.x, rotated.y / stretch));
            // Idea 2 — L∞ mix so cell interiors facet instead of rounding.
            let linf = max(abs(rotated.x), abs(rotated.y / stretch));
            let d = mix(euclid, linf, 0.48);
            
            if (d < f1) {
                f3 = f2;
                f2 = f1;
                f1 = d;
                cell2 = cellId;
                cellId = cell;
                seedPos = o;
                localVec = rotated;
            } else if (d < f2) {
                f3 = f2;
                f2 = d;
                cell2 = cell;
            } else if (d < f3) {
                f3 = d;
            }
        }
    }
    
    return Voro(vec4<f32>(f1, f2, f3, hash21(cellId)), localVec, hash21(cell2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }
    let resolution = vec2<f32>(dims);
    let uv = (vec2<f32>(global_id.xy) + vec2<f32>(0.5)) / resolution;
    let t = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Parameters - safe randomization
    let growthSpeed = mix(0.2, 1.5, u.zoom_params.x);
    let crystalCount = mix(2.0, 20.0, u.zoom_params.y);
    let irregularity = mix(0.0, 0.4, u.zoom_params.z);
    let glowIntensity = mix(0.5, 2.0, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv * vec2<f32>(aspect, 1.0);
    
    // Idea 1: crystalline structural faults (diagonal coordinate shift)
    let fault = step(0.0, p.x + p.y - 1.0) * 0.1;
    p += vec2<f32>(fault, -fault);

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouseUv = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouseUv = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(t - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouseUv += mouseVelocity * springDt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouseUv.x; extraBuffer[134] = mouseUv.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = t;
    }
    let mouse = mouseUv * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouse;
    p += mouseDelta * exp(-dot(mouseDelta, mouseDelta) * 7.0) * 0.16;
    
    // Slow pan
    p = p + vec2<f32>(sin(t * 0.05) * 0.1, cos(t * 0.03) * 0.1);
    
    // Get Voronoi data
    let vo = voronoiCrystal(p, t * growthSpeed * (1.0 + bass * 0.18), crystalCount, irregularity);
    let voro = vo.m;
    let f1 = voro.x;
    let f2 = voro.y;
    let f3 = voro.z;
    let cellHash = voro.w;
    
    // Edge detection (facet boundaries)
    let edge = f2 - f1;
    let edgeMask = smoothstep(0.15, 0.0, edge);
    // Idea 1 — triple-junction vertices where three crystals meet.
    let triple = 1.0 - smoothstep(0.0, 0.07, (f2 - f1) + (f3 - f2));
    // Idea 3 — dislocation glide lines crossing selected grains.
    let dislocAngle = cellHash * TAU;
    let dislocAxis = vec2<f32>(cos(dislocAngle), sin(dislocAngle));
    let dislocCoord = dot(p * crystalCount, dislocAxis);
    let dislocation = smoothstep(0.08, 0.015, abs(fract(dislocCoord * 0.35 + t * (0.15 + bass * 0.12)) - 0.5));
    // Idea 4 — annealing front where facets briefly brighten/smooth.
    let annealBand = smoothstep(0.09, 0.01, abs(fract(length(p) * 0.85 - t * 0.12 + cellHash * 0.2) - 0.5));
    
    // Crystal depth simulation (cell age/size)
    let cellAge = fract(cellHash + t * 0.05);
    let depth = cellAge * 0.5 + 0.5;
    
    // Color palette - icy blues and whites with rainbow iridescence
    let baseHue = cellHash * 0.1 + 0.55; // Blue range
    let iridescence = sin(cellHash * 20.0 + t * 0.5) * (0.1 + mids * 0.06);
    
    var col = vec3<f32>(0.0);
    
    // Base crystal color
    let h = baseHue + iridescence;
    let crystalBase = vec3<f32>(
        0.5 + 0.5 * cos(6.28 * (h + 0.0)),
        0.5 + 0.5 * cos(6.28 * (h + 0.33)),
        0.5 + 0.5 * cos(6.28 * (h + 0.67))
    );

    // ── Idea 5: Michel–Lévy polarised-light tint (§12.2F phase/interference).
    // Seen between crossed polars a grain shows I(λ) = sin²(2θ)·sin²(π·Γ/λ): θ is the
    // grain axis against a slowly turning stage, Γ the retardation. The wedge-thin
    // grain edge (small f1) is first-order grey, the thick centre climbs the orders.
    let grainTheta = cellHash * 3.14159265;
    // ── Idea 6: polysynthetic twin lamellae. Stripes run in the grain-LOCAL frame
    // (anchored to the grain, unlike the world-anchored dislocation lines); every other
    // lamella of a twinned grain flips its axis θ → −θ, so extinction alternates.
    let lamCoord = vo.local.x * (7.0 + 9.0 * fract(cellHash * 37.0));
    let lamOdd = f32(i32(floor(lamCoord)) & 1);
    let twinned = step(0.5, fract(cellHash * 13.7));
    let thetaEff = grainTheta * (1.0 - 2.0 * lamOdd * twinned);
    let stageAngle = t * 0.12;
    let retardNm = 140.0 + 780.0 * f1;
    let polPhase = 3.14159265 * retardNm / vec3<f32>(650.0, 550.0, 450.0);
    let polS = sin(polPhase);
    let sin2 = sin(2.0 * (thetaEff - stageAngle));
    let polTint = vec3<f32>(sin2 * sin2) * (polS * polS);
    let lamLine = smoothstep(0.06, 0.0, abs(fract(lamCoord) - 0.5) - 0.42) * twinned;
    let crystalCol = max(mix(crystalBase, crystalBase * 0.45 + polTint * 1.25, 0.5) * (1.0 - 0.28 * lamLine), vec3<f32>(0.0));
    
    // Darker interior, brighter edges
    let interior = smoothstep(0.0, 0.3, f1);
    col = crystalCol * (0.3 + 0.7 * interior);
    
    // Add edge glow (facets)
    // ── Idea 7: misorientation-weighted grain boundaries. The second-nearest grain's hash
    // (promoted from the kernel) gives the axis difference: near-equal axes are faint
    // low-angle boundaries, large differences are bright high-angle ones.
    let misorient = abs(cellHash - vo.nb);
    let highAngle = smoothstep(0.05, 0.45, misorient);
    let edgeGlow = vec3<f32>(0.9, 0.95, 1.0) * edgeMask * glowIntensity * mix(0.4, 1.3, highAngle);
    col = col + edgeGlow;
    
    // Add depth shading
    col = col * (0.7 + 0.3 * depth);
    
    // Idea 2: piezoelectric charge flashes (bright flashes on random cells)
    let flash = step(0.98, fract(cellHash * 100.0 + t * 5.0)) * interior * (1.0 + treble);
    col += vec3<f32>(0.8, 0.9, 1.0) * flash * 2.0;
    
    // Internal structure (growth rings)
    let rings = sin(f1 * 20.0 + cellAge * 6.28);
    let ringMask = smoothstep(0.0, 0.1, rings) * smoothstep(0.3, 0.0, f1);
    col = col + crystalCol * ringMask * 0.3;
    col = col + vec3<f32>(1.0, 0.92, 0.65) * triple * glowIntensity * 0.7;
    
    // Specular highlight at seed center
    let specular = exp(-f1 * 10.0) * (0.5 + 0.5 * sin(t + cellHash * 10.0));
    col = col + vec3<f32>(1.0) * specular * (0.5 + treble * 0.3);
    
    // Frost effect at cell boundaries
    let frost = smoothstep(0.1, 0.0, edge) * smoothstep(0.0, 0.05, f1);
    col = mix(col, vec3<f32>(0.95, 0.98, 1.0), frost * 0.4);
    
    var clickCrack = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 1.7) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let ring = exp(-abs(radius - age * 0.24) * 76.0) * exp(-age * 1.7);
            let facets = pow(max(cos(atan2(delta.y, delta.x) * 8.0), 0.0), 12.0);
            clickCrack = max(clickCrack, ring * (0.7 + facets * 0.5));
        }
    }
    col += vec3<f32>(0.55, 0.9, 1.3) * clickCrack * (0.65 + treble * 0.3);
    col += vec3<f32>(0.95, 0.62, 0.25) * dislocation * 0.18 * (0.4 + mids * 0.5);
    col = mix(col, col * vec3<f32>(1.08, 1.03, 0.95), annealBand * 0.35);
    let coord = vec2<i32>(global_id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.9, clamp(0.02 + mids * 0.008, 0.0, 0.05));
    col = acesToneMap(max(col, vec3<f32>(0.0)) * 1.08);
    let reliefDepth = clamp(0.18 + edgeMask * 0.58 + specular * 0.18 + clickCrack * 0.06 + triple * 0.12 + annealBand * 0.08, 0.0, 1.0);
    let alpha = clamp(0.22 + edgeMask * 0.58 + specular * 0.15 + clickCrack * 0.15 + triple * 0.12 + dislocation * 0.08 + annealBand * 0.08, 0.0, 0.96);
    let outColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
