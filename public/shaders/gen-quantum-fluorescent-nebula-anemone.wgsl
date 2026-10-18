// ═══════════════════════════════════════════════════════════════════
//  Quantum-Fluorescent Nebula-Anemone
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: nematocyst pulse beads crawling the tentacles; Stokes-shift amber afterglow from C history; crenulated breathing oral disc
//  A packing: raw field state (glow history, fog, quantum, alpha); ACES only on writeTexture
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
    config: vec4<f32>,       // x=Time, y=ClickCount (NOT audio), z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Fluorescence Intensity, y=Tentacle Density, z=Audio Reactivity, w=Nebula Density
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 6; i++) {
        value += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return value;
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let v = max(c.r, max(c.g, c.b));
    let minc = min(c.r, min(c.g, c.b));
    let s = select(0.0, (v - minc) / v, v > 0.0);
    let delta = v - minc;
    var h = 0.0;
    if (delta > 0.0) {
        if (v == c.r) { h = (c.g - c.b) / delta; }
        else if (v == c.g) { h = 2.0 + (c.b - c.r) / delta; }
        else { h = 4.0 + (c.r - c.g) / delta; }
    }
    h = fract(h / 6.0 + 1.0);
    return vec3<f32>(h, s, v);
}

fn hue_preserving_clamp(c: vec3<f32>, max_val: f32) -> vec3<f32> {
    let hsv = rgb2hsv(c);
    let v = min(hsv.z, max_val);
    return hsv2rgb(vec3<f32>(hsv.x, hsv.y, v));
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51, 2.51, 2.51);
    let b = vec3<f32>(0.03, 0.03, 0.03);
    let c = vec3<f32>(2.43, 2.43, 2.43);
    let d = vec3<f32>(0.59, 0.59, 0.59);
    let e = vec3<f32>(0.14, 0.14, 0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign_dither(uv: vec2<f32>) -> f32 {
    let p = floor(uv);
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

fn god_rays(uv: vec2<f32>, time: f32, density: f32) -> f32 {
    var rays = 0.0;
    var a = 0.0;
    for (var i = 0; i < 8; i++) {
        let fi = f32(i);
        let angle = fi * 0.17 + time * 0.05;
        let dir = vec2<f32>(cos(angle), sin(angle));
        let proj = dot(uv - vec2<f32>(0.5), dir);
        rays += pow(max(0.0, sin(proj * 12.0 + time * 0.3 + fi)), 8.0) * density;
        a += 1.0;
    }
    return rays / a;
}

fn volumetric_fog(p: vec2<f32>, time: f32, density: f32) -> f32 {
    let f1 = fbm(p * 1.5 + time * vec2<f32>(0.04, 0.06));
    let f2 = fbm(p * 3.0 - time * vec2<f32>(0.07, 0.03));
    return max(0.0, f1 * 0.7 + f2 * 0.3) * density;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<f32>(u.config.z, u.config.w);
    if (gid.x >= u32(size.x) || gid.y >= u32(size.y)) { return; }
    let uv = vec2<f32>(gid.xy) / size;

    let time = u.config.x;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    // Sliders honour their saved JSON labels (HEAD read them under different names).
    let fluorescence = u.zoom_params.x;      // Fluorescence Intensity
    let tentacleDensity = u.zoom_params.y;   // Tentacle Density (count + mouse reach)
    let audioReact = u.zoom_params.z;        // Audio Reactivity
    let nebulaDensity = u.zoom_params.w;     // Nebula Density
    let tentacleReach = tentacleDensity;     // HEAD reach: 0.5 -> 0.4 after *0.8
    let quantumFreq = 0.5;                   // HEAD's value at its 0.5 default

    // Live audio: bass/mid/treble from plasmaBuffer[0].xyz (config.y is click count)
    let au = plasmaBuffer[0].xyz;
    let audio = (au.x * 0.5 + au.y * 0.3 + au.z * 0.2) * audioReact * 2.0;

    // Exact history load (raw field packing: r = glow history)
    let cPrev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);

    let prev = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // === Cosmic nebula base ===
    var p = uv * 6.0 - 3.0;
    p += vec2<f32>(sin(time * 0.15), cos(time * 0.2)) * 0.8;

    let nebula = fbm(p * 1.2 + time * vec2<f32>(0.1, 0.15)) * nebulaDensity;
    let nebula2 = fbm(p * 2.4 - time * vec2<f32>(0.2, 0.1)) * (nebulaDensity * 0.6);
    let fog = volumetric_fog(p, time, nebulaDensity * 0.9);

    // === Quantum interference field ===
    let qWave = sin(length(p) * quantumFreq + time * 6.0) *
                cos(p.x * quantumFreq * 1.3 - time * 4.0) *
                sin(p.y * quantumFreq * 0.8 + time * 5.0);
    let quantum = (qWave * 0.5 + 0.5) * 0.8;

    // === Fluorescent anemone tentacles ===
    var anemone = 0.0;
    var tentacleColor = vec3<f32>(0.0);
    var tentacleEmission = 0.0;
    var beads = vec3<f32>(0.0);

    let warmLight = vec3<f32>(1.4, 0.7, 0.25);
    let coolLight = vec3<f32>(0.25, 0.8, 1.6);
    let rimLight = vec3<f32>(1.2, 0.4, 1.8);

    for (var i = 0; i < 22; i++) {
        let fi = f32(i);
        let angle = fi * PI * 2.0 / 22.0 + time * 0.35;
        let tentacleP = rot(angle) * p;

        let sway = sin(time * 3.0 + fi * 1.7) * 0.4;
        let dist = length(tentacleP + vec2<f32>(sway, 0.0)) - 1.6;

        let mouseDir = normalize(mouse - uv + 0.0001);
        let reach = tentacleReach * 0.8;
        let mouseInfluence = max(0.0, 1.0 - length(uv - mouse) * 3.5) * reach;

        // Tentacle Density: soft-gated count, all 22 visible at the 0.5 default
        let tentGate = clamp(tentacleDensity * 44.0 - fi, 0.0, 1.0);
        let tent = exp(-dist * dist * (3.5 - mouseInfluence * 1.2)) * tentGate;
        anemone += tent * 0.75;

        // Iridescent hue per tentacle
        let hueShift = fi * 0.06 + time * 0.4;
        let tentColor = hsv2rgb(vec3<f32>(fract(hueShift), 0.85, 1.0));

        // Dual-temperature lighting
        let lit = tentColor * warmLight * 0.6 + tentColor * coolLight * 0.45;

        // Fresnel rim based on radial falloff
        let rim = pow(1.0 - clamp(dist * 0.6, 0.0, 1.0), 4.0);
        let rimLit = rimLight * rim * 2.5;

        tentacleColor += (lit + rimLit) * tent * fluorescence;
        tentacleEmission += tent * fluorescence;

        // [Idea 1] Nematocyst pulse beads: sparse photophores crawling each band
        let q = tentacleP + vec2<f32>(sway, 0.0);
        let beadPhase = atan2(q.y, q.x) * 7.0 - time * 1.6 + fi * 2.39;
        let bead = pow(max(cos(beadPhase), 0.0), 24.0) * tent;
        beads += mix(tentColor, vec3<f32>(1.6, 1.5, 1.2), 0.6) * bead;
    }

    // === Ripple interaction ===
    var rippleInfluence = 0.0;
    for (var i = 0; i < 20; i++) {
        let r = u.ripples[i];
        // r.z is the click start time (r.w is always 0): strength decays with age
        let age = time - r.z;
        if (r.z > 0.0 && age >= 0.0 && age < 6.0) {
            let d = length(uv - r.xy);
            if (d < 0.35) {
                rippleInfluence += (0.35 - d) * exp(-age * 1.0) * 2.5;
            }
        }
    }

    // === [Idea 3] Crenulated breathing oral disc at the ring centre ===
    let discR = length(p);
    let discAng = atan2(p.y, p.x);
    let discEdge = (0.62 + 0.10 * cos(discAng * 11.0 - time * 0.5) + 0.03 * sin(discAng * 22.0 + time))
                   * (1.0 + 0.06 * sin(time * 1.3));
    let gullet = smoothstep(discEdge, discEdge - 0.4, discR);
    let lipD = (discR - discEdge) * 9.0;
    let lip = exp(-lipD * lipD);

    // === [Idea 2] Stokes-shift afterglow: emission history in C decays; residue is red-shifted ===
    let emitNow = min(tentacleEmission, 4.0);
    let decayed = cPrev.r * 0.985;
    let glowHist = max(emitNow, decayed);
    let afterglow = max(decayed - emitNow, 0.0);

    // === God rays from central anemone ===
    let rays = god_rays(uv, time, nebulaDensity * 1.4);

    // === Final composition (HDR) ===
    var hdr = vec3<f32>(prev.rgb) * 0.86;

    // Nebula glow (cool + warm mix)
    hdr += nebula * vec3<f32>(0.5, 0.25, 1.2) * 0.9;
    hdr += nebula2 * vec3<f32>(0.7, 0.4, 1.1) * 0.7;
    hdr += fog * mix(vec3<f32>(0.2, 0.5, 1.0), vec3<f32>(1.0, 0.5, 0.2), 0.4) * 0.6;

    // [Idea 1] beads, [Idea 2] amber afterglow, [Idea 3] oral disc
    hdr += beads * 0.35 * (0.5 + fluorescence) * (1.0 + audio * 0.5);
    hdr += vec3<f32>(1.5, 0.5, 0.18) * afterglow * 0.45 * (0.5 + fluorescence);
    hdr += gullet * vec3<f32>(0.45, 0.12, 0.8) * 0.45;
    hdr += lip * vec3<f32>(1.6, 0.9, 0.5) * 0.7 * (0.5 + fluorescence);

    // Quantum sparkles
    hdr += quantum * vec3<f32>(1.2, 0.9, 1.8) * 0.45;

    // Anemone tentacles with emission
    hdr += tentacleColor * 0.95;
    hdr += anemone * vec3<f32>(1.1, 0.5, 1.8) * 0.8;

    // Mouse attraction glow
    let mouseDist = length(uv - mouse);
    let mouseGlow = exp(-mouseDist * 12.0) * 1.5;
    hdr += vec3<f32>(1.2, 0.35, 2.0) * mouseGlow * fluorescence;

    // Ripple boost + god rays
    hdr += vec3<f32>(0.7, 0.25, 1.5) * rippleInfluence * 0.7;
    hdr += vec3<f32>(1.3, 1.0, 1.6) * rays * 0.55;

    // Audio reactivity boost (plasmaBuffer, scaled by the Audio Reactivity slider)
    hdr *= 1.0 + audio * 0.35;

    // Hue-preserving clamp before tonemap
    hdr = hue_preserving_clamp(hdr, 6.0);

    // ACES tone mapping
    let mapped = aces_tone_map(hdr);

    // IGN dither for banding-free gradients
    let dither = (ign_dither(vec2<f32>(gid.xy)) - 0.5) / 255.0;
    let finalColor = clamp(mapped + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Meaningful alpha: emission + density + occlusion
    let alpha = clamp(0.25 + tentacleEmission * 0.55 + nebula * 0.25 + fog * 0.15
                      + lip * 0.1 + afterglow * 0.1, 0.0, 1.0);
    let outColor = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, gid.xy, outColor);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * 0.5 + fog * 0.2, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(glowHist, fog, quantum, alpha));
}
