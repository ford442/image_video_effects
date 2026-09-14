// ═══════════════════════════════════════════════════════════════════
//  Luminescent Quantum-Silicate Diatom
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: hexagonal areolae pore lattice pitted into each frustule valve face; thin-film valve-thickness interference (2·n·d·cosθ) colouring the silica
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
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Pore Density, .y = Pulse Speed, .z = Iridescence Spread, .w = Bioluminescence Shift
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
  let p2 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.6))
  );
  return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn simplex3d(p: vec3<f32>) -> f32 {
  let K1 = 0.333333333;
  let K2 = 0.166666667;
  let i = floor(p + vec3<f32>((p.x + p.y + p.z) * K1));
  let d0 = p - (i - vec3<f32>((i.x + i.y + i.z) * K2));

  var e = vec3<f32>(step(d0.yzx, d0.xyz));
  let j1 = e * (vec3<f32>(1.0) - e.zxy);
  let j2 = vec3<f32>(1.0) - e.zxy * (vec3<f32>(1.0) - e);

  let d1 = d0 - (j1 - vec3<f32>(K2));
  let d2 = d0 - (j2 - vec3<f32>(K2 * 2.0));
  let d3 = d0 - (vec3<f32>(1.0 - K2 * 3.0));

  var w = max(vec4<f32>(0.6) - vec4<f32>(dot(d0, d0), dot(d1, d1), dot(d2, d2), dot(d3, d3)), vec4<f32>(0.0));
  w = w * w;
  w = w * w;

  let d = vec4<f32>(
    dot(d0, hash33(i)),
    dot(d1, hash33(i + j1)),
    dot(d2, hash33(i + j2)),
    dot(d3, hash33(i + vec3<f32>(1.0)))
  );

  return dot(w, d) * 31.316;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn modv2(p: vec2<f32>, s: vec2<f32>) -> vec2<f32> {
  return p - s * floor(p / s);
}

// Warp (mouse gravity well) + lattice fold into a single frustule cell.
fn frustuleLocal(p: vec3<f32>, mouse_pos: vec3<f32>) -> vec3<f32> {
    var pos = p;
    let dist_to_mouse = length(pos - mouse_pos);
    let strength = 0.5 * u.zoom_config.w; // active on click/drag
    pos += normalize(pos - mouse_pos + vec3<f32>(1e-4)) * (strength / (dist_to_mouse + 0.1));
    let spacing = vec3<f32>(4.0);
    return pos - spacing * round(pos / spacing);
}

// Native idea 1: hexagonal areolae — the regular pore chambers of a diatom valve.
// Each octahedral face is flattened to a 2D plane orthogonal to (1,1,1) and tiled
// with a hex lattice; returns 1 at an areola centre, 0 on the silica ribs between.
fn areolae(pos: vec3<f32>, poreDensity: f32) -> f32 {
    let a = abs(pos);
    let face = vec2<f32>((a.x - a.y) * 0.70710678, (a.x + a.y - 2.0 * a.z) * 0.40824829);
    let freq = 2.5 + poreDensity * 7.0;
    let hp = face * freq;
    let s = vec2<f32>(1.0, 1.7320508);
    let h = s * 0.5;
    let c0 = modv2(hp, s) - h;
    let c1 = modv2(hp - h, s) - h;
    let hexDist = min(length(c0), length(c1));
    return smoothstep(0.36, 0.12, hexDist);
}

fn map(p: vec3<f32>, mouse_pos: vec3<f32>) -> vec2<f32> {
    // Mouse Interaction: micro-cellular gravity well + domain folding for lattice
    let pos = frustuleLocal(p, mouse_pos);

    // Base shape: Octahedron
    var s = abs(pos.x) + abs(pos.y) + abs(pos.z) - 1.5;

    // High-frequency noise for pores (Pore Density mapped to u.zoom_params.x)
    let pore_density = u.zoom_params.x * 5.0 + 1.0;
    let pores = simplex3d(pos * pore_density) * 0.3;
    s += pores;

    // Areolae pits only bite near the valve surface (keeps the field well-behaved).
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let shellBand = smoothstep(0.6, 0.0, abs(s));
    s += areolae(pos, u.zoom_params.x) * shellBand * (0.12 + bass * 0.05);

    return vec2<f32>(s * 0.5, 1.0); // ID 1.0 for shell
}

fn get_normal(p: vec3<f32>, mouse_pos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, mouse_pos).x - map(p - e.xyy, mouse_pos).x,
        map(p + e.yxy, mouse_pos).x - map(p - e.yxy, mouse_pos).x,
        map(p + e.yyx, mouse_pos).x - map(p - e.yyx, mouse_pos).x
    );
    return normalize(n);
}

// Native idea 2: thin-film interference in the frustule valve. Silica (n≈1.43) of
// thickness d gives optical path 2·n·d·cosθt; each wavelength reinforces/cancels.
// Valve is thinner inside areolae and thicker on the ribs, so the pore lattice
// shows up as interference fringes.
fn valveInterference(n: vec3<f32>, v: vec3<f32>, areola: f32, noiseT: f32, spread: f32, treble: f32) -> vec3<f32> {
    let cosI = max(dot(n, v), 0.0);
    let nSilica = 1.43;
    let sinT2 = (1.0 - cosI * cosI) / (nSilica * nSilica);
    let cosT = sqrt(max(1.0 - sinT2, 0.0));
    let thicknessNm = 180.0 + (1.0 - areola) * (220.0 + spread * 520.0) + noiseT * 90.0 + treble * 40.0;
    let opd = 2.0 * nSilica * thicknessNm * cosT;
    let lambda = vec3<f32>(650.0, 530.0, 450.0);
    return 0.5 + 0.5 * cos(TAU * opd / lambda + vec3<f32>(TAU * 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(f32(global_id.x), f32(global_id.y)) / resolution;
    let aspect = resolution.x / resolution.y;
    let cuv = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    let time = u.config.x * u.zoom_params.y; // Pulse Speed mapped to u.zoom_params.y

    // Audio reactivity (plasmaBuffer)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let audio_val = 0.35 + bass * 0.45 + mids * 0.2;

    let mouse_uv = u.zoom_config.yz;
    let cmouse = (mouse_uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let mouse_pos = vec3<f32>(cmouse * 5.0, 0.0);

    var ro = vec3<f32>(0.0, 0.0, -5.0 + time * 0.5);
    var rd = normalize(vec3<f32>(cuv, 1.5));

    // Camera rotation
    ro = vec3<f32>(rot(time * 0.2) * ro.xy, ro.z);
    rd = vec3<f32>(rot(time * 0.2) * rd.xy, rd.z);

    var t = 0.0;
    var d = 0.0;
    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    var hit = false;

    var vol_acc = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p, mouse_pos);
        d = res.x;

        // Volumetric accumulation for cytoplasm
        if (d > 0.0) {
           let cyto_noise = simplex3d(p * 2.0 - vec3<f32>(0.0, 0.0, time * 2.0)) * 0.5 + 0.5;
           let emissive = smoothstep(0.4, 0.6, cyto_noise) * 0.02 * (1.0 + audio_val * 2.0 + mids * 0.5);
           vol_acc += emissive;
        }

        if (d < 0.01) {
            hit = true;
            let n = get_normal(p, mouse_pos);
            let v = -rd;

            // Fresnel for iridescence
            let f = pow(1.0 - max(dot(n, v), 0.0), 3.0);

            // Chromatic aberration gradient based on iridescence spread
            let spread = u.zoom_params.z;
            var iridescent_col = vec3<f32>(
                sin(f * 10.0 * spread),
                sin(f * 12.0 * spread + 2.0),
                sin(f * 14.0 * spread + 4.0)
            ) * 0.5 + 0.5;

            // Thin-film valve interference driven by the areolae lattice
            let local = frustuleLocal(p, mouse_pos);
            let areola = areolae(local, u.zoom_params.x);
            let noiseT = simplex3d(local * 1.7);
            let film = valveInterference(n, v, areola, noiseT, spread, treble);
            iridescent_col = mix(iridescent_col, film, 0.65);

            // Bioluminescence shift
            let shift = u.zoom_params.w;
            let bio_col = vec3<f32>(0.0, 1.0 - shift, shift + 0.2) * 2.0;

            col += (iridescent_col * 0.5 + bio_col * audio_val) * (1.0 - f);
            // Light leaking through the open pores from the living cytoplasm behind
            col += bio_col * areola * 0.12 * (1.0 + bass * 0.4);

            // Inner cytoplasm emission added
            col += bio_col * vol_acc;
            alpha = clamp(0.55 + (1.0 - f) * 0.35 + (1.0 - areola) * 0.1, 0.0, 1.0);
            break;
        }

        t += d;
        if (t > 20.0) {
            col += vec3<f32>(0.0, 0.1, 0.2) * vol_acc * u.zoom_params.w;
            break;
        }
    }

    if (!hit) {
        alpha = clamp(vol_acc * 0.6, 0.0, 0.6);
    }

    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), smoothstep(10.0, 20.0, t));

    // Click ripples: silica-deposition rings expanding across the valve lattice
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r++) {
        let rp = u.ripples[r];
        let age = u.config.x - rp.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rc = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
        let rd2 = length(cuv - rc);
        let ring = exp(-pow((rd2 - age * 0.9) * 14.0, 2.0)) * (1.0 - age / 3.0);
        let shift = u.zoom_params.w;
        col += vec3<f32>(0.2, 1.0 - shift * 0.6, 0.5 + shift) * ring * 0.35;
        alpha = max(alpha, ring * 0.5);
    }

    // Soft bloom post-processing approximation
    col += col * 0.2 * audio_val;

    // Exact temporal feedback from C (mild cytoplasm afterglow)
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let prevCoord = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
    let previous = textureLoad(dataTextureC, prevCoord, 0);
    col = mix(col, previous.rgb * 0.92, 0.05 + mids * 0.03);

    col = acesToneMap(col * (1.0 + bass * 0.2));
    let finalAlpha = clamp(alpha + previous.a * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(col, finalAlpha);

    var depth = 0.0;
    if (hit) {
        depth = clamp(1.0 - t / 20.0, 0.0, 1.0);
    }

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
