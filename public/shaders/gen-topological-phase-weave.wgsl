// ═══════════════════════════════════════════════════════════════════
//  Topological Phase Weave
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            topological-defects, phase-transition, euler-characteristic
//  Complexity: High
//  Created: 2026-05-31
//  Updated: 2026-06-07
//  Upgraded: 2026-09-27
//  Ideas: true line-integral convolution along the director; +1/2 comet / -1/2 trefoil glyphs; order parameter drives thread coherence
//  A packing: (ACES display RGBA)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ---- ACES TONE MAPPING ----
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Hash / Noise ═══
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    let p4 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ═══ Director Field (nematic angle) ═══
// Returns (angle, d angle/dx, d angle/dy). The gradient of atan2 is (-dy, dx)/r^2, so the
// LIC below gets a cheap local director (Taylor step) without re-running the 8 atan2s.
fn directorFieldG(p: vec2<f32>, time: f32, defectDensity: f32, mobility: f32, mousePos: vec2<f32>, mouseDown: f32) -> vec3<f32> {
    var angle = 0.0;
    var grad = vec2<f32>(0.0);
    let numDefects = 8;

    for (var i: i32 = 0; i < numDefects; i++) {
        let fi = f32(i);
        // Defect positions orbit and wander
        let phase = fi * 0.7853 + time * mobility * (0.3 + fi * 0.1);
        let radius = 0.3 + 0.2 * sin(time * 0.1 * (fi + 1.0));
        let defectPos = vec2<f32>(
            cos(phase) * radius + sin(time * 0.07 * (fi + 2.0)) * 0.15,
            sin(phase) * radius + cos(time * 0.09 * (fi + 1.5)) * 0.15
        ) * defectDensity;

        // Topological charge: alternate +1/2 and -1/2 defects
        let charge = select(-0.5, 0.5, i % 2 == 0);

        let dp = p - defectPos;
        let defectAngle = atan2(dp.y, dp.x);
        angle += charge * defectAngle;
        grad += charge * vec2<f32>(-dp.y, dp.x) / max(dot(dp, dp), 1e-4);
    }

    // Mouse creates topological defect when down
    if (mouseDown > 0.5) {
        let mdp = p - mousePos;
        let mouseAngle = atan2(mdp.y, mdp.x);
        angle += 0.5 * mouseAngle;
        grad += 0.5 * vec2<f32>(-mdp.y, mdp.x) / max(dot(mdp, mdp), 1e-4);
    }

    // Add smooth background field from noise
    angle += noise(p * 2.0 + time * 0.05) * 0.5;

    return vec3<f32>(angle, grad);
}

// Scalar-angle form kept from the original layout.
fn directorField(p: vec2<f32>, time: f32, defectDensity: f32, mobility: f32, mousePos: vec2<f32>, mouseDown: f32) -> f32 {
    return directorFieldG(p, time, defectDensity, mobility, mousePos, mouseDown).x;
}

// IDEA 1: line-integral convolution. Integrates a noise texture along the streamline of the
// director (5 steps each way, triangle kernel). Each step's direction is jittered by
// (1 - cohere) so a disordered field smears into isotropic speckle (IDEA 3).
fn licConvolve(p: vec2<f32>, theta0: f32, g: vec2<f32>, cohere: f32, licScale: f32, time: f32) -> f32 {
    let ns = licScale * 3.0;
    let h = 0.9 / ns;
    let drift = vec2<f32>(time * 0.1, time * 0.07);
    var acc = noise(p * ns + drift);
    var wsum = 1.0;
    for (var s: i32 = 0; s < 2; s++) {
        let sgn = select(-1.0, 1.0, s == 1);
        var q = p;
        for (var k: i32 = 0; k < 5; k++) {
            let dth = clamp(dot(g, q - p), -1.4, 1.4);
            let jit = (hash21(q * ns * 1.7 + vec2<f32>(f32(k) * 3.1 + sgn, sgn)) - 0.5) * 3.1416 * (1.0 - cohere);
            let th = theta0 + dth + jit;
            q += vec2<f32>(cos(th), sin(th)) * h * sgn;
            let w = 1.0 - f32(k + 1) / 6.0;
            acc += noise(q * ns + drift) * w;
            wsum += w;
        }
    }
    return acc / wsum;
}

// ═══ Defect proximity (singularity detector) ═══
struct DefectInfo {
    minDist: f32,
    charge: f32,
    totalCharge: f32,
    eulerChar: f32,
    rel: vec2<f32>,
};

fn defectProximity(p: vec2<f32>, time: f32, defectDensity: f32, mobility: f32, mousePos: vec2<f32>, mouseDown: f32) -> DefectInfo {
    var minDist = 100.0;
    var charge = 0.0;
    var totalCharge = 0.0;
    var rel = vec2<f32>(0.0);
    let numDefects = 8;

    for (var i: i32 = 0; i < numDefects; i++) {
        let fi = f32(i);
        let phase = fi * 0.7853 + time * mobility * (0.3 + fi * 0.1);
        let radius = 0.3 + 0.2 * sin(time * 0.1 * (fi + 1.0));
        let defectPos = vec2<f32>(
            cos(phase) * radius + sin(time * 0.07 * (fi + 2.0)) * 0.15,
            sin(phase) * radius + cos(time * 0.09 * (fi + 1.5)) * 0.15
        ) * defectDensity;

        let dist = length(p - defectPos);
        if (dist < minDist) {
            minDist = dist;
            rel = p - defectPos;
            charge = select(-0.5, 0.5, i % 2 == 0);
        }
        totalCharge += select(-0.5, 0.5, i % 2 == 0);
    }

    // Mouse defect contributes +1/2 charge
    if (mouseDown > 0.5) {
        let mouseDist = length(p - mousePos);
        if (mouseDist < minDist) {
            minDist = mouseDist;
            rel = p - mousePos;
            charge = 0.5;
        }
        totalCharge += 0.5;
    }

    // Euler characteristic: chi = 2 * totalCharge (for nematic defects)
    // Torus: chi = 0, Sphere: chi = 2
    let eulerChar = totalCharge * 2.0;

    return DefectInfo(minDist, charge, totalCharge, eulerChar, rel);
}

// ═══ Iridescent color mapping (oil-slick) ═══
fn iridescent(angle: f32, proximity: f32, time: f32) -> vec3<f32> {
    let t = angle * 0.3183 + time * 0.05; // normalize angle to [0,1]-ish range
    let film = proximity * 6.0 + t;

    // Thin-film interference colors
    let r = 0.5 + 0.5 * cos(6.2832 * (film + 0.0));
    let g = 0.5 + 0.5 * cos(6.2832 * (film + 0.33));
    let b = 0.5 + 0.5 * cos(6.2832 * (film + 0.67));

    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Audio input
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let defectDensity = mix(0.5, 2.0, u.zoom_params.x);     // Bass increases density
    let mobility = mix(0.2, 1.5, u.zoom_params.y);           // Mids control mobility
    let perturbation = mix(0.0, 1.0, u.zoom_params.z);       // Treble perturbation
    let colorSaturation = mix(0.3, 1.5, u.zoom_params.w);

    // Mouse: creates topological defect
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Stateless: HEAD's extraBuffer[0] "prevBass" was the raw uploaded bass (smoothing was a no-op
    // and thread (0,0) raced the audio slot), so the effective value was always bass itself.
    let smoothBass = bass;

    // Phase transition order parameter: 0 = disordered, 1 = ordered
    let orderParam = smoothstep(0.2, 0.8, smoothBass);

    // Aspect ratio
    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // Audio-modulated parameters
    let dynDensity = defectDensity * (1.0 + smoothBass * 0.5);
    let dynMobility = mobility * (1.0 + mids * 0.4);
    let dynPerturb = perturbation + treble * 0.3;

    // Mouse influence position in normalized space
    let mp = (mousePos - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // ═══ DIRECTOR FIELD COMPUTATION ═══
    let dfg = directorFieldG(p, time, dynDensity, dynMobility, mp, mouseDown);
    let angle = dfg.x;

    // Add high-frequency treble perturbation
    let perturbAngle = angle + noise(p * 10.0 + time * 2.0) * dynPerturb * 0.5;

    // Mouse pins the local field
    let mouseAttract = exp(-length(p - mp) * 4.0) * 0.8;
    let finalAngle = mix(perturbAngle, atan2(p.y - mp.y, p.x - mp.x), mouseAttract);

    // ═══ DEFECT VISUALIZATION ═══
    let defect = defectProximity(p, time, dynDensity, dynMobility, mp, mouseDown);
    let defectDist = defect.minDist;
    let defectCharge = defect.charge;
    let totalCharge = defect.totalCharge;
    let eulerChar = defect.eulerChar;

    // ═══ FIELD VISUALIZATION ═══
    // Director vector
    let director = vec2<f32>(cos(finalAngle), sin(finalAngle));

    // IDEA 3: order parameter -> director coherence. Autonomous breathing domains keep it
    // visible at audio = 0; bass (orderParam), the mouse pin and distance from cores raise it.
    let domain = noise(p * 1.3 + vec2<f32>(time * 0.03, -time * 0.02));
    let breath = 0.5 + 0.5 * sin(time * 0.2 + domain * 5.0);
    let autoOrder = 0.15 + 0.7 * smoothstep(0.25, 0.75, breath);
    var cohere = mix(autoOrder, 1.0, orderParam);
    cohere = max(cohere, mouseAttract);
    cohere *= mix(0.55, 1.0, smoothstep(0.0, 0.3, defectDist));
    cohere = clamp(cohere, 0.0, 1.0);

    // IDEA 1: true LIC along the streamline (Taylor director from the analytic gradient)
    let licScale = 8.0 + dynPerturb * 4.0;
    let mrel = p - mp;
    let gPin = vec2<f32>(-mrel.y, mrel.x) / max(dot(mrel, mrel), 1e-4);
    let gEff = mix(dfg.yz, gPin, mouseAttract);
    let lic = licConvolve(p, finalAngle, gEff, cohere, licScale, time);
    let fieldVis = clamp(0.5 + (lic - 0.5) * mix(2.2, 3.4, cohere), 0.0, 1.0);

    // Singularity glow
    let singularityGlow = exp(-defectDist * 15.0) * 1.5;

    // Defect type coloring: +1/2 warm (comet), -1/2 cool (trefoil)
    let positiveCol = vec3<f32>(1.0, 0.6, 0.2); // warm amber
    let negativeCol = vec3<f32>(0.2, 0.5, 1.0); // cool blue
    let defectCol = mix(negativeCol, positiveCol, step(0.0, defectCharge)) * singularityGlow;

    // ═══ COLOR MAPPING ═══
    // Iridescent base from director angle
    let iridescentBase = iridescent(finalAngle, defectDist, time);

    // Brush-stroke pattern from field
    let brushHalf = mix(0.3, 0.16, cohere);   // crisp threads when ordered, soft speckle when not
    let brushIntensity = smoothstep(0.5 - brushHalf, 0.5 + brushHalf, fieldVis);

    // Phase transition color shift:
    // Disordered (low bass) = warm colors (high entropy)
    // Ordered (high bass) = cool crystal colors
    let disorderedCol = vec3<f32>(1.0, 0.35, 0.1);  // warm amber-red
    let orderedCol = vec3<f32>(0.2, 0.7, 1.0);      // cool cyan-crystal
    let phaseCol = mix(disorderedCol, orderedCol, orderParam);

    // Compose final color with phase transition influence
    var col = iridescentBase * brushIntensity * colorSaturation;
    col = mix(col, col * phaseCol * 2.0, orderParam * 0.6 + 0.2);

    // Add defect singularity highlights
    col += defectCol;

    // Nematic order parameter visualization: darker near defect cores
    let localOrder = smoothstep(0.0, 0.15, defectDist);
    col *= localOrder * 0.8 + 0.2;

    // IDEA 2: defect glyphs. Radial alignment cos^2(theta - phi) about the nearest core is one
    // wedge for a +1/2 (comet tail; theta-phi = c - phi/2) and three lobes for a -1/2 (trefoil;
    // theta-phi = c - 3phi/2). Warm comet, cool trefoil, drawn after the core darkening.
    let isPos = defectCharge > 0.0;
    let dphi = atan2(defect.rel.y, defect.rel.x);
    let radial = cos(angle - dphi);
    let radial2 = radial * radial;
    let glyphShape = select(pow(radial2, 5.0) * exp(-defectDist * 8.0) * (1.0 - smoothstep(0.2, 0.35, defectDist)),
                            pow(radial2, 6.0) * exp(-defectDist * 5.0) * (1.0 - smoothstep(0.3, 0.5, defectDist)),
                            isPos);
    let glyph = glyphShape * smoothstep(0.0, 0.04, defectDist);
    col += select(negativeCol, positiveCol, isPos) * glyph * (0.4 + 0.6 * colorSaturation) * (0.7 + 0.6 * fieldVis);

    // Background: very dark with subtle field texture
    let bgField = fieldVis * 0.08;
    col = max(col, vec3<f32>(bgField));

    // Audio pulse on defect regions
    col += defectCol * smoothBass * 0.4;

    // Euler characteristic visible as color change
    // Torus (chi=0): neutral, Sphere-like (chi>0): golden tint
    let eulerTint = vec3<f32>(1.0, 0.8, 0.3) * eulerChar * 0.25;
    col += eulerTint * brushIntensity;

    // Temporal feedback for trail persistence
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    col = mix(col, max(col, prev * 0.88), 0.3);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // ACES tone mapping
    col = acesToneMap(col * 1.1);

    // Semantic alpha
    let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(1.0 - localOrder, 0.0, 0.0, 0.0));
}
