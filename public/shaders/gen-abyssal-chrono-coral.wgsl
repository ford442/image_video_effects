// ═══════════════════════════════════════════════════════════════════
//  Abyssal Chrono-Coral — Batch 63
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Deep-time coral growth accelerated into a fast abyssal current:
//  psychedelic bioluminescent spectra, polyp-level geometric detail,
//  cursor time-dilation well, held bloom, capped click sediment rings.
//  Upgraded: 2026-09-27
//  Ideas: growth-band strata carved along each branch (age faster in the well); gravitational red-shift in the well + blue Einstein-ring rim; travelling budding front swelling tip nodes
//  A packing: ACES display RGBA (prev.rgb*0.94 trail, read back as colour)
//  Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//            exact textureLoad from dataTextureC, plasmaBuffer three-band audio.
//            (The old extraBuffer[133..138] cursor spring was a no-op - the
//            buffer is zeroed every frame - and has been removed.)
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Coral Density, y=Branch Complexity, z=Bioluminescence Intensity, w=Time Dilation Field
    ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

var<private> g_bass: f32;
var<private> g_mids: f32;
var<private> g_treble: f32;
var<private> g_bloom: f32;
var<private> g_held: f32;
// IDEA 1/3 side channels written by map() for the surface shader:
// g_band.x = stratum height 0..1 (ledge -> taper), g_band.y = sharp ledge line; g_bud = budding-front strength 0..1
var<private> g_band: vec2<f32>;
var<private> g_bud: f32;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn fbm3(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var x = p;
    var a = 0.5;
    for(var i = 0; i < 4; i++) {
        let h = hash3(x);
        f += a * (h.x + h.y + h.z) / 3.0;
        x *= 2.0;
        a *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic abyssal spectrum — cyan/magenta wheel that spins with the audio
fn abyssPalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.6, 2.2 + drive * 1.1, 4.4 - drive * 0.7);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

// ═══ Gravitational lensing around dense coral mass ═══
fn gravitationalLensing(coralDist: f32, strength: f32) -> vec3<f32> {
    let lens = strength / (0.8 + coralDist * 2.0);
    return vec3<f32>(lens * 0.04, lens * 0.03, 0.0);
}

// ═══ Growth rings — deep time, now sped up by the current ═══
fn growthRings(p: vec3<f32>, t: f32, audioPulse: f32) -> f32 {
    let r = length(p);
    let ring = sin(r * 11.0 - t * 1.6 + audioPulse * 5.0) * 0.5 + 0.5;
    return ring * (0.3 + audioPulse * 0.4);
}

// ═══ Polyp micro-detail — fine corrugation carved onto every branch ═══
fn polypDetail(p: vec3<f32>, t: f32) -> f32 {
    let c = sin(p.x * 28.0 + t * 2.0) * sin(p.y * 28.0 - t * 1.7) * sin(p.z * 28.0 + t * 2.3);
    return c * 0.012;
}

// IDEA 1 - growth-band strata: sawtooth accretion ledges along the branch axis.
// Sharp step out at the ledge, slow taper back, phase running on the (well-dilated) clock.
fn strata(axis: f32, t: f32) -> vec3<f32> {
    let f = fract(axis * 1.6 - t * 0.28);
    let step_up = smoothstep(0.0, 0.08, f);
    let h = step_up * (1.0 - f);
    let line = exp(-f * 22.0);
    return vec3<f32>(h, line, h - 0.5);
}

fn map(pos_in: vec3<f32>, time: f32) -> vec2<f32> {
    var p = pos_in;
    g_band = vec2<f32>(0.5, 0.0);

    // Domain repetition
    p.x = (fract(p.x / 10.0 + 0.5) - 0.5) * 10.0;
    p.z = (fract(p.z / 10.0 + 0.5) - 0.5) * 10.0;

    // Domain warping — the abyssal current now runs several times faster
    let warpT = time * 1.1;
    p.x += (fbm3(p * 0.5 + warpT) - 0.5) * 2.0;
    p.y += (fbm3(p * 0.5 + warpT + 100.0) - 0.5) * 2.0;
    p.z += (fbm3(p * 0.5 + warpT + 200.0) - 0.5) * 2.0;

    let iterations = clamp(i32(u.zoom_params.y), 1, 8);
    var d = 1000.0;
    var s = 1.0;

    let audioPulse = g_mids * 0.6 + g_treble * 0.9 + g_bloom * 0.5;

    for(var i = 0; i < iterations; i++) {
        p = abs(p) - vec3<f32>(0.5, 1.5, 0.5);
        let rot_xy = rotate2D(0.5 + sin(time * 0.9) * 0.35) * p.xy;
        p.x = rot_xy.x;
        p.y = rot_xy.y;
        let rot_yz = rotate2D(0.3 + cos(time * 1.2) * 0.35) * p.yz;
        p.y = rot_yz.x;
        p.z = rot_yz.y;
        s *= 1.2;
        p *= 1.2;

        let ringMod = growthRings(p, time, audioPulse);
        // IDEA 1: radius steps out at each accretion ledge along this branch's own axis (p.y)
        let band = strata(p.y, time);
        let radius = u.zoom_params.x * (1.0 + g_bass * 0.4 + ringMod * 0.3) * (1.0 + 0.16 * band.z);
        var branch = (length(p.xz) - radius) / s;
        branch -= polypDetail(p, time) / s;
        if (branch < d) { g_band = band.xy; }
        d = smin(d, branch, 0.2);
    }

    // Bioluminescent nodes at tips
    // IDEA 3: budding front - a travelling wave along tip depth, sharp leading edge, slow decay
    let budPhase = fract(length(p) * 0.5 - time * 0.8);
    let bud = smoothstep(0.0, 0.15, budPhase) * (1.0 - smoothstep(0.15, 0.7, budPhase));
    g_bud = bud;
    let node_d = length(p) / s - (0.18 + audioPulse * 0.24 + g_held * 0.06) * (1.0 + 0.7 * bud);

    if (node_d < d) {
        return vec2<f32>(node_d, 2.0);
    }
    return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time).x - map(p - e.xyy, time).x,
        map(p + e.yxy, time).x - map(p - e.yxy, time).x,
        map(p + e.yyx, time).x - map(p - e.yyx, time).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.z, u.config.w);

    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

    let uv01 = vec2<f32>(coord) / resolution;
    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;
    let aspect = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
    let time = u.config.x;

    g_bass = plasmaBuffer[0].x;
    g_mids = plasmaBuffer[0].y;
    g_treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    let smoothMouse = mouse;

    // ── click sediment blooms — real ripple slots, capped and bounded ────
    var sediment = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.8) {
            let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.7);
            sediment = max(sediment, exp(-front * 24.0) * (1.0 - age / 1.8));
        }
    }
    sediment = min(sediment, 1.0);
    g_bloom = sediment + g_held * 0.35;

    // ── fast abyssal current + mouse time-dilation well ─────────────────
    let driftSpeed = 2.2 + g_bass * 2.4 + g_held * 1.4;
    let base_time = time * (1.4 + g_mids * 0.6);

    let dist_to_mouse = length((uv01 - smoothMouse) * aspect);
    let dilation_strength = max(u.zoom_params.w, 0.02);
    let well = smoothstep(dilation_strength, 0.0, dist_to_mouse);
    let dilation = well * 12.0 * (1.0 + g_held);
    let local_time = base_time + dilation;

    var ro = vec3<f32>(0.0, base_time * driftSpeed * 0.9, base_time * driftSpeed);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Camera bank — cursor steers it, current rolls it
    let steer = (smoothMouse - vec2<f32>(0.5)) * 0.8;
    let rd_xy = rotate2D(sin(base_time * 0.5) * 0.25 + steer.x * 0.6) * rd.xy;
    rd.x = rd_xy.x;
    rd.y = rd_xy.y;
    let rd_xz = rotate2D(cos(base_time * 0.35) * 0.25 - steer.y * 0.5) * rd.xz;
    rd.x = rd_xz.x;
    rd.z = rd_xz.y;
    rd = normalize(rd);

    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var acc_glow = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p, local_time);
        d = res.x;
        mat = res.y;

        // Gravitational lensing near coral mass bends the accumulated glow
        let lens = gravitationalLensing(d, u.zoom_params.x * 0.8 + sediment * 1.4);
        acc_glow += length(lens) * 0.02;

        if (d < 0.001) { break; }
        t += d * 0.48;

        if (mat == 2.0) {
            let pulse = g_mids * 0.7 + g_treble * 1.1 + sediment * 1.1;
            acc_glow += (0.012 + pulse * 0.008) / (0.01 + d * d) * u.zoom_params.z;
        }
        if (t > 22.0) { break; }
    }

    var col = vec3<f32>(0.0);
    var fres = 0.0;

    if (t < 22.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, local_time);
        // refresh the strata / bud side channels at the exact hit point (calcNormal leaves them at an offset probe)
        _ = map(p, local_time);
        let strat = g_band;
        let bud = g_bud;
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        fres = pow(max(1.0 - max(dot(n, -rd), 0.0), 0.0), 3.0);

        // Hue races along the branch with treble and the sediment bloom
        let hue = fract(length(p) * 0.12 + time * (0.25 + g_treble * 0.8) + sediment * 0.5);

        if (mat == 1.0) {
            let ring = growthRings(p, local_time, g_mids * 0.6);
            let sss = smoothstep(0.0, 1.0, map(p + l * 0.1, local_time).x);
            let branchTint = abyssPalette(hue, g_mids * 1.3);
            col = branchTint * diff * 0.5
                + branchTint * sss * 0.85
                + fres * abyssPalette(hue + 0.25, g_treble) * 1.1
                + ring * abyssPalette(hue + 0.5, g_bass) * 0.5;
            // Corrugation shading — makes the polyp micro-detail read as geometry
            let corr = 0.5 + 0.5 * sin(dot(p, vec3<f32>(28.0)) + time * 2.0);
            col *= 0.8 + corr * 0.4;
            // IDEA 1 shading: each stratum is lighter on its ledge, and the ledge line glows
            col *= 0.78 + 0.44 * strat.x;
            col += strat.y * abyssPalette(hue + 0.3, g_mids) * 0.3 * (0.5 + well);
        } else {
            let bloomAmt = 1.6 + (g_mids + g_treble) * 1.5 + sediment * 2.2;
            // IDEA 3: a swelling bud burns hotter
            col = abyssPalette(hue + 0.15, 1.0 + g_bass) * bloomAmt * (1.0 + 0.6 * bud)
                + abyssPalette(hue + 0.6, g_treble) * fres * 0.9;
        }
    } else {
        let stars = pow(hash3(rd * 110.0).x, 48.0);
        col += stars * vec3<f32>(0.9, 0.95, 1.0);
        col += abyssPalette(time * 0.05 + length(uv) * 0.3, g_mids) * 0.03;
    }

    // Volumetric glow — spectral, stronger during bloom events
    col += acc_glow * abyssPalette(time * 0.3 + acc_glow * 0.2, g_treble * 1.4) * (1.0 + sediment);

    // Cursor bloom halo
    let cursorGlow = exp(-dist_to_mouse * 8.0) * (0.15 + g_held * 0.5);
    col += abyssPalette(time * 0.6, g_bass) * cursorGlow;

    // Ambient abyssal fog
    col = mix(col, vec3<f32>(0.0, 0.04, 0.09), 1.0 - exp(-0.018 * t));

    // IDEA 2: gravitational shift. Light climbing out of the well is red-shifted (spectral matrix,
    // not a palette swap); a thin blue-shifted Einstein ring sits at the well rim and brightens
    // where coral / glow lies behind it. Uses the saved well radius (Time Dilation Field).
    let pre_luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let redshift = vec3<f32>(
        col.r + 0.55 * col.g + 0.15 * col.b,
        0.45 * col.g + 0.10 * col.b,
        0.15 * col.b);
    col = mix(col, redshift * 1.1, well * 0.75);
    let rim_w = 0.006 + 0.03 * dilation_strength;
    let rim_d = (dist_to_mouse - dilation_strength * 0.9) / rim_w;
    let einstein = exp(-rim_d * rim_d);
    let blueshift = vec3<f32>(0.25 * col.r, 0.6 * col.g + 0.2 * col.r, col.b + 0.5 * col.g);
    col = mix(col, blueshift, einstein * 0.5);
    col += einstein * vec3<f32>(0.4, 0.75, 1.5) * (0.10 + 0.35 * min(acc_glow, 1.5) + 0.3 * pre_luma) * (1.0 + g_held * 0.5);

    col *= 1.0 + g_bass * 0.22 + sediment * 0.8;

    col = acesToneMap(col * (1.05 + g_mids * 0.2));

    // Semantic alpha: bioluminescent intensity + surface presence
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let bioIntensity = min(acc_glow, 2.0) * 0.4 + (g_mids + g_treble) * 0.3;
    let alpha = clamp(
        select(0.0, 0.4 + fres * 0.3, t < 22.0)
        + luma * 0.45 + bioIntensity * 0.35 + sediment * 0.3,
        0.0, 1.0);

    let prev = textureLoad(dataTextureC, coord, 0);
    let temporal = mix(prev.rgb * 0.94, col, 0.3 + g_bass * 0.1);
    textureStore(dataTextureA, coord, vec4<f32>(temporal, alpha));

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));

    let rawDepth = textureLoad(readDepthTexture, coord, 0).r;
    let depth = mix(rawDepth, clamp(t / 22.0, 0.0, 1.0), 0.75);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth, 0.0, 1.0), 0.0, 0.0, 0.0));
}
