// ═══════════════════════════════════════════════════════════════════
//  Prismatic Quantum-Glass Chrysalis-Engine
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-08
//  Ideas: chrysalis chamber ribs; internal TIR caustics; helical emergence fissure; dichroic aurora backdrop; crack-junction sparks
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: Refraction Index, Plasma Intensity, Core Rotation Speed, Chromatic Dispersion

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  var q = abs(p);
  return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let q = abs(p);
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
    var p2 = q.xy;
    p2 = p2 - 2.0 * min(dot(k.xy, p2), 0.0) * k.xy;
    let d1 = p2 - vec2<f32>(clamp(p2.x, -k.z * h.x, k.z * h.x), h.x);
    let d2 = vec2<f32>(length(d1) * sign(d1.y), q.z - h.y);
    return min(max(d2.x, d2.y), 0.0) + length(max(d2, vec2<f32>(0.0)));
}

// 3D Voronoi / noise helper for cuts
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn voronoi3(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    var res = vec2<f32>(8.0);
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g - f + o;
                let d = dot(r, r);
                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return sqrt(res);
}

fn chrysalisSpace(p: vec3<f32>) -> vec3<f32> {
    let time = u.config.x;
    let rotationSpeed = u.zoom_params.z;
    let rotatedXY = rot(time * rotationSpeed * 0.5) * p.xy;
    let xyPosition = vec3<f32>(rotatedXY, p.z);
    let rotatedYZ = rot(time * rotationSpeed * 0.7) * xyPosition.yz;
    return vec3<f32>(xyPosition.x, rotatedYZ);
}

// Idea 1: transverse tapered rings occupy only the original crystal volume.
// They bridge Voronoi openings as nested metamorphic chamber ribs.
fn chamberRibDistance(pos: vec3<f32>) -> f32 {
    let spacing = 0.46;
    let ribCenter = clamp(round(pos.z / spacing), -3.0, 3.0) * spacing;
    let localZ = pos.z - ribCenter;
    let axialTaper = clamp(1.0 - abs(ribCenter) / 1.8, 0.0, 1.0);
    let ribRadius = 0.52 + axialTaper * 0.76;
    let ringDistance = abs(length(pos.xy) - ribRadius)
      - (0.035 + axialTaper * 0.018);
    let transverseSlice = abs(localZ) - 0.032;
    return max(ringDistance, transverseSlice);
}

fn map(p: vec3<f32>) -> f32 {
    let pos = chrysalisSpace(p);

    let d1 = sdOctahedron(pos, 2.0);
    let d2 = sdHexPrism(pos, vec2<f32>(1.5, 1.8));
    let baseChrysalis = max(d1, d2);

    // Preserve the original Voronoi-cut shell.
    let v = voronoi3(pos * 2.0);
    let crack = (v.y - v.x) * 0.5;
    let cutShell = max(baseChrysalis, -crack + 0.1);

    // The max confines every rib inside the octahedron/prism intersection;
    // min reveals those ribs only where the original Voronoi cuts open.
    let containedRibs = max(chamberRibDistance(pos), baseChrysalis + 0.01);

    return min(cutShell, containedRibs);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp(
      (x * (a * x + b)) / (x * (c * x + d) + e),
      vec3<f32>(0.0),
      vec3<f32>(1.0)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let dims = vec2<f32>(u.config.zw);
    if (coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) { return; }

    // Rescue: screen y grows downward; flip so the scene is upright.
    var uv = (vec2<f32>(coord) - 0.5 * dims) / min(dims.x, dims.y);
    uv.y = -uv.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    // Parameters
    let ior = clamp(u.zoom_params.x, 1.0, 2.5);
    let plasmaIntensity = clamp(u.zoom_params.y, 0.0, 3.0);
    let rotationSpeed = clamp(u.zoom_params.z, 0.0, 2.0);
    let chromDisp = clamp(u.zoom_params.w, 0.0, 1.0);

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    // Rescue: the old pitch was mouse.y * PI, so the idle cursor (0.5) parked
    // the camera on the pole where cross(cw, up) = 0 and every ray was NaN
    // (fully black). Centre both axes on 0.5 and keep pitch off the pole;
    // mouse y is flipped to match the upright uv.
    let orbitYZ = rot((0.5 - mouse.y) * 1.3) * ro.yz;
    ro = vec3<f32>(ro.x, orbitYZ);
    let orbitXZ = rot((mouse.x - 0.5) * 6.2831853) * ro.xz;
    ro = vec3<f32>(orbitXZ.x, ro.y, orbitXZ.y);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t = 0.0;
    var hit = false;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    // Idea 4: dichroic aurora backdrop - slow curtains whose hue splits by
    // Chromatic Dispersion, so the "void of refracted auroral light" exists.
    let curtainX = rd.x * 3.0 + sin(rd.y * 4.0 + time * 0.2) * 0.6;
    let curtain = pow(0.5 + 0.5 * sin(curtainX * 2.5 + time * 0.15), 4.0)
      * smoothstep(-0.4, 0.5, rd.y) * (0.6 + audio.y * 0.3);
    let auroraHue = vec3<f32>(
      0.5 + 0.5 * sin(curtainX + chromDisp * 3.0),
      0.5 + 0.5 * sin(curtainX + 2.1),
      0.5 + 0.5 * sin(curtainX + 4.2 - chromDisp * 3.0));
    let bgCol = max(vec3<f32>(0.02, 0.0, 0.08) - length(uv) * 0.05, vec3<f32>(0.0))
      + auroraHue * vec3<f32>(0.25, 0.55, 0.6) * curtain;
    col = bgCol;
    var surfaceAlphaBg = 0.18 * curtain;
    var surfaceAlpha = clamp(surfaceAlphaBg, 0.0, 1.0);
    var sceneDepth = 1.0;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let localP = chrysalisSpace(p);

        // Refraction Index keeps its saved physical role by steering the
        // interior sample ray rather than remapping the saved value.
        let refractedRay = refract(rd, n, 1.0 / max(ior, 1.001));
        let internalP = p + refractedRay * (0.10 + chromDisp * 0.08);
        let plasmaDist = map(internalP);
        let plasmaGain = plasmaIntensity * (1.0 + audio.x * 0.25);
        let plasmaCol = vec3<f32>(1.0, 0.2, 0.8)
          * exp(-abs(plasmaDist) * 5.0) * plasmaGain * 0.45;
        // (0.45 / 0.6 trims: both glows saturate just under the shell and
        // the ACES output washed to white once the camera rescue made it visible.)
        let cyanCore = vec3<f32>(0.0, 0.8, 1.0)
          * exp(-abs(plasmaDist) * 10.0) * plasmaGain * 0.6;

        // Refraction / thin film
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let filmPhase = fresnel * (10.0 + chromDisp * 10.0)
          + time * rotationSpeed * 0.08 + audio.y * 0.15;
        let thinFilm = vec3<f32>(
           sin(filmPhase + chromDisp * 2.1) * 0.5 + 0.5,
           sin(filmPhase * 1.23) * 0.5 + 0.5,
           sin(filmPhase * 1.47 - chromDisp * 2.1) * 0.5 + 0.5
        ) * 0.5;

        let glass = mix(vec3<f32>(0.1, 0.1, 0.2), thinFilm, fresnel);
        let ribMask = exp(-abs(chamberRibDistance(localP)) * 34.0);
        let ribLight = vec3<f32>(0.24, 0.62, 0.78) * ribMask
          * (0.35 + fresnel * 0.65);

        // Idea 2: wavelength-separated caustic threads follow the interior
        // Voronoi cut lips and intensify at grazing, TIR-like angles.
        let internalLocal = chrysalisSpace(internalP);
        let interiorCells = voronoi3(internalLocal * 2.0);
        let interiorCrack = (interiorCells.y - interiorCells.x) * 0.5;
        let cutLip = exp(-abs(interiorCrack - 0.1) * 52.0);
        let grazing = pow(1.0 - abs(dot(refractedRay, n)), 2.0);
        let tirFocus = smoothstep(
          0.08,
          0.82,
          grazing * (0.55 + 0.45 * (ior - 1.0) / 1.5)
        );
        let causticPhase = dot(internalLocal, vec3<f32>(9.0, 13.0, 7.0))
          - time * (0.35 + rotationSpeed * 0.15) + audio.y * 0.4;
        let spectralOffset = chromDisp * 2.0943951;
        let causticThreads = vec3<f32>(
          pow(0.5 + 0.5 * sin(causticPhase + spectralOffset), 6.0),
          pow(0.5 + 0.5 * sin(causticPhase), 6.0),
          pow(0.5 + 0.5 * sin(causticPhase - spectralOffset), 6.0)
        ) * cutLip * tirFocus * (1.0 + audio.z * 0.4);

        // Idea 3: helical emergence fissure - a bright seam spiralling round the
        // chrysalis axis; bass widens it as if the shell were about to split.
        let helixAngle = atan2(localP.y, localP.x);
        let helixPhase = helixAngle - localP.z * 2.4 - time * 0.3;
        let helixDist = abs(sin(helixPhase * 0.5)) * length(localP.xy);
        let fissureWidth = 0.03 + audio.x * 0.03;
        let fissure = exp(-helixDist / fissureWidth) * smoothstep(1.9, 0.6, abs(localP.z));
        let fissureCol = vec3<f32>(1.0, 0.75, 0.35) * fissure * (2.0 + audio.x * 1.5);

        // Idea 5: crack-junction sparks - where three Voronoi cells meet on the
        // surface (F2-F1 tiny), hashed cells blink white on treble.
        let surfCells = voronoi3(localP * 2.0);
        let junction = exp(-(surfCells.y - surfCells.x) * 40.0);
        let blink = step(0.82, fract(hash3(floor(localP * 2.0)).x + time * 0.35));
        let sparks = vec3<f32>(0.9, 0.95, 1.0) * junction * blink * (0.6 + audio.z * 1.2);

        col = glass + plasmaCol + cyanCore + ribLight + causticThreads + fissureCol + sparks;
        surfaceAlpha = clamp(
          0.32 + fresnel * 0.38 + ribMask * 0.18 + cutLip * tirFocus * 0.22 + fissure * 0.25,
          0.0,
          1.0
        );
        sceneDepth = clamp(t / 20.0, 0.0, 1.0);
    }

    let displayColor = acesToneMap(max(col, vec3<f32>(0.0)));
    let display = vec4<f32>(displayColor, surfaceAlpha);
    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}
