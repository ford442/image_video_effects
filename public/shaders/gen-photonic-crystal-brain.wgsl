// ═══════════════════════════════════════════════════════════════════
//  Photonic Crystal-Brain
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Bragg-reflection structural color (lambda = 2 n d cos theta from lattice spacing); line-defect waveguide spikes (photon packets travelling along sparse firing rods)
//  A packing: ACES display RGBA in A (C unused)
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
    zoom_params: vec4<f32>,  // .x = Intensity, .y = Speed, .z = Scale, .w = Mouse Influence
    ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

// --- Color Science: OkLab ---
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        vec3<f32>(0.8189330101, 0.3618667424, -0.1288597137),
        vec3<f32>(0.0329845436, 0.9293118715, 0.0361456387),
        vec3<f32>(0.0482003018, 0.2643662691, 0.6338517070)
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0/3.0));
    return mat3x3<f32>(
        vec3<f32>(0.2104542553, 1.9779984951, 0.0259040371),
        vec3<f32>(0.7936177850, -2.4285922050, 0.7827717662),
        vec3<f32>(-0.0040720468, 0.4505937099, -0.8086757660)
    ) * lms_;
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.3963377774, -0.1055613458, -0.0894841775),
        vec3<f32>(0.2158037573, -0.0638541728, -1.2914855480)
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        vec3<f32>(1.2270138510, -0.5577992887, 0.2812561490),
        vec3<f32>(-0.0405801784, 1.1122568696, -0.0716766787),
        vec3<f32>(-0.0763812845, -0.4214819784, 1.5861632204)
    ) * lms;
}
fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear(mix(linear_to_oklab(a), linear_to_oklab(b), t));
}

// --- Blackbody Color Temperature ---
fn blackbody(t: f32) -> vec3<f32> {
    var col = vec3<f32>(1.0);
    col.y = 0.3900815787690196 * log(t) - 0.6318414437886275;
    col.z = 0.5432067891101961 * log(t) - 1.1964741063266880;
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    return col;
}

// --- Cosine Palette (Inigo Quilez) ---
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// --- HDR Tone Mapping (ACES-inspired) ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51);
    let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43);
    let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle); let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}
fn crystalSpacing() -> f32 {
    return 4.0 / max(u.zoom_params.x, 0.05);
}
// Lattice-space warp shared by the SDF and the waveguide spikes.
fn crystalWarp(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    // Mouse Y-flip: screen-top (zoom_config.z=0) = +Y/up
    let mx = (u.zoom_config.y * 2.0 - 1.0) * 5.0;
    let my = (u.zoom_config.z * 2.0 - 1.0) * 5.0;
    let mousePos = vec3<f32>(mx, my, p.z);
    let distToMouse = length(p - mousePos);
    let pull = exp(-distToMouse * 0.5) * 2.0;
    // Mouse Influence (w): default 0.5 == old 0.2 pull; holding the mouse draws the lattice in harder
    let held = step(0.5, u.zoom_config.w);
    let pullGain = 0.4 * u.zoom_params.w * (1.0 + held * 1.2);
    p = mix(p, mousePos, clamp(pull * pullGain, 0.0, 0.9));
    let distortion = u.zoom_params.z;
    p.x += sin(p.y * 2.0 + u.config.x) * 0.1 * distortion;
    p.y += cos(p.x * 2.0 + u.config.x) * 0.1 * distortion;
    return p;
}
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = crystalWarp(p_in);
    let distortion = u.zoom_params.z;
    let spacing = crystalSpacing();
    let id = floor(p / spacing);
    p = fract(p / spacing) * spacing - spacing * 0.5;
    let cylX = length(p.yz) - 0.1;
    let cylY = length(p.xz) - 0.1;
    let cylZ = length(p.xy) - 0.1;
    var d = smin(cylX, cylY, 0.3);
    d = smin(d, cylZ, 0.3);
    let sphere = length(p) - 0.3;
    d = smin(d, sphere, 0.4);
    let h = hash3(id);
    let disp = sin(p.x * 10.0) * cos(p.y * 10.0) * sin(p.z * 10.0) * 0.05 * distortion;
    d += disp;
    return vec2<f32>(d, h.x);
}
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}
// Idea 1: Bragg reflection in a photonic crystal. Reflected peak wavelength
// lambda = 2 * n_eff * d * cos(theta); d follows the lattice spacing slider.
// Outside the visible band the stop-band leaves the eye -> no structural color.
fn spectralRGB(lambdaNm: f32) -> vec3<f32> {
    let x = (lambdaNm - 380.0) / 400.0;
    let r = exp(-pow((x - 0.78) / 0.16, 2.0)) + 0.35 * exp(-pow((x - 0.08) / 0.08, 2.0));
    let g = exp(-pow((x - 0.47) / 0.15, 2.0));
    let b = exp(-pow((x - 0.18) / 0.13, 2.0));
    let vis = smoothstep(0.0, 0.05, x) * (1.0 - smoothstep(0.95, 1.0, x));
    return vec3<f32>(r, g, b) * vis;
}
fn braggStructuralColor(cosTheta: f32, spacing: f32, bass: f32) -> vec3<f32> {
    let nEff = 1.45;
    let dNm = 260.0 * clamp(spacing / 8.0, 0.35, 2.5) * (1.0 + bass * 0.04);
    let lam1 = 2.0 * nEff * dNm * cosTheta;       // first order
    let lam2 = lam1 * 0.5;                        // second order
    return spectralRGB(lam1) + spectralRGB(lam2) * 0.5;
}

// Idea 2: line-defect waveguides. Sparse hashed cells carry a photon packet
// travelling along one of their three rods (a firing axon). Returns glow.
fn waveguideSpike(p: vec3<f32>, t: f32, mids: f32) -> f32 {
    let wp = crystalWarp(p);
    let spacing = crystalSpacing();
    let cid = floor(wp / spacing);
    let q = fract(wp / spacing) * spacing - spacing * 0.5;
    let h = hash3(cid + vec3<f32>(7.13, 1.71, 3.37));
    if (h.y < 0.55) { return 0.0; }
    let axis = i32(floor(h.x * 2.999));
    var along = q.x;
    var radial = length(q.yz);
    if (axis == 1) { along = q.y; radial = length(q.xz); }
    if (axis == 2) { along = q.z; radial = length(q.xy); }
    let a01 = along / spacing + 0.5;
    let phase = fract(t * (0.25 + mids * 0.5) * (0.6 + h.z) + h.x * 5.0);
    let dir = select(a01, 1.0 - a01, h.z > 0.5);
    let packet = exp(-pow((dir - phase) * 10.0, 2.0));
    return packet * 0.004 / (radial * radial + 0.004);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(id.xy);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(id.xy) - res * 0.5) / res.y;
    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let rotX = rotate2D(sin(u.config.x * 0.2) * 0.1);
    let rotY = rotate2D(cos(u.config.x * 0.3) * 0.1);
    let rdYZ = rotX * vec2<f32>(rd.y, rd.z); rd.y = rdYZ.x; rd.z = rdYZ.y;
    let rdXZ = rotY * vec2<f32>(rd.x, rd.z); rd.x = rdXZ.x; rd.z = rdXZ.y;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let screenUV = vec2<f32>(id.xy) / res;
    let spikeCol = vec3<f32>(0.55, 0.85, 1.0);
    // Click ripples: action-potential shells expanding through the lattice (world XY, same map as mouse)
    let nRip = min(u32(u.config.y), 50u);
    var t = 0.0; var d = 0.0; var m = 0.0; var glow = vec3<f32>(0.0);
    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let res_map = map(p);
        d = res_map.x; m = res_map.y;
        // Glow was plasma-bass-only (black at silence); now a floor + bass gain keeps sliders live
        let audioPulse = 0.25 + bass * 0.35;
        let pulseSpeed = u.zoom_params.y;
        let glowIntens = u.zoom_params.w;
        let pulse = sin(p.z * 2.0 - u.config.x * 5.0 * pulseSpeed) * 0.5 + 0.5;
        // Cosine palette + OkLab mixing for glow colors
        let cp1 = cosinePalette(m + sin(u.config.x), vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5), vec3<f32>(1.0,1.0,0.8), vec3<f32>(0.0,0.33,0.67));
        let cp2 = cosinePalette(m + sin(u.config.x) + 0.3, vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.8,1.0,1.0), vec3<f32>(0.2,0.5,0.8));
        let glowColor = oklab_mix(cp1, cp2, 0.5 + 0.5 * sin(u.config.x * 0.5));
        glow += glowColor * (0.01 / (d * d + 0.01)) * pulse * audioPulse * glowIntens;
        if (d < 0.3) {
            glow += spikeCol * waveguideSpike(p, u.config.x, mids) * 0.35 * (0.5 + glowIntens) * (1.0 + treble * 0.3);
            var fire = 0.0;
            for (var r = 0u; r < nRip; r++) {
                let rip = u.ripples[r];
                let age = u.config.x - rip.z;
                if (age <= 0.0 || age > 3.0) { continue; }
                let rc = vec2<f32>((rip.x * 2.0 - 1.0) * 5.0, (rip.y * 2.0 - 1.0) * 5.0);
                let shell = length(p.xy - rc) - age * 4.0;
                fire += exp(-shell * shell * 3.0) * (1.0 - age / 3.0);
            }
            glow += vec3<f32>(1.0, 0.75, 0.45) * min(fire, 2.0) * (0.01 / (d * d + 0.01)) * 0.15;
        }
        if (d < 0.001 || t > 20.0) { break; }
        t += d * 0.5;
    }
    var col = vec3<f32>(0.0);
    var coverage = 0.0;
    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(reflect(rd, n), l), 0.0), 32.0);
        // Fresnel rim lighting with OkLab mixing
        let fresnel = pow(1.0 + dot(rd, n), 4.0);
        let bbTemp = mix(3000.0, 9000.0, m);
        let bbCol = blackbody(bbTemp) * 0.8;
        col = vec3<f32>(0.05) + bbCol * diff;
        col += spec * vec3<f32>(1.0);
        // Multi-layer Fresnel rim with cosine palette
        let rimPalette = cosinePalette(m + u.config.x * 0.1, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0,0.8,0.6), vec3<f32>(0.0,0.33,0.67));
        col += fresnel * oklab_mix(rimPalette, vec3<f32>(0.5,0.8,1.0), 0.5) * 0.5;
        // Bragg stop-band structural color (idea 1)
        let cosTheta = clamp(abs(dot(rd, n)), 0.0, 1.0);
        col += braggStructuralColor(cosTheta, crystalSpacing(), bass) * (0.22 + treble * 0.18) * (0.4 + 0.6 * diff);
        // Ambient occlusion approximation
        let ao = exp(-t * 0.15);
        col *= ao;
        // Secondary bounce light from glow
        col += glow * 0.3 * (1.0 - ao);
        coverage = ao;
    }
    col += glow;
    // HDR fog with tone mapping
    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), 1.0 - exp(-t * 0.1));
    // Mouse held: stimulated region brightens (synaptic excitation)
    let held = step(0.5, u.zoom_config.w);
    let mDist = length(screenUV - u.zoom_config.yz);
    col += vec3<f32>(0.35, 0.6, 1.0) * held * exp(-mDist * mDist * 40.0) * 0.25 * (1.0 + bass * 0.4);
    col = acesToneMap(col);
    // Semantic alpha: crystal coverage (fogged by distance) + synaptic glow density
    let glowDensity = clamp(dot(glow, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let _alpha = clamp(0.1 + coverage * 0.6 + glowDensity * 0.5, 0.0, 1.0);
    let controlled = applyGenerativePrimaryControls(vec4<f32>(col, _alpha));
    let finalColor = vec4<f32>(clamp(controlled.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), controlled.a);
    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
    // Raymarched depth (near = 1)
    let _depth = clamp(1.0 - t / 20.0, 0.0, 1.0);
    textureStore(writeDepthTexture, coords, vec4<f32>(_depth, 0.0, 0.0, 0.0));
}
