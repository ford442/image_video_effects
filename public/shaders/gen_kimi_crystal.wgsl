// ═══════════════════════════════════════════════════════════════════
//  Kimi Crystal
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Nakaya habit transition - hex plates sprout six-fold stellar dendrite arms with 60-degree sidebranches as growth (and treble supersaturation) advances; 22-degree ice halo + parhelia around the mouse "sun" from minimum deviation through 60-degree ice prisms, dispersed by IOR 1.31/1.32/1.33
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
//
//  Preserved core: odd-row hex offset grid, sdHexagon crystals, the
//  physical transmission block (crystalMask, Fresnel-Schlick with F0
//  from IOR_ICE = 1.31, Beer absorption, transmission product) and the
//  spectral-dispersion Fresnel edge glow.

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
  config: vec4<f32>,       // x=time, y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Grid Density, y=Crystal Purity, z=Growth Speed, w=Crystal Thickness
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;
// Ice refractive index (mean) - identity constant of this shader.
const IOR_ICE: f32 = 1.31;
// Spectral dispersion of ice: slight IOR variation per channel.
const IOR_ICE_R: f32 = 1.31;
const IOR_ICE_G: f32 = 1.32;
const IOR_ICE_B: f32 = 1.33;

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Signed distance to hexagon
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    let q = abs(p);
    let h = vec2<f32>(dot(k.xy, q), q.y);
    return length(max(h - vec2<f32>(k.z * r, r * 0.5), vec2<f32>(0.0))) + min(max(h.x - k.z * r, h.y - r * 0.5), 0.0);
}

// Fresnel for ice/glass
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Hue-preserving clamp: scale down uniformly so the brightest
// channel never exceeds maxVal, keeping the hue of HDR highlights.
fn hueLimit(c: vec3<f32>, maxVal: f32) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    if (peak > maxVal) {
        return c * (maxVal / peak);
    }
    return c;
}

// Filmic ACES approximation (Narkowicz fit) for the final store.
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Distance from p to segment a->b.
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// Nakaya stellar dendrite: fold the plane into one 60-degree wedge (six-fold
// ice symmetry, mirrored), then a tapering main arm along the wedge axis with
// sidebranches leaving it at 60 degrees - i.e. parallel to the neighbouring
// arms, as real dendritic snow crystals grow. Returns a signed distance.
fn sdDendrite(q: vec2<f32>, armLen: f32, width: f32, branchGrowth: f32) -> f32 {
    let sector = TAU / 6.0;
    let r = length(q);
    let a = atan2(q.y, q.x);
    let af = abs(a - sector * round(a / sector));
    let f = vec2<f32>(cos(af), sin(af)) * r;
    let along = clamp(f.x / max(armLen, 1e-4), 0.0, 1.0);
    var d = sdSegment(f, vec2<f32>(0.0), vec2<f32>(armLen, 0.0)) - width * (1.0 - along * 0.6);
    let dir = vec2<f32>(0.5, 0.866025404);
    for (var k = 1; k <= 3; k++) {
        let x0 = armLen * (0.22 + 0.2 * f32(k));
        let len = (armLen - x0) * 0.55 * branchGrowth;
        let db = sdSegment(f, vec2<f32>(x0, 0.0), vec2<f32>(x0, 0.0) + dir * len) - width * 0.55;
        d = min(d, db);
    }
    return d;
}

// Minimum deviation of light through a 60-degree ice prism (the side faces
// of a hexagonal column/plate): D = 2*asin(n*sin(A/2)) - A.
fn prismMinDeviation(n: f32) -> f32 {
    let A = TAU / 6.0;
    return 2.0 * asin(n * sin(A * 0.5)) - A;
}

// Halo radial profile: no refracted light inside minimum deviation (the dark
// inner sky), a sharp inner edge, and a slow fade outward.
fn haloProfile(rad: f32, rMin: f32) -> f32 {
    let inner = smoothstep(rMin - 0.012, rMin, rad);
    return inner * exp(-max(rad - rMin, 0.0) * 9.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    // Standard bounds guard: discard out-of-range invocations.
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 5.0; // Fast motion upgrade
    let px = vec2<i32>(global_id.xy);

    // ═══════════════════════════════════════════════════════════════
    // Parameters via zoom_params (saved-preset contract):
    // x: grid density      -> hex grid scale 2..5
    // y: crystal purity    -> transmission / absorption 0.3..1, halo clarity
    // z: growth speed      -> animation rate 0.05..0.3
    // w: thickness / depth -> physical light path 0.1..1
    // ═══════════════════════════════════════════════════════════════

    let gridDensity = mix(2.0, 5.0, u.zoom_params.x);
    let crystalPurity = mix(0.3, 1.0, u.zoom_params.y);
    let growthSpeed = mix(0.05, 0.3, u.zoom_params.z);
    let crystalThickness = mix(0.1, 1.0, u.zoom_params.w);

    // ── Audio reactivity (plasmaBuffer[0] = bass, mids, treble) ─────
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    // Bass energy pulses the crystal growth cycle.
    let bassGrowth = 1.0 + bass * 0.4;

    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = resolution.x / resolution.y;

    // Center and aspect correct
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Mouse position in crystal space
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;

    // Crystal grid
    let gridScale = gridDensity;
    var gridUV = p * gridScale;

    // Hexagonal grid
    let hexSize = 0.5;
    let hexSpacing = vec2<f32>(1.732, 2.0) * hexSize;

    // Calculate hex grid coordinates
    let hexUV = vec2<f32>(gridUV.x / hexSpacing.x, gridUV.y / hexSpacing.y);
    let hexId = floor(hexUV);
    let hexFract = fract(hexUV);

    // Offset every other row
    var offset = vec2<f32>(0.0);
    if (i32(hexId.y) % 2 == 1) {
        offset.x = 0.5;
    }

    // Local hex coordinate
    var hexLocal = hexFract - vec2<f32>(0.5);
    if (i32(hexId.y) % 2 == 1) {
        hexLocal.x -= 0.5;
    }

    // Per-row shimmer: mids ripple along the hex rows.
    let rowIndex = i32(hexId.y);
    let rowShimmer = mids * (0.5 + 0.5 * sin(time * 6.0 + f32(rowIndex) * 1.7));

    // ── Click ripples: nucleation fronts ────────────────────────
    // A click seeds a freezing front; cells it has swept over snap to full
    // growth and the front itself flashes as a frost ring.
    let cellCenterP = (hexId + vec2<f32>(0.5 + offset.x, 0.5)) * hexSpacing / gridScale;
    var frozen = 0.0;
    var frostFlash = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = u.config.x - rp.z;
        if (age >= 0.0 && age < 4.0) {
            var rpos = rp.xy * 2.0 - 1.0;
            rpos.x *= aspect;
            let frontR = age * 0.9;
            let fade = exp(-age * 0.8);
            frozen = max(frozen, smoothstep(frontR + 0.05, frontR - 0.05, length(cellCenterP - rpos)) * fade);
            let fd = length(p - rpos) - frontR;
            frostFlash += exp(-fd * fd * 220.0) * fade;
        }
    }

    // Animated crystal growth (bass pulses the cycle and the size)
    let hexHash = hash(hexId + floor(time * growthSpeed * bassGrowth));
    let growthPhase = max(fract(time * growthSpeed * bassGrowth * 0.5 + hexHash * 10.0), frozen * 0.95);
    let sizePulse = 1.0 + bass * 0.15 * sin(time * 4.0 + hexHash * 6.28);
    let crystalSize = smoothstep(0.0, 0.8, growthPhase) * hexSize * 0.8 * sizePulse;

    // Mouse influence on nearby crystals
    let mouseHex = mousePos * gridScale / hexSpacing;
    let distToMouseHex = length(hexUV + offset - mouseHex);
    let mouseGlow = smoothstep(2.0, 0.0, distToMouseHex) * mouseDown;

    // Rotate crystal based on time and mouse
    let rotation = time * 0.2 + hexHash * 6.28 + mouseGlow * 2.0;
    hexLocal = rotate(hexLocal, rotation);

    // ── Idea 1: Nakaya habit transition (plate -> stellar dendrite) ──
    // Low supersaturation keeps a solid hexagonal plate; as the crystal
    // matures (and treble raises supersaturation) the plate core shrinks and
    // six dendrite arms with 60-degree sidebranches race outward.
    let supersat = hash(hexId * 1.37 + vec2<f32>(7.1, 3.3)) * 0.6 + treble * 0.5;
    let habit = smoothstep(0.35, 0.9, growthPhase) * smoothstep(0.2, 0.7, supersat);
    let plateD = sdHexagon(hexLocal, crystalSize * mix(1.0, 0.38, habit));
    let armLen = crystalSize * mix(0.5, 1.15, habit);
    let armWidth = mix(0.012, 0.03, u.zoom_params.w) * (0.6 + 0.4 * crystalSize / (hexSize * 0.8));
    let dendD = sdDendrite(hexLocal, armLen, armWidth, smoothstep(0.5, 1.0, habit));
    let d = mix(plateD, min(plateD, dendD), step(0.001, habit));

    // Crystal interior pattern (row shimmer brightens the facets)
    let interiorPattern = (sin(length(hexLocal) * 20.0 - time * 2.0) * 0.5 + 0.5) * (1.0 + rowShimmer * 0.6);

    // Color palette - icy blues and warm gold accents
    let bgColor = vec3<f32>(0.02, 0.03, 0.05);
    let crystalBase = vec3<f32>(0.4, 0.7, 0.9);      // Ice blue
    let crystalHighlight = vec3<f32>(0.8, 0.95, 1.0); // White highlight
    let crystalDeep = vec3<f32>(0.1, 0.3, 0.6);      // Deep blue
    let goldAccent = vec3<f32>(1.0, 0.8, 0.3);       // Gold

    // ═══════════════════════════════════════════════════════════════
    // Physical Transmission Calculation
    // ═══════════════════════════════════════════════════════════════

    // Crystal mask (1 inside, 0 outside)
    let crystalMask = smoothstep(0.02, -0.02, d);

    // Distance from crystal center (for Fresnel)
    let distFromCenter = length(hexLocal) / max(crystalSize, 0.01);
    let cosTheta = 1.0 - distFromCenter * 0.5; // Approximate view angle

    // Fresnel for ice
    let F0 = pow((IOR_ICE - 1.0) / (IOR_ICE + 1.0), 2.0);
    let fresnel = fresnelSchlick(max(cosTheta, 0.0), F0);

    // Path length through crystal (thicker at center)
    let pathLength = crystalThickness * (1.0 - distFromCenter * 0.3) / crystalPurity;

    // Absorption (ice absorbs slightly, more if impure)
    let absorptionCoeff = mix(0.5, 3.0, 1.0 - crystalPurity);
    let absorption = exp(-absorptionCoeff * pathLength * crystalMask);

    // Transmission coefficient
    let transmission = absorption * (1.0 - fresnel) * crystalPurity;

    // Mix colors based on crystal shape
    var color = bgColor;

    // Crystal body with depth layers
    color = mix(color, crystalDeep, crystalMask * 0.5 * (1.0 - distFromCenter * 0.5));
    color = mix(color, crystalBase, crystalMask * interiorPattern * transmission);
    color = mix(color, crystalHighlight, crystalMask * smoothstep(0.0, 0.3, -d) * transmission);

    // ── Spectral dispersion edge glow ───────────────────────────
    let cosT = max(cosTheta, 0.0);
    let F0r = pow((IOR_ICE_R - 1.0) / (IOR_ICE_R + 1.0), 2.0);
    let F0g = pow((IOR_ICE_G - 1.0) / (IOR_ICE_G + 1.0), 2.0);
    let F0b = pow((IOR_ICE_B - 1.0) / (IOR_ICE_B + 1.0), 2.0);
    let edgeR = smoothstep(0.05, 0.0, abs(d - 0.008)) * fresnelSchlick(cosT, F0r);
    let edgeG = smoothstep(0.05, 0.0, abs(d)) * fresnelSchlick(cosT, F0g);
    let edgeB = smoothstep(0.05, 0.0, abs(d + 0.008)) * fresnelSchlick(cosT, F0b);
    let spectralEdge = vec3<f32>(edgeR, edgeG, edgeB) * (1.0 + treble * 0.4);
    color += goldAccent * spectralEdge * 0.8;

    // Row shimmer glow on crystal bodies
    color += crystalBase * rowShimmer * crystalMask * 0.2;

    // Mouse interaction glow
    color += vec3<f32>(0.5, 0.8, 1.0) * mouseGlow * 0.3 * transmission;

    // Sparkles at vertices (specular highlights)
    let vertexDist = sdHexagon(hexLocal, crystalSize * 0.9);
    let sparkle = select(0.0, 1.0, vertexDist > 0.0 && vertexDist < 0.05 && hash(hexId + vec2<f32>(time)) > 0.95);
    color += vec3<f32>(1.0) * sparkle * fresnel;

    // Final intensity adjustment
    color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(0.9)) * 1.1;
    color = hueLimit(color, 1.2);

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Opacity control - blend crystal over input
    let opacity = 0.9;
    let body = crystalMask * opacity;
    var linear = mix(inputColor.rgb, color, body);

    // ── Idea 2: 22-degree halo + parhelia around the mouse "sun" ────
    // Light refracted through randomly oriented 60-degree ice prisms piles up
    // at minimum deviation (~21.8 deg for n=1.31), so a ring appears with a red
    // inner edge and bluer outer skirt (n rises toward blue). Horizontally
    // settled plates concentrate it into sun dogs left and right of the sun.
    let haloScale = 1.4;
    let rMinR = tan(prismMinDeviation(IOR_ICE_R)) * haloScale;
    let rMinG = tan(prismMinDeviation(IOR_ICE_G)) * haloScale;
    let rMinB = tan(prismMinDeviation(IOR_ICE_B)) * haloScale;
    let sunVec = p - mousePos;
    let sunR = length(sunVec);
    let haloRGB = vec3<f32>(haloProfile(sunR, rMinR), haloProfile(sunR, rMinG), haloProfile(sunR, rMinB));
    let dogL = sunVec - vec2<f32>(-rMinG, 0.0);
    let dogR = sunVec - vec2<f32>(rMinG, 0.0);
    let dogShape = exp(-dot(dogL * vec2<f32>(3.0, 14.0), dogL * vec2<f32>(3.0, 14.0)))
                 + exp(-dot(dogR * vec2<f32>(3.0, 14.0), dogR * vec2<f32>(3.0, 14.0)));
    let dogRGB = vec3<f32>(
        haloProfile(abs(sunVec.x), rMinR),
        haloProfile(abs(sunVec.x), rMinG),
        haloProfile(abs(sunVec.x), rMinB)
    ) * smoothstep(0.12, 0.0, abs(sunVec.y));
    let haloStrength = (0.18 + mouseDown * 0.5) * crystalPurity * (1.0 + bass * 0.4);
    let sunCore = exp(-sunR * sunR * 900.0) * (0.4 + mouseDown * 0.8);
    let haloLight = (haloRGB * 0.55 + dogRGB * dogShape * 1.3) * haloStrength
                  + vec3<f32>(1.0, 0.97, 0.9) * sunCore;
    // Inside minimum deviation the sky is darker (no refracted light there).
    linear *= 1.0 - smoothstep(rMinR, rMinR * 0.8, sunR) * 0.12 * haloStrength;
    linear += haloLight * (1.0 - body * 0.5);

    // Nucleation frost ring from clicks
    linear += crystalHighlight * frostFlash * 0.35;

    // Single ACES pass on the display colour
    let display = acesToneMap(max(linear, vec3<f32>(0.0)));

    // Alpha: ice coverage (opaque where thick/impure, clearer where
    // transmissive) plus Fresnel edge, halo light and frost-front glow.
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let haloLum = dot(haloLight, vec3<f32>(0.333));
    let edgeLum = dot(spectralEdge, vec3<f32>(0.333));
    let alpha = clamp(body * mix(1.0, 0.55, transmission) + edgeLum * 0.3 + haloLum * 0.4
                      + frostFlash * 0.25 + luma * 0.15, 0.02, 1.0);

    let finalColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, px, finalColor);
    textureStore(dataTextureA, px, finalColor);

    // Depth based on crystal presence
    let generatedDepth = crystalMask * 0.5 + 0.5;
    let finalDepth = mix(inputDepth, generatedDepth, body);
    textureStore(writeDepthTexture, px, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
