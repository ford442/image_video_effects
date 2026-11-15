// ═══════════════════════════════════════════════════════════════════
//  Hybrid Cyber-Organic
//  Category: generative
//  Features: hybrid, circuit-patterns, organic-growth, neon-glow, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-10, 2026-11-15
//  Ideas: exact-C occupancy persist; photo-luma seed on growth; neighbour-driven wavefront growth (exact C at the 6 hex neighbours); solder-via pads at hex vertices, brighter at junctions
//  Rescue: growth/hue/pulse/chaos keyed on the true hex-centre id (HEAD used the rectangular lattice cell, so hexes were cut into rectangular blocks)
//  A packing: raw occupancy in A.r; ACES on writeTexture
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Tuning gains for the 2026-11-15 ideas (1.0 = shipped look).
const SPREAD_GAIN: f32 = 1.0;   // Idea 1: neighbour wavefront
const VIA_GAIN: f32 = 1.0;      // Idea 2: solder-via pads

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hexEdgeDist(p: vec2<f32>) -> f32 {
    var q = abs(p);
    return max(q.x * 0.5 + q.y * 0.866025, q.x);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// Occupancy (A.r of last frame, exact C load) at the pixel under hex-lattice point pN; 0 off-frame.
// Lattice-B centres sit exactly on uv x=0 / y=0 (and on x=1 / y=1 whenever aspect*gridSize is an integer), so a strict
// `uvN >= 0` / `uvN < 1` test flips per pixel on ~1e-7 rounding and striped the edge hexes. Test in pixel units with
// half a pixel of slack on BOTH sides and clamp the index: a centre on the frame edge is deterministically the edge
// pixel, and every interior load is unchanged.
fn nbrOcc(pN: vec2<f32>, gridSize: f32, aspect: f32, resolution: vec2<f32>) -> f32 {
    let pf = vec2<f32>(pN.x / (gridSize * aspect), pN.y / gridSize) * resolution;
    let inside = all(pf > vec2<f32>(-0.5)) && all(pf < resolution + vec2<f32>(0.5));
    let pixN = clamp(vec2<i32>(floor(pf)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    return select(0.0, textureLoad(dataTextureC, pixN, 0).r, inside);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let gridSize = mix(5.0, 25.0, u.zoom_params.x);
    let growthAmount = u.zoom_params.y;
    let glowStrength = mix(0.5, 3.0, u.zoom_params.z);
    let chaosFactor = u.zoom_params.w * 0.5;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let srcLuma = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let prev = textureLoad(dataTextureC, id, 0);

    let aspect = resolution.x / max(resolution.y, 0.001);
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    var p = uvCorrected * gridSize;

    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let fractA = fract(p / r) * r - h;
    let fractB = (fract((p / r) + 0.5) * r) - h;

    var localUV = vec2<f32>(0.0);
    if (dot(fractA, fractA) < dot(fractB, fractB)) {
        localUV = fractA;
    } else {
        localUV = fractB;
    }

    var q = abs(localUV);
    let distToCenter = max(q.x * 0.5 + q.y * 0.866025, q.x);
    let distToEdge = 0.5 - distToCenter;

    // ── Rescue 1: true hex-centre id ──
    // HEAD keyed everything on floor(p / r), the RECTANGULAR lattice cell: the two interleaved hex lattices then
    // share ids and a B-lattice hex straddles four of them. localUV already knows the nearest centre, so use it.
    // Lattice A centres sit at (i+.5, (j+.5)*1.732), B at (i, j*1.732): doubling x and halving y by 0.866 makes
    // every centre an integer pair (odd/odd for A, even/even for B). *0.5 keeps HEAD's noise frequency.
    let hexCentre = p - localUV;
    let hexId = round(vec2<f32>(hexCentre.x * 2.0, hexCentre.y / 0.8660254));
    let cellId = hexId * 0.5;

    // HEAD's own occupancy rule first (photo-luma seed + exact-C persistence).
    let growthNoise = fbm2(cellId * 0.5 + time * 0.1, 3);
    let seeded = growthNoise + growthAmount - 0.5 + srcLuma * 0.45;
    let growthLive = smoothstep(0.3, 0.7, seeded);
    let baseOcc = max(growthLive, prev.r * mix(0.86, 0.97, growthAmount));
    let lineThickness = mix(0.02, 0.08, growthAmount) * (1.0 + chaosFactor * hash12(cellId));

    // Vertex-pad geometry (Idea 2 below) — needed here to know whether this pixel can show a via.
    let qv = abs(localUV);
    let dV1sq = dot(qv - vec2<f32>(0.5, 0.2886751), qv - vec2<f32>(0.5, 0.2886751));
    let dV2sq = dot(qv - vec2<f32>(0.0, 0.5773503), qv - vec2<f32>(0.0, 0.5773503));
    // Capped: lineThickness grows with the growth/chaos sliders, and an uncapped pad (0.255 at 0.4,1,1,1) swallows the outline.
    // The cap (0.14) sits above the saved-default maximum (0.13), so the default look is unchanged.
    let viaR = min(lineThickness * 2.0 + 0.015, 0.14);
    let onPad = min(dV1sq, dV2sq) < viaR * viaR;

    // ── Idea 1: neighbour-driven wavefront growth (native; exact C at the 6 hex neighbours) ──
    // C already holds every hex's occupancy at every pixel, so a neighbour's state is one exact load at its centre
    // pixel. An unlit cell catches from a lit neighbour when its slow per-cell gate is open; the 0.72 per-hop falloff
    // plus HEAD's own decay keeps the front to ~2 hexes, so the lattice never floods.
    // The loads only matter where spread can beat baseOcc (spread <= 0.72) or where a via pad is drawn, so every other
    // pixel skips them and the gate hash (output is bit-identical to computing everything unconditionally).
    // neighbours: 0 (+1,0)  1 (-1,0)  2 (+.5,+.866)  3 (-.5,+.866)  4 (+.5,-.866)  5 (-.5,-.866)
    var n0 = 0.0; var n1 = 0.0; var n2 = 0.0; var n3 = 0.0; var n4 = 0.0; var n5 = 0.0;
    var spread = 0.0;
    if (baseOcc < 0.72 || onPad) {
        n0 = nbrOcc(hexCentre + vec2<f32>(1.0, 0.0), gridSize, aspect, resolution);
        n1 = nbrOcc(hexCentre + vec2<f32>(-1.0, 0.0), gridSize, aspect, resolution);
        n2 = nbrOcc(hexCentre + vec2<f32>(0.5, 0.8660254), gridSize, aspect, resolution);
        n3 = nbrOcc(hexCentre + vec2<f32>(-0.5, 0.8660254), gridSize, aspect, resolution);
        n4 = nbrOcc(hexCentre + vec2<f32>(0.5, -0.8660254), gridSize, aspect, resolution);
        n5 = nbrOcc(hexCentre + vec2<f32>(-0.5, -0.8660254), gridSize, aspect, resolution);
        let nbrMax = max(max(max(n0, n1), max(n2, n3)), max(n4, n5));
        // The gate re-rolls every 0.71 s tick; crossfading gate(tick) -> gate(tick+1) over the last 30 % of the tick
        // stops fringe cells' outlines popping on in a single frame.
        let gateT = time * 1.4;
        let gateTick = floor(gateT);
        let gateThr = 1.0 - mix(0.25, 0.6, growthAmount);
        let gateF = smoothstep(0.7, 1.0, gateT - gateTick);   // uniform across the dispatch: the next tick's hash is only paid in the fade
        var gate = step(gateThr, hash12(hexId * 1.37 + vec2<f32>(gateTick * 0.61, gateTick * 0.17)));
        if (gateF > 0.0) {
            gate = mix(gate, step(gateThr, hash12(hexId * 1.37 + vec2<f32>((gateTick + 1.0) * 0.61, (gateTick + 1.0) * 0.17))), gateF);
        }
        spread = nbrMax * 0.72 * gate * SPREAD_GAIN;
    }
    let occupy = max(baseOcc, spread);
    let growthPattern = occupy;

    let circuitActive = growthPattern > 0.5;
    let isHexLine = 1.0 - smoothstep(0.0, lineThickness, distToEdge);

    let tendrilNoise = fbm2(uv * gridSize * 2.0 + time * 0.2, 4);
    let tendrils = smoothstep(0.4, 0.6, tendrilNoise) * growthPattern;

    let hue = cellId.x * 0.1 + cellId.y * 0.05 + time * 0.1;
    let baseColor = palette(hue,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.0, 0.33, 0.67)
    );

    let cyberColor = mix(
        vec3<f32>(0.0, 0.8, 1.0),
        vec3<f32>(0.2, 1.0, 0.3),
        growthPattern
    );

    var color = vec3<f32>(0.02, 0.03, 0.05);

    if (isHexLine > 0.0 && circuitActive) {
        color = mix(color, cyberColor * glowStrength, isHexLine);
    }

    color += vec3<f32>(0.1, 0.9, 0.4) * tendrils * growthAmount;

    let glowRadius = lineThickness * 3.0;
    let glowAmt = (1.0 - smoothstep(0.0, glowRadius, distToEdge)) * growthPattern;
    color += baseColor * glowAmt * glowStrength * 0.5;

    let pulse = sin(time * 3.0 + cellId.x * 0.5 + cellId.y * 0.3 + bass * 2.0) * 0.5 + 0.5;
    color += cyberColor * pulse * isHexLine * 0.3;

    // ── Idea 2: solder-via pads at hex vertices (native PCB node) ──
    // The two distinct vertices of the folded hex are (0.5, 0.2887) and (0, 0.5774). A round pad with a drilled hole
    // sits on each; it is lit only on occupied cells (so a half-grown corner shows a partial pad, like the outline)
    // and brightens as the 3 hexes meeting at the vertex fill in (junction).
    var via = 0.0;
    if (onPad) {
        let viaD = sqrt(min(dV1sq, dV2sq));
        let sxp = select(0.0, 1.0, localUV.x > 0.0);
        let syp = select(0.0, 1.0, localUV.y > 0.0);
        // neighbours sharing this vertex: vertex1 -> (+-1,0) & (+-.5,+-.866); vertex2 -> (+-.5,+-.866) both
        let nSideX = select(n1, n0, sxp > 0.5);
        let nDiag = select(select(n5, n4, sxp > 0.5), select(n3, n2, sxp > 0.5), syp > 0.5);
        let nTopA = select(n4, n2, syp > 0.5);
        let nTopB = select(n5, n3, syp > 0.5);
        let isV1 = dV1sq < dV2sq;
        let nShareA = select(nTopA, nSideX, isV1);
        let nShareB = select(nTopB, nDiag, isV1);
        let junction = (smoothstep(0.4, 0.6, occupy) + smoothstep(0.4, 0.6, nShareA) + smoothstep(0.4, 0.6, nShareB)) / 3.0;
        let padDisc = 1.0 - smoothstep(viaR * 0.62, viaR, viaD);
        let drill = 1.0 - smoothstep(viaR * 0.22, viaR * 0.34, viaD);
        via = padDisc * (1.0 - drill * junction) * smoothstep(0.4, 0.6, occupy) * VIA_GAIN;
        let viaColor = mix(cyberColor, vec3<f32>(0.85, 1.0, 0.95), 0.55) * glowStrength * (0.55 + 0.9 * junction);
        color += viaColor * via;
    }

    let activity = isHexLine + tendrils + glowAmt * 0.5 + via * 0.5;
    let alpha = mix(0.3, 1.0, activity);

    textureStore(dataTextureA, id, vec4<f32>(occupy, tendrils, glowAmt, 1.0));
    textureStore(writeTexture, id, vec4<f32>(acesToneMap(color), alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(growthPattern, 0.0, 0.0, 0.0));
}
