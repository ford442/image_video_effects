// ═══════════════════════════════════════════════════════════════════
//  Neon Cyber Mandala
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: glow-discharge tube anatomy on every ring (cathode negative glow, Faraday dark space, drifting positive-column striations, Ne/Ar-Hg emission lines); click ionization strike fronts that re-ignite rings with recombination afterglow, mouse-held raises discharge current
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Glow Intensity, .y = Rotation Speed, .z = Zoom Scale, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749895;
const GOLDEN_ANGLE: f32 = 2.399963229728653;

// ─── ACES Filmic Tone Mapping ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Noise/hash functions
fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// ─── Glow-discharge tube anatomy ───
// A cold-cathode neon tube is not uniformly lit: next to the cathode sits a
// thin bright negative glow, then the Faraday dark space, then the positive
// column, which at low current breaks into travelling striations whose
// spacing is set by the electron energy-relaxation length. Higher current
// smears the striations into a continuous column. `arc` is the angle measured
// from the tube's cathode (0..TAU), `circ` the tube circumference.
fn dischargeProfile(arc: f32, circ: f32, time: f32, drift: f32, current: f32) -> f32 {
    let arcLen = arc / TAU * circ;
    let negGlow = exp(-pow((arcLen - 0.012) / 0.006, 2.0)) * 1.6;
    let faraday = smoothstep(0.02, 0.06, arcLen);
    let striLen = 0.035;
    let nStri = max(floor(circ / striLen), 3.0);
    let wave = 0.5 + 0.5 * sin(arc * nStri - time * drift);
    let contrast = clamp(0.85 / current, 0.15, 0.85);
    let column = (1.0 - contrast) + contrast * pow(wave, 3.0) * 3.2;
    return negGlow + faraday * column;
}

// Gas emission tint: neon (585–640 nm red-orange lines) vs argon + mercury
// vapour (436 nm blue / 546 nm green) fills, alternating per tube.
fn gasLine(i: i32) -> vec3<f32> {
    return select(vec3<f32>(0.30, 0.52, 1.0), vec3<f32>(1.0, 0.32, 0.07), i % 2 == 0);
}

// Rainbow palette
fn rainbow(t: f32) -> vec3<f32> {
    return vec3<f32>(
        0.5 + 0.5 * cos(TAU * (t + 0.0)),
        0.5 + 0.5 * cos(TAU * (t + 0.33)),
        0.5 + 0.5 * cos(TAU * (t + 0.67))
    );
}

fn neonRainbow(t: f32) -> vec3<f32> {
    return vec3<f32>(
        0.5 + 0.5 * cos(TAU * t - 0.0),
        0.5 + 0.5 * cos(TAU * t - 2.094),
        0.5 + 0.5 * cos(TAU * t - 4.189)
    );
}

// SDF for regular polygon
fn sdPolygon(p: vec2<f32>, r: f32, n: i32) -> f32 {
    let angle = atan2(p.y, p.x);
    let sector = TAU / f32(n);
    let a = abs(fract(angle / sector) - 0.5) * sector;
    let polyP = vec2<f32>(cos(a), abs(sin(a))) * length(p);
    let edge = vec2<f32>(cos(sector * 0.5), sin(sector * 0.5)) * r;
    let d = polyP - edge * clamp(dot(polyP, edge) / dot(edge, edge), 0.0, 1.0);
    return length(d) * sign(polyP.x * edge.y - polyP.y * edge.x);
}

// Simple star SDF using rays
fn starRays(p: vec2<f32>, r: f32, rays: i32, innerR: f32) -> f32 {
    let angle = atan2(p.y, p.x);
    let d = length(p);
    let sector = TAU / f32(rays);
    let folded = abs(fract(angle / sector) - 0.5) * sector;
    
    let starR = mix(r * innerR, r, folded / (sector * 0.5));
    return d - starR;
}

// Ring with pattern
fn patternedRing(p: vec2<f32>, innerR: f32, outerR: f32, pattern: i32, time: f32, hue: f32) -> vec3<f32> {
    let d = length(p);
    let ringDist = abs(d - (innerR + outerR) * 0.5) - (outerR - innerR) * 0.5;
    let ringMask = smoothstep(0.008, 0.0, ringDist);
    
    if (ringMask < 0.001) {
        return vec3<f32>(0.0);
    }
    
    let angle = atan2(p.y, p.x);
    
    var patternVal: f32 = 0.0;
    
    // Different patterns for each ring
    if (pattern == 0) {
        // Dots
        let dotFreq = 24.0;
        let dotAngle = fract(angle / TAU * dotFreq) - 0.5;
        let dotDist = length(vec2<f32>(dotAngle * TAU / dotFreq * d, d - (innerR + outerR) * 0.5));
        patternVal = smoothstep(0.015, 0.0, dotDist);
    } else if (pattern == 1) {
        // Lines radiating
        let lineFreq = 18.0;
        let lineAngle = abs(fract(angle / TAU * lineFreq) - 0.5) * 2.0;
        patternVal = smoothstep(0.02, 0.0, lineAngle) * 0.8;
    } else if (pattern == 2) {
        // Zigzag
        let zigzag = sin(angle * 12.0 + time * 2.0) * 0.5 + 0.5;
        let zd = abs(d - mix(innerR, outerR, zigzag));
        patternVal = smoothstep(0.006, 0.0, zd);
    } else if (pattern == 3) {
        // Wave
        let wave = sin(angle * 16.0 + time * 3.0) * (outerR - innerR) * 0.25;
        let wd = abs(d - (innerR + outerR) * 0.5 - wave);
        patternVal = smoothstep(0.008, 0.0, wd);
    } else {
        // Diamonds
        let dFreq = 20.0;
        let da = fract(angle / TAU * dFreq);
        let dd = fract(d / (outerR - innerR) * 4.0);
        let diamond = abs(da - 0.5) + abs(dd - 0.5);
        patternVal = smoothstep(0.35, 0.3, diamond);
    }
    
    let col = neonRainbow(hue + angle / TAU) * patternVal;
    return col * ringMask;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    
    let time = u.config.x;
    let mousePos = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x, res.y) / min(res.x, res.y);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Discharge current: mouse-held closes the ballast, bass surges the supply.
    let current = 1.0 + held * 0.9 + bass * 0.4;
    let stripeDrift = 2.0 + speed * 6.0 + mids * 2.0;

    // ─── Ionization strike fronts from click ripples ───
    // Each click fires a breakdown avalanche expanding from the click point;
    // tubes behind the front re-ignite and then fade with the ion
    // recombination time.
    var strikeFront = 0.0;
    var reignite = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rpl = u.ripples[ri];
        let age = time - rpl.z;
        if (age >= 0.0 && age < 3.0) {
            let rpos = (rpl.xy - 0.5) * res / min(res.x, res.y);
            let dist = length(uv - rpos);
            let frontR = age * 0.9;
            let fd = dist - frontR;
            strikeFront += exp(-fd * fd * 900.0) * exp(-age * 1.4);
            let sincePass = age - dist / 0.9;
            if (sincePass > 0.0) {
                reignite += exp(-sincePass * 2.8) * exp(-age * 0.6);
            }
        }
    }
    let ignition = 1.0 + reignite * 2.2;

    let audioSpeed = speed * (0.9 + bass * 0.5);
    let audioIntensity = intensity * (0.85 + treble * 0.6);
    let audioColor = colorShift + mids * 0.2;
    
    // Mouse controls
    let mouseRot = atan2(mousePos.y, mousePos.x);
    
    // ─── Golden Ratio Enrichment ───
    // Fibonacci petal counts: 5, 8, 13, 21 mapped via phi
    let nPetals = i32(mix(5.0, 21.0, clamp(intensity * PHI, 0.0, 1.0)));
    let fibPetals = array<i32, 4>(5, 8, 13, 21);
    
    // Zoom: mouse Y controls zoom into center
    let zoomAmount = (mousePos.y + 0.5) * 0.5;
    let zoom = mix(0.4, 2.5, zoomAmount);
    let p = uv * (zoom * (0.5 + scale));
    
    // ─── Mouse Warp of Symmetry Field ───
    let mouseWarp = mousePos * 0.15 * (1.0 + bass * 0.5);
    let warpedP = p + vec2<f32>(
        sin(p.y * PHI * 3.0 + time) * mouseWarp.x,
        cos(p.x * PHI * 3.0 + time) * mouseWarp.y
    );
    
    // Rotation speed from mouse X and speed param + bass rotation
    let rotSpeed = (mousePos.x * 0.5 + 0.5) * 0.3 + audioSpeed * 0.5 + bass * 0.15;
    let rotAngle = time * rotSpeed + mouseRot * 0.2 + bass * 0.3;
    let cos_r = cos(rotAngle);
    let sin_r = sin(rotAngle);
    let rotMat = mat2x2<f32>(cos_r, -sin_r, sin_r, cos_r);
    let rp = rotMat * warpedP;
    
    // Breathing pulse effect
    let breathe = 1.0 + sin(time * 1.5) * 0.08 * intensity;
    let brp = rp * breathe;
    let d = length(brp);
    let angle = atan2(brp.y, brp.x);
    
    // Dark background
    var col = vec3<f32>(0.015, 0.01, 0.02);
    
    // Background glow
    let bgGlow = exp(-d * d * 1.5) * 0.15;
    col += vec3<f32>(0.05, 0.02, 0.08) * bgGlow;
    
    // ─── Ring definitions with golden-angle layer rotation ───
    let rings = 6;
    var ringInner = 0.055 * (0.7 + scale * 0.5) / max(zoom, 0.25);
    
    for (var i = 0; i < rings; i++) {
        let fi = f32(i);
        let innerR = ringInner;
        let outerR = innerR * 1.25;
        let ringHue = fract(fi / f32(rings) + colorShift + time * 0.02);
        
        let contra = select(1.0, -1.0, i < 3);
        let layerAngle = GOLDEN_ANGLE * fi + time * rotSpeed * contra * 0.45;
        let cos_la = cos(layerAngle);
        let sin_la = sin(layerAngle);
        let layerRot = mat2x2<f32>(cos_la, -sin_la, sin_la, cos_la);
        let layerP = layerRot * brp;
        
        let ringCol = patternedRing(layerP, innerR, outerR, i % 5, time * (0.5 + speed), ringHue);
        // Tube anatomy: cathode at the layer's local angle 0, column runs round the ring.
        let tubeArc = fract(atan2(layerP.y, layerP.x) / TAU + 1.0) * TAU;
        let tubeCirc = TAU * (innerR + outerR) * 0.5;
        let discharge = dischargeProfile(tubeArc, tubeCirc, time, stripeDrift * contra, current);
        let gasTint = mix(vec3<f32>(1.0), gasLine(i) * 1.6, 0.35 + treble * 0.15);
        col += ringCol * gasTint * discharge * ignition * sqrt(current) * intensity * 2.0;
        
        // Add geometric shapes on some rings using Fibonacci petal counts
        if (i % 2 == 0) {
            let shapeR = (innerR + outerR) * 0.5;
            let petalIdx = clamp(i / 2, 0, 3);
            let numShapes = fibPetals[petalIdx];
            for (var s = 0; s < numShapes; s++) {
                let fs = f32(s);
                let sa = (fs / f32(numShapes)) * TAU + time * (0.2 + speed * 0.3) * (1.0 - fi * 0.1);
                let sc = vec2<f32>(cos(sa), sin(sa)) * shapeR;
                let toShape = layerP - sc;
                
                // Rotated shape
                let shapeRot = time * (0.5 + fi * 0.2) + fs * 0.5;
                let cos_sr = cos(shapeRot);
                let sin_sr = sin(shapeRot);
                let srotMat = mat2x2<f32>(cos_sr, -sin_sr, sin_sr, cos_sr);
                let shapeP = srotMat * toShape;
                
                var shapeDist: f32;
                if (i % 4 == 0) {
                    // Hexagon (6 is close to Fibonacci 5, 8)
                    shapeDist = sdPolygon(shapeP, 0.025 / zoom, 6);
                } else {
                    // Star with Fibonacci ray count
                    let starRayCount = fibPetals[clamp(petalIdx + 1, 0, 3)];
                    shapeDist = starRays(shapeP, 0.03 / zoom, starRayCount, 0.4);
                }
                
                let shapeGlow = exp(-shapeDist * shapeDist * 800.0 * zoom);
                let shapeCol = neonRainbow(ringHue + fs / f32(numShapes));
                col += shapeCol * shapeGlow * 0.6 * audioIntensity * ignition;
            }
        }
        
        // Connecting lines between rings
        if (i < rings - 1) {
            let nextR = innerR * PHI;
            let connFreq = 12.0 + fi * 4.0;
            for (var c = 0; c < i32(connFreq); c++) {
                let fc = f32(c);
                let ca = (fc / connFreq) * TAU;
                let a = ca + time * (0.1 + speed * 0.2);
                let innerP = vec2<f32>(cos(a), sin(a)) * innerR;
                let outerP = vec2<f32>(cos(a), sin(a)) * nextR;
                
                // Line SDF
                let lineDir = outerP - innerP;
                let lineLen = length(lineDir);
                let lineN = normalize(lineDir);
                let toP = layerP - innerP;
                let proj = clamp(dot(toP, lineN), 0.0, lineLen);
                let lineD = length(toP - lineN * proj);
                
                let lineGlow = exp(-lineD * lineD * 6000.0);
                let pulse = sin(time * 3.0 + fc * 0.5 + fi) * 0.5 + 0.5;
                let connHue = fract(ringHue + fc / connFreq * 0.3);
                col += neonRainbow(connHue) * lineGlow * 0.15 * pulse * intensity;
            }
        }
        ringInner = innerR * PHI;
    }
    
    // Central star burst with Fibonacci rays
    let centerRays = fibPetals[2]; // 13
    let starGlow = starRays(brp, 0.05 / zoom, centerRays, 0.3);
    let starMask = exp(-starGlow * starGlow * 500.0);
    let centerHue = fract(colorShift + time * 0.03);
    col += neonRainbow(centerHue) * starMask * 1.5 * intensity;
    
    // Central orb
    let orbGlow = exp(-d * d * 200.0 * zoom);
    col += vec3<f32>(1.0, 0.95, 0.8) * orbGlow * 0.8 * intensity;
    
    // Outer decorative border
    let borderR = ringInner + 0.02;
    let borderDist = abs(d - borderR);
    let borderMask = smoothstep(0.01, 0.0, borderDist);
    let borderPattern = sin(angle * 36.0 + time) * 0.5 + 0.5;
    col += neonRainbow(fract(colorShift + time * 0.05)) * borderMask * borderPattern * 0.3 * intensity;
    
    // Floating particles
    for (var fp = 0; fp < 12; fp++) {
        let ffp = f32(fp);
        let particleSeed = ffp * PHI * 10.0 + 100.0;
        let pa = hash1(particleSeed) * TAU + time * (0.2 + hash1(particleSeed * 2.0) * 0.5);
        let pr = hash1(particleSeed * 3.0) * borderR;
        let particleP = vec2<f32>(cos(pa), sin(pa)) * pr;
        let pd = length(brp - particleP);
        let psize = 0.008 / zoom;
        let pglow = exp(-pd * pd / (psize * psize));
        let phue = fract(ffp / 12.0 + colorShift + time * 0.02);
        col += neonRainbow(phue) * pglow * 0.5 * intensity;
    }
    
    // Vignette
    let vignette = 1.0 - dot(uv, uv) * 0.3;
    col *= max(vignette, 0.5);
    
    // Saturation boost
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    col = mix(vec3<f32>(lum), col, 1.2 + intensity * 0.3);
    
    // Strike front: violet-white breakdown flash (N2/Ar continuum)
    col += vec3<f32>(0.75, 0.6, 1.0) * strikeFront * (0.8 + intensity);

    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Temporal afterglow in display space (A holds ACES display RGBA)
    let dims = vec2<i32>(i32(res.x), i32(res.y));
    let prevCoord = clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevCoord, 0);
    let mapped = acesToneMap(max(col, vec3<f32>(0.0)) * 1.1);
    let display = mix(mapped, max(mapped, prev.rgb * 0.92), 0.6);
    // Alpha = neon glow coverage: lit tube luminance plus afterglow persistence
    let glowLum = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(max(glowLum * 1.3 + strikeFront * 0.3, prev.a * 0.9), 0.03, 1.0);
    let finalColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(clamp(1.0 - d * 0.55, 0.0, 1.0), 0.0, 0.0, 0.0));
}
