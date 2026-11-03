// ═══════════════════════════════════════════════════════════════════
//  Crystalline Fracture v3
//  Category: generative
//  Features: audio-reactive, fracture-mechanics, stress-intensity,
//            crack-propagation, iridescence, subsurface-scatter, upgraded-rgba, aces-tone-map
//  Complexity: Very High
//  Upgraded: 2026-11-01
//  Ideas: Wallner-line fracture arcs (rib spacing from K); photoelastic isochromatic fringes (Irwin K/sqrt(2*pi*r) tip field); cleavage-plane alignment lowers toughness
//  A packing: ACES display RGBA (unchanged)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

// Value noise: bilinear-interpolated hash lattice
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

// 3-octave fbm for grain boundary structure
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var q = p;
    for (var i = 0; i < 3; i = i + 1) {
        v = v + amp * vnoise(q);
        q = q * 2.13 + vec2<f32>(7.7, 3.1);
        amp = amp * 0.5;
    }
    return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    
    // Persistent state strictly in extraBuffer[133..138] (single-writer)
    if (global_id.x == 0u && global_id.y == 0u) {
        var pos = extraBuffer[133];
        var vel = extraBuffer[134];
        let goal = u.zoom_config.w; // held-pointer response
        let dt = 0.016;
        let force = (goal - pos) * 200.0 - vel * 15.0; // Bounded spring
        vel = vel + force * dt;
        pos = clamp(pos + vel * dt, 0.0, 1.0);
        extraBuffer[133] = pos;
        extraBuffer[134] = vel;
    }
    
    let heldPointer = extraBuffer[133];
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;

    // truthful three-band audio + bins
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let binAvg = (plasmaBuffer[0].x + plasmaBuffer[1].x + plasmaBuffer[2].x) * 0.33;

    let mouse = u.zoom_config.yz;

    // Exact textureLoad from dataTextureC
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Sliders (JSON contract: cells / glow / fracture / chromatic) ──
    let cellCount = mix(3.0, 15.0, u.zoom_params.x) * (1.0 + depth * 0.5);
    let edgeGlow = u.zoom_params.y;
    let fractureAmt = u.zoom_params.z;
    let chromatic = u.zoom_params.w * 0.02;

    let aspect = res.x / res.y;
    let p = uv * vec2<f32>(aspect, 1.0) * cellCount;
    let cellId = floor(p);
    let cellUV = fract(p);

    let grainUV = uv * vec2<f32>(aspect, 1.0) * (2.0 + cellCount * 0.35);
    let grain = fbm(grainUV);

    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseField = exp(-mouseDist * mouseDist * 20.0) * heldPointer;
    let mouseStress = smoothstep(0.15, 0.0, mouseDist) * heldPointer * 4.0;
    
    var stress = bass * 2.0 + mouseStress + mouseField * 2.0 + prev.r * 0.3;

    // capped click fronts
    let clickCount = min(u32(u.config.y), 10u);
    var ringStress = 0.0;
    for (var i = 0u; i < clickCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 4.0) {
            let rd = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let waveFront = age * 0.35;
            let band = exp(-abs(rd - waveFront) * 24.0);
            ringStress = ringStress + band * exp(-age * 1.2);
        }
    }
    stress = stress + ringStress * (1.0 + fractureAmt * 2.0);

    let catastrophic = step(0.8, treble) * 2.0;
    stress = stress + catastrophic;
    
    let connectivity = smoothstep(0.3, 0.7, prev.g);
    stress = stress + connectivity * 0.3;

    var minDist = 1e9;
    var secondMinDist = 1e9;
    var nearestId = vec2<f32>(0.0);
    var nearestSeed = vec2<f32>(0.0);
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let nid = cellId + vec2<f32>(f32(x), f32(y));
            let center = hash22(nid + vec2<f32>(time * 0.01 * fractureAmt, 0.0)) + vec2<f32>(f32(x), f32(y));
            let d = length(cellUV - center);
            if (d < minDist) {
                secondMinDist = minDist;
                minDist = d;
                nearestId = nid;
                nearestSeed = center;
            } else if (d < secondMinDist) {
                secondMinDist = d;
            }
        }
    }

    // Residual (thermal) stress: a crystal under load is never stress-free. HEAD's stress was
    // 0 without audio/pointer, so K never reached toughness and nothing ever cracked at rest.
    let cellRand = hash21(nearestId + vec2<f32>(7.3, 2.9));
    stress = stress + (0.12 + 0.4 * fractureAmt) * (0.6 + 0.8 * cellRand);

    // ── Idea 3: cleavage-plane alignment ───────────────────────────────
    // Each grain has a cleavage plane; it parts easiest when the load (pointer point-load) pulls
    // across it. alignment = cos(2*(plane - load)), toughness drops up to 35 % when aligned.
    let loadDir = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let cleavageAng = hash21(nearestId + vec2<f32>(3.1, 9.7)) * 3.14159265;
    let alignment = cos(2.0 * (cleavageAng - atan2(loadDir.y, loadDir.x)));
    let cleavage = 1.0 - 0.35 * (0.5 + 0.5 * alignment);

    let toughness = (0.4 + mids * 0.6) * (0.55 + grain * 0.9) * cleavage;
    let edgeDist = secondMinDist - minDist;
    let edge = smoothstep(0.05, 0.0, edgeDist);

    let crackSpeed = 0.1 + bass * 0.2;
    let crackLength = hash21(nearestId) * 2.0 + time * crackSpeed * (0.2 + fractureAmt * 1.2);
    let K = stress * sqrt(max(crackLength, 0.0)) * (0.7 + grain * 0.6);
    let crack = step(toughness, K);
    let branch = step(toughness * 1.3, K) * hash21(nearestId + vec2<f32>(1.0, 0.0));
    let crackDensity = crack + branch * 0.5;

    let tip = smoothstep(0.015, 0.0, minDist) * crack * (1.0 - branch);

    let hackle = sin(dot(cellUV, vec2<f32>(12.0, 5.0)) + hash21(nearestId) * 6.28) * 0.5 + 0.5;
    let hackleMask = smoothstep(0.45, 0.55, hackle) * edge * crackDensity;

    let hackleDir = atan2(cellUV.y - 0.5, cellUV.x - 0.5);
    let hackleRidge = sin(hackleDir * 6.0 + hash21(nearestId) * 6.28) * 0.5 + 0.5;
    let hackleMask2 = smoothstep(0.4, 0.6, hackleRidge) * edge * crackDensity * 0.5;

    let film = sin(length(cellUV - 0.5) * 25.0 - time * 1.5 + depth * 3.14) * 0.5 + 0.5;
    let irid = mix(vec3<f32>(0.9, 0.2, 0.2), vec3<f32>(0.2, 0.8, 0.9), film) * edge * crackDensity;

    let refraction = sin(minDist * 20.0 + time * 0.5) * smoothstep(0.3, 0.0, edgeDist) * 0.12 * fractureAmt;

    // ── Idea 1: Wallner lines ──────────────────────────────────────────
    // Stress waves reflected off the free surface ripple a running crack front, leaving
    // arcs on the fracture face centred on the crack origin (a point outside the grain, on
    // the side it came from). Rib spacing tightens with K (faster front, higher frequency).
    let originDir = vec2<f32>(cos(cellRand * 6.2831853), sin(cellRand * 6.2831853));
    let wallnerR = length(cellUV - (nearestSeed + originDir * 0.9));
    let wallnerPhase = wallnerR * (14.0 + min(K, 4.0) * 6.0) - time * 0.4;
    let wallner = smoothstep(0.55, 0.9, 0.5 + 0.5 * sin(wallnerPhase)) * smoothstep(0.0, 0.2, edgeDist) * crack;

    // ── Idea 2: photoelastic isochromatic fringes ──────────────────────
    // Birefringent crystal under load shows fringes where the Irwin tip field
    // sigma = K / sqrt(2*pi*r) crosses integer orders. Reuse the file's red/cyan film tints.
    let sigmaTip = K / sqrt(6.2831853 * max(minDist, 0.03));
    let fringe = 0.5 + 0.5 * cos(sigmaTip * 4.0);
    let fringeMask = crack * smoothstep(0.6, 0.1, minDist) * (1.0 - smoothstep(0.1, 0.25, edgeDist) * 0.5);
    let photoelastic = mix(vec3<f32>(0.9, 0.2, 0.2), vec3<f32>(0.2, 0.8, 0.9), fringe) * fringe * fringeMask * 0.35;

    let sss = smoothstep(0.25, 0.0, edgeDist) * 0.25 * (1.0 + mids);

    let ca = chromatic * (1.0 + treble) * edgeDist;
    let rEdge = smoothstep(0.05 + ca, 0.0, edgeDist);
    let bEdge = smoothstep(0.05 - ca, 0.0, edgeDist);
    let chromaEdge = vec3<f32>(rEdge, edge, bEdge) * edgeGlow * (1.0 + treble);

    // Continuous geometry using audio bins
    let cellHue = hash21(nearestId + vec2<f32>(time * 0.005, 0.0));
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let h = abs(fract(vec3<f32>(cellHue) + k) * 6.0 - vec3<f32>(3.0));
    let cellColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)) * (0.3 + mids * 0.2 + binAvg * 0.1) * (1.0 - depth * 0.3);

    let bloom = tip * (0.5 + edgeGlow * 5.0) * (1.0 + bass);
    var color = cellColor + chromaEdge + irid + vec3<f32>(sss) + vec3<f32>(refraction) + vec3<f32>(bloom);
    color = color + vec3<f32>(0.35, 0.3, 0.25) * hackleMask;
    color = color + vec3<f32>(0.3, 0.25, 0.2) * hackleMask2;
    color = color + vec3<f32>(0.32, 0.3, 0.26) * wallner * 0.3 + photoelastic;

    let caStr = 0.001 + chromatic * (0.5 + bass) + depth * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    color = acesToneMap(color * 1.1);

    // Semantic alpha
    let alpha = clamp(crackDensity * K * 0.5 + edge * 0.5 + bloom * 0.2 + sss + wallner * 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(color, alpha);

    // Write final display RGBA ONLY to dataTextureA (and writeTexture)
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    
    // We can use writeDepthTexture if needed, but not dataTextureB.
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(edge * 0.5 + crackDensity * 0.3, 0.0, 0.0, 0.0));
}
