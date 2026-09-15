// ═══════════════════════════════════════════════════════════════════
//  Stellar-Acoustic Resonance-Manifold
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: coherent stellar p/g-mode shells; compression-antinode blackbody heating with traveling highlights
//  A packing: ACES display RGBA
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
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Audio Reactivity, .y = Plasma Density, .z = Orbital Speed, .w = Core Temperature
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    let r = q + dot(q, q.yxz + 33.33);
    return fract((r.x + r.y) * r.z);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3<f32>(0.0,0.0,0.0)), hash(i + vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0,1.0,0.0)), hash(i + vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(hash(i + vec3<f32>(0.0,0.0,1.0)), hash(i + vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0,1.0,1.0)), hash(i + vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>, amp: f32, scale: f32) -> f32 {
    var v = 0.0;
    var a = amp;
    var pp = p * scale;
    for(var i = 0; i < 4; i++) {
        v += a * noise(pp);
        pp = pp * 2.0;
        a *= 0.5;
    }
    return v;
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

// Basic blackbody family retained from the original shader.
fn blackbody(temp_in: f32) -> vec3<f32> {
    let temp = clamp(temp_in, 1000.0, 10000.0);
    let r = clamp(temp / 6000.0, 0.0, 1.0);
    let g = clamp((temp - 3000.0) / 4000.0, 0.0, 1.0);
    let b = clamp((temp - 5000.0) / 4000.0, 0.0, 1.0);
    return vec3<f32>(r, g, b);
}

// Returns distance, repeated-cell phase, acoustic pressure, and local radius.
fn stellarField(p_in: vec3<f32>, audio: vec3<f32>) -> vec4<f32> {
    var p = p_in;
    let time = u.config.x * u.zoom_params.z;

    let r_mat = rot(time * 0.2 + audio.x * 0.5);
    p = vec3<f32>(r_mat * p.xy, p.z);
    let r_mat2 = rot(time * 0.15);
    p = vec3<f32>(p.x, r_mat2 * p.yz);

    let spacing = 3.0;
    let cell = floor((p + spacing * 0.5) / spacing);
    p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;
    let cellPhase = hash(cell) * 2.0 * PI;

    let audio_reactivity = u.zoom_params.x;
    let noise_amp = 0.5 + audio.z * audio_reactivity * 0.5;
    let n = fbm(p + time, noise_amp, 1.5);

    let radius = 0.8 * u.zoom_params.y;
    let radialDistance = length(p);
    let safeRadius = max(radius, 0.08);
    let direction = p / max(radialDistance, 0.0001);
    let azimuth = atan2(direction.z, direction.x);
    let polar = acos(clamp(direction.y, -1.0, 1.0));

    // Idea 1 — stellar p/g-mode shells. Radial pressure nodes emboss nested
    // shells while angular gravity-mode sectors corrugate each repeated sphere.
    let radialOrder = 2.0 + floor(clamp(u.zoom_params.y, 0.1, 1.0) * 4.0);
    let pMode = cos((radialDistance / safeRadius) * PI * radialOrder
                  - time * (0.8 + audio.x * 0.8) + cellPhase);
    let gMode = cos(azimuth * 4.0 + cellPhase - time * 0.37)
              * sin(polar * 3.0 + time * 0.21);
    let acousticPressure = pMode * 0.62 + gMode * 0.38;
    let bandEnergy = dot(audio, vec3<f32>(0.5, 0.3, 0.2));
    let modeStrength = 0.045 + audio_reactivity * bandEnergy * 0.055;
    let surfaceEmboss = acousticPressure * modeStrength;

    let d = radialDistance - radius + n * 0.28 - surfaceEmboss;
    return vec4<f32>(d * 0.55, cellPhase, acousticPressure, radialDistance);
}

fn getNormal(p: vec3<f32>, audio: vec3<f32>) -> vec3<f32> {
    let e = 0.01;
    let x = stellarField(p + vec3<f32>(e, 0.0, 0.0), audio).x
          - stellarField(p - vec3<f32>(e, 0.0, 0.0), audio).x;
    let y = stellarField(p + vec3<f32>(0.0, e, 0.0), audio).x
          - stellarField(p - vec3<f32>(0.0, e, 0.0), audio).x;
    let z = stellarField(p + vec3<f32>(0.0, 0.0, e), audio).x
          - stellarField(p - vec3<f32>(0.0, 0.0, e), audio).x;
    return normalize(vec3<f32>(x, y, z) + vec3<f32>(0.00001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) {
        return;
    }

    let res = vec2<f32>(u.config.zw);
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(coord) - 0.5 * res) / max(res.y, 1.0);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let previous = textureLoad(dataTextureC, coord, 0);

    let mouse_pos = vec2<f32>(
        (u.zoom_config.y - 0.5) * (res.x / max(res.y, 1.0)),
        0.5 - u.zoom_config.z
    );
    let gravity_strength = 2.0;
    let dist_to_mouse = length(uv - mouse_pos);
    let distortion = 1.0 / (1.0 + dist_to_mouse * gravity_strength);

    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * u.zoom_params.z);
    var rd = normalize(vec3<f32>(uv, 1.0));
    rd = normalize(mix(rd, normalize(vec3<f32>(mouse_pos, 0.5) - ro), distortion * 0.5));

    var p = ro;
    var travel = 0.0;
    var minDistance = 100.0;
    var hit = false;
    for (var i = 0; i < 64; i = i + 1) {
        let field = stellarField(p, audio);
        let distance = field.x;
        minDistance = min(minDistance, abs(distance));
        if (distance < 0.01) {
            hit = true;
            break;
        }
        travel = travel + max(distance, 0.01);
        p = ro + rd * travel;
        if (travel > 20.0) {
            break;
        }
    }

    let surface = stellarField(p, audio);
    let pressure = surface.z;
    let glow = exp(-minDistance * 2.0);
    let base_temp = u.zoom_params.w;

    // Idea 2 — compression-antinode heating. Positive pressure heats the
    // blackbody emission and rarefaction cools it; the p/g phases travel
    // coherently, so hot highlights migrate across every repeated star.
    let acousticEnergy = dot(audio, vec3<f32>(0.5, 0.3, 0.2));
    let thermalSwing = (650.0 + u.zoom_params.x * acousticEnergy * 1350.0) * pressure;
    let em_temp = clamp(base_temp + thermalSwing + distortion * 450.0, 1000.0, 10000.0);
    let em_col = blackbody(em_temp);

    var hdr = vec3<f32>(0.01, 0.01, 0.05);
    hdr = hdr + em_col * glow * (0.35 + max(pressure, 0.0) * 0.35);
    if (hit) {
        let n = getNormal(p, audio);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let sss = fbm(p * 5.0, 1.0, 2.0) * 0.5 + 0.5;
        let compressionHighlight = smoothstep(0.15, 0.85, pressure);
        hdr = hdr + em_col * (diff * 0.2 + sss * 0.8) * 1.5;
        hdr = hdr + blackbody(min(em_temp + 1200.0, 10000.0))
            * compressionHighlight * (0.35 + audio.y * 0.3);
    }

    let mapped = acesToneMap(max(hdr, vec3<f32>(0.0)));
    let historyPresent = step(0.001, dot(abs(previous), vec4<f32>(1.0)));
    let displayRgb = mix(mapped, previous.rgb, historyPresent * 0.05);
    let hitCoverage = select(0.0, 0.58, hit);
    let alpha = clamp(
        hitCoverage + glow * 0.28 + max(pressure, 0.0) * select(0.0, 0.14, hit),
        0.0,
        1.0
    );
    let finalColor = vec4<f32>(displayRgb, alpha);
    let depth = select(1.0, clamp(travel / 20.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
