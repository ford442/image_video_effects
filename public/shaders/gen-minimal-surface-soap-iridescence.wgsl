// ═══════════════════════════════════════════════════════════════════
//  Minimal Surface Soap Iridescence
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Gravity drainage with Marangoni marginal-regeneration plumes and Newton black film; Culick rupture holes with Rayleigh-Plateau rim beading on click
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
  config: vec4<f32>,       // x=time, y=rippleCount, zw=resolution
  zoom_config: vec4<f32>,  // x=time, yz=mouse uv, w=mouse down
  zoom_params: vec4<f32>,  // x=Bonnet Rotation, y=Surface Tension, z=Y Rotation, w=Caustic Glow
  ripples: array<vec4<f32>, 50>, // xy=pos, z=start time
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash / noise ──────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

// ── Color science ─────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h, h, h) + k) * 6.0 - vec3<f32>(3.0, 3.0, 3.0));
    return v * mix(vec3<f32>(k.x, k.x, k.x), clamp(p - vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn colorTemperature(t: f32) -> vec3<f32> {
    // t in [-1, 1]; negative = cool, positive = warm
    let warm = vec3<f32>(1.12, 1.0, 0.82);
    let cool = vec3<f32>(0.82, 0.92, 1.12);
    let m = t * 0.5 + 0.5;
    return mix(cool, warm, m);
}

fn splitTone(col: vec3<f32>, shadows: vec3<f32>, highlights: vec3<f32>, balance: f32) -> vec3<f32> {
    let lum = luma(col);
    let shadowMask = 1.0 - smoothstep(0.0, balance, lum);
    let highlightMask = smoothstep(balance, 1.0, lum);
    let tinted = mix(col, col * shadows, shadowMask * 0.35);
    return tinted + highlightMask * highlights * lum * 0.22;
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ── Geometry ──────────────────────────────────────────────────────
fn surfacePoint(uParam: f32, vParam: f32, time: f32, bonnet: f32, treble: f32) -> vec3<f32> {
    let cb = cos(bonnet);
    let sb = sin(bonnet);
    let coshv = cosh(vParam);
    let sinhv = sinh(vParam);
    let cu = cos(uParam);
    let su = sin(uParam);
    let bubble = treble * sin(uParam * 3.0 + vParam * 5.0 + time * 2.0) * 0.3;
    let catX = coshv * cu;
    let catY = coshv * su;
    let catZ = vParam;
    let helX = sinhv * cu;
    let helY = sinhv * su;
    let helZ = uParam;
    return vec3<f32>(
        catX * cb + helX * sb + bubble,
        catY * cb + helY * sb,
        catZ * cb + helZ * sb
    );
}

fn surfaceTangentU(uParam: f32, vParam: f32, time: f32, bonnet: f32, treble: f32) -> vec3<f32> {
    let cb = cos(bonnet);
    let sb = sin(bonnet);
    let coshv = cosh(vParam);
    let sinhv = sinh(vParam);
    let cu = cos(uParam);
    let su = sin(uParam);
    let bubbleU = treble * 3.0 * cos(uParam * 3.0 + vParam * 5.0 + time * 2.0) * 0.3;
    let catXu = -coshv * su;
    let catYu = coshv * cu;
    let helXu = -sinhv * su;
    let helYu = sinhv * cu;
    return vec3<f32>(
        catXu * cb + helXu * sb + bubbleU,
        catYu * cb + helYu * sb,
        sb
    );
}

fn surfaceTangentV(uParam: f32, vParam: f32, time: f32, bonnet: f32, treble: f32) -> vec3<f32> {
    let cb = cos(bonnet);
    let sb = sin(bonnet);
    let coshv = cosh(vParam);
    let sinhv = sinh(vParam);
    let cu = cos(uParam);
    let su = sin(uParam);
    let bubbleV = treble * 5.0 * cos(uParam * 3.0 + vParam * 5.0 + time * 2.0) * 0.3;
    let catXv = sinhv * cu;
    let catYv = sinhv * su;
    let helXv = coshv * cu;
    let helYv = coshv * su;
    return vec3<f32>(
        catXv * cb + helXv * sb + bubbleV,
        catYv * cb + helYv * sb,
        cb
    );
}

fn rotateY(p: vec3<f32>, cy: f32, sy: f32) -> vec3<f32> {
    return vec3<f32>(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy);
}

// ── Entry ─────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = (vec2<f32>(pixel) + 0.5) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mousePressed = u.zoom_config.w > 0.5;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let aspect = res.x / max(res.y, 1.0);
    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    // Parameter-space surface coordinates
    let st = (uv01 - 0.5) * 4.0;
    let uParam = st.x;
    let vParam = st.y;

    // Bonnet morph and Y rotation
    let bonnet = time * 0.15 * (1.0 + bass * 0.5) + p1 * PI;
    let rotY = time * 0.1 + p3 * PI;
    let cy = cos(rotY);
    let sy = sin(rotY);

    // Base surface point
    var P = surfacePoint(uParam, vParam, time, bonnet, treble);

    // Branchless mouse dimple
    let dimple = length(uv01 - mouse);
    let dimpleStrength = exp(-dimple * dimple * 20.0) * 0.5;
    P.z -= select(0.0, dimpleStrength, mousePressed);

    // View-space position
    let viewP = rotateY(P, cy, sy);
    let rx = viewP.x;
    let surfY = viewP.y;
    let rz = viewP.z;

    // Perspective projection
    let depth = 1.0 / (3.0 + rz);
    let proj = vec2<f32>(rx, surfY) * depth;
    let screenPos = proj * 0.4 + 0.5;

    // Analytic normal in view space
    let puObj = surfaceTangentU(uParam, vParam, time, bonnet, treble);
    let pvObj = surfaceTangentV(uParam, vParam, time, bonnet, treble);
    let pu = rotateY(puObj, cy, sy);
    let pv = rotateY(pvObj, cy, sy);
    let rawN = cross(pu, pv);
    let nLen = length(rawN);
    var N = select(vec3<f32>(0.0, 0.0, 1.0), normalize(rawN), nLen > 0.0001);

    // Curvature / film thickness proxy
    let area = length(cross(pu, pv));
    let curvature = area * 0.35;
    let filmBase = 0.22 + mids * 0.55 + curvature * 0.28 + bass * 0.08;

    // ── Idea 1: gravity drainage + Marangoni marginal regeneration ──
    // Film drains under gravity: Mysels-type profile h ∝ sqrt(depth below
    // the top edge), thin at the top, wedge-thick at the bottom. Surface
    // tension gradients pull thin film up from the bottom border as rising,
    // swirling plumes (marginal regeneration). Where h → 0 the film turns
    // into Newton black film: no interference, nearly no reflection.
    let tension = p2;
    let height = clamp(uv01.y, 0.0, 1.0);             // 0 = top edge, 1 = bottom
    let drainProfile = sqrt(height + 0.015);
    let swirl = sin(uv01.y * 7.0 + time * 0.6 + fbm(uv01 * 3.0, 2) * 4.0) * (0.06 + mids * 0.05);
    let plumeCoord = vec2<f32>((uv01.x + swirl) * 9.0 * aspect, uv01.y * 2.5 + time * (0.12 + tension * 0.25));
    let plumeNoise = fbm(plumeCoord, 3);
    let marangoni = smoothstep(0.52, 0.8, plumeNoise) * smoothstep(0.15, 0.85, height) * (0.5 + tension * 0.6);
    let filmThick = max(0.0, filmBase * mix(0.18, 1.3, drainProfile) - marangoni * 0.22 * filmBase);
    let blackFilm = (1.0 - smoothstep(0.035, 0.11, filmThick)) * (0.85 + treble * 0.15);

    // View-dependent thin-film phase
    let V = vec3<f32>(0.0, 0.0, 1.0);
    let NdotV = max(0.0, dot(N, V));
    let viewAngle = 1.0 - NdotV;
    let phaseScale = 0.13 + 0.04 * sin(time * 0.2);
    let basePhase = filmThick * 14.0 + rz * 0.12 + viewAngle * 1.4;
    let phaseR = basePhase + 0.05;
    let phaseG = basePhase;
    let phaseB = basePhase - 0.04;

    var irid = vec3<f32>(
        hsv2rgb(fract(phaseR * phaseScale), 0.55 + mids * 0.25, 0.88).r,
        hsv2rgb(fract(phaseG * phaseScale), 0.55 + mids * 0.25, 0.88).g,
        hsv2rgb(fract(phaseB * phaseScale), 0.55 + mids * 0.25, 0.88).b
    );
    // Newton black film: path difference << wavelength, reflectance ∝ sin²(2πnh/λ) → 0
    irid *= 1.0 - blackFilm * 0.93;

    // Cinematic lighting
    let lightPos = normalize(vec3<f32>(
        0.5 + 0.25 * sin(time * 0.3),
        0.7,
        0.6 + 0.15 * cos(time * 0.25)
    ));
    let L = lightPos;
    let H = normalize(L + V);
    let NdotL = max(0.0, dot(N, L));
    let NdotH = max(0.0, dot(N, H));

    // Fresnel rim
    let rimPower = 2.0 + p2 * 2.0;
    let rim = pow(1.0 - NdotV, rimPower) * vec3<f32>(0.65, 0.9, 1.05);

    // Specular with roughness controlled by surface tension
    let roughness = mix(6.0, 48.0, p2);
    let spec = pow(NdotH, roughness) * (0.8 + treble * 0.6);

    // Subsurface scattering glow
    let backLight = max(0.0, -dot(N, L));
    let sss = vec3<f32>(1.0, 0.5, 0.32) * backLight * filmThick * (0.35 + bass * 0.5);

    // Caustics
    let caustic = pow(curvature, 1.6) * 1.4;
    let causticColor = vec3<f32>(0.48, 0.72, 0.9) * caustic * (0.4 + treble);

    // Combine lighting layers
    var color = irid * (0.22 + 0.78 * NdotL);
    color += rim;
    color += vec3<f32>(spec);
    color += sss;
    color += causticColor;

    // ── Idea 2: Culick rupture holes from click ripples ──
    // A click punctures the film. The hole opens at the Culick speed
    // v = sqrt(2σ / (ρ h)): faster in thin (drained / black) film, slower in
    // the thick bottom wedge, so holes elongate toward the top. Liquid swept
    // from the hole piles into a toroidal rim that beads into droplets
    // (Rayleigh–Plateau instability of the rim cylinder). The film re-wets
    // after a few seconds.
    var holeCover = 0.0;
    var rimGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < 3.5) {
            let dv = (uv01 - rp.xy) * vec2<f32>(aspect, 1.0);
            let d = length(dv);
            let culick = 0.045 * sqrt((0.5 + tension) / max(filmThick, 0.04));
            let radius = age * culick * (1.0 + bass * 0.3);
            let heal = 1.0 - smoothstep(2.2, 3.5, age);
            let inside = 1.0 - smoothstep(radius - 0.006, radius, d);
            let rimW = 0.004 + 0.02 * sqrt(radius);
            let beads = 5.0 + floor(radius * 60.0);
            let ang = atan2(dv.y, dv.x);
            let beading = 0.55 + 0.45 * cos(ang * beads + hashf(rp.z) * TAU);
            let rimBand = exp(-pow((d - radius) / rimW, 2.0)) * mix(1.0, beading, smoothstep(0.03, 0.15, radius));
            holeCover = max(holeCover, inside * heal);
            rimGlow += rimBand * heal;
        }
    }
    rimGlow = min(rimGlow, 2.0);
    let holeBg = vec3<f32>(0.03, 0.045, 0.07);
    color = mix(color, holeBg, holeCover);
    color += vec3<f32>(0.95, 0.97, 1.0) * rimGlow * (0.6 + p4 * 1.2 + treble * 0.4);

    // HDR bloom threshold
    let exposure = 1.05 + p4 * 0.55;
    color *= exposure;
    let bloomThreshold = 0.9;
    let bloom = max(color - vec3<f32>(bloomThreshold), vec3<f32>(0.0));
    color += bloom * (0.45 + p4 * 0.35);

    // Temporal surface memory
    let cDims = vec2<i32>(textureDimensions(dataTextureC));
    let prevCoord = clamp(pixel, vec2<i32>(0), cDims - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevCoord, 0);
    let decay = 0.96 - p4 * 0.03;
    let trail = mix(prev.rgb * decay, color, 0.1 + bass * 0.05);
    color = mix(color, trail, 0.3);

    // Volumetric atmosphere / fog
    let safeDepth = clamp(depth, 0.0, 1.0);
    let fogDensity = 0.5 + p2 * 1.2;
    let fogAmount = (1.0 - safeDepth) * fogDensity;
    let fogColor = vec3<f32>(0.06, 0.09, 0.13) * (0.8 + mids * 0.35);
    color = mix(color, fogColor, clamp(fogAmount, 0.0, 0.55));

    // Film grain
    let grain = fbm(uv01 * 600.0 + vec2<f32>(time * 0.2), 3) - 0.5;
    color += grain * 0.02 * (1.0 - luma(color));

    // Color grading: dynamic temperature + split tone
    let temp = 0.25 * sin(time * 0.12) + (p1 - 0.5) * 0.15;
    color *= colorTemperature(temp);
    color = splitTone(color, vec3<f32>(0.78, 0.9, 1.05), vec3<f32>(1.08, 0.95, 0.72), 0.38);

    // Chromatic aberration
    let caStr = 0.0035 * (1.0 + bass) + (1.0 - safeDepth) * 0.0015;
    color = genChromaticShift(color, uv01, caStr, time);

    // ACES tone map
    color = acesToneMap(color);

    // Semantic alpha
    // film coverage: thickness × curvature × depth, lost in black film and
    // rupture holes, regained on the liquid rims
    let filmCover = clamp(filmThick * curvature * safeDepth * 3.0, 0.0, 0.98) * (1.0 - blackFilm * 0.6);
    let alpha = clamp(filmCover * (1.0 - holeCover) + rimGlow * 0.35, 0.0, 0.98);

    // Output
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth * (1.0 - holeCover), 0.0, 0.0, 0.0));
}
