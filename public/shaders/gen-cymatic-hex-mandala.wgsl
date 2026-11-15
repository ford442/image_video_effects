// ═══════════════════════════════════════════════════════════════════
//  gen-cymatic-hex-mandala
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, cymatic-hex, upgraded-rgba
//  Complexity: Medium
//  Chunks From: hexGrid, standingWave, bass_env, ign
//  Created: 2026-07-17
//  By: weekly swarm Batch 15
//  Upgraded: 2026-11-15
//  Ideas: hex-symmetric modal wave (m=6 circular-plate mode, Hankel-phase J6, native); Chladni sand collecting on the nodal lines (history A.a, native); true hexagonal lattice (rescue)
//  A packing: A.rgb = pre-ACES colour trail (as before), A.a = Chladni sand density (raw scalar; was an unused bass copy); ACES display + straight semantic alpha premultiplied into RGB (catalog gen convention)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
const PI: f32 = 3.14159265359;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
// ── Rescue 1: true hexagonal lattice ───────────────────────────────────
// HEAD split each axial parallelogram into two triangles and measured the "edge" in the skewed frame (its axial y
// coefficient was 2/sqrt(3) where flat-top hexes need sqrt(3)/3), so the lattice drew skewed checker tiles. This is the standard two-interleaved-lattice form: the
// nearest of two rectangular-lattice centres wins, which tiles the plane with regular (pointy-top) hexagons. Float `%`
// is truncated in WGSL, so the periodic fold uses floor. z = hex distance from the cell centre: 0 at the centre, 0.5 at the edge.
fn hexCoords(p: vec2<f32>) -> vec3<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = p - r * floor(p / r) - h;
    let q = p - h;
    let b = q - r * floor(q / r) - h;
    let gv = select(b, a, dot(a, a) < dot(b, b));
    let hp = abs(gv);
    let hd = max(dot(hp, vec2<f32>(0.5, 0.8660254)), hp.x);
    let id = p - gv;
    return vec3<f32>(id.x, id.y, hd);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    // plasmaBuffer[0] is already the host-smoothed band; a shared extraBuffer[0] envelope
    // raced across invocations and was re-uploaded each frame.
    let bassEnv = bass;

    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 1.5;
    let ruv = uv - mouse * 0.15;
    let scale = mix(5.0, 11.0, p1);
    let hex = hexCoords(ruv * scale * 0.6);
    let cellId = vec2<f32>(hex.x, hex.y);
    let edge = 1.0 - smoothstep(0.38, 0.42, hex.z);

    let dist = length(ruv);
    let freq = 3.0 + mids * 5.0 + p2 * 4.0;
    let ampl = 0.35 + bassEnv * 0.45;
    let kr = max(dist * freq * TAU, 0.001);
    let radialWave = sin(kr - time * (1.2 + p3 * 1.5));

    // ── Idea 1: hex-symmetric modal wave (native; Bessel, docs/WOLFRAM_SHADER_DATA.md) ──
    // A vibrating circular plate does not carry one travelling ring, it carries MODES J_m(k r) cos(m theta). The hex lattice
    // fixes m = 6. J_m(x) ~ sqrt(2/(pi x)) cos(x - m pi/2 - pi/4 + (4m^2-1)/(8x)): the amplitude falloff is already the
    // file's exp(-dist) envelope, so only the phase is kept; the (4m^2-1)/(8x) Hankel term is what makes the m=6 nodal
    // circles scallop against the m=0 ones. Core fade because J_6 vanishes at the centre. Rings stay (radialWave untouched).
    let theta = atan2(ruv.y, ruv.x + 0.000001);
    let phase0 = kr - 0.7853982;
    let phase6 = kr - 3.0 * PI - 0.7853982 + 17.875 / max(kr, 4.0);
    let core6 = smoothstep(3.0, 10.0, kr);
    let petals = cos(6.0 * theta + time * 0.12);
    let modal6 = core6 * cos(phase6) * petals;
    let wave = ampl * (radialWave + 0.7 * modal6 * cos(time * 0.9));
    let ring = abs(wave) * exp(-dist * (1.2 - bassEnv * 0.3));

    // Standing figure (the plate's static m=0 + m=6 mode) — its zero set is where sand collects.
    let standing = cos(phase0) + 0.9 * modal6;
    let nodeSpark = hash21(cellId + fract(time * 0.2)) * treble * edge;

    let hue = fract(theta / TAU + 0.5 + mids * 0.25 + time * 0.02);
    var col = vec3<f32>(0.01, 0.015, 0.025);
    let palette = mix(vec3<f32>(0.2, 0.75, 1.0), vec3<f32>(1.0, 0.45, 0.85), hue);
    col += palette * ring * (0.55 + p3 * 0.35);
    col += vec3<f32>(0.9, 0.95, 1.0) * edge * (0.15 + mids * 0.2);
    col += vec3<f32>(1.0, 0.98, 0.75) * nodeSpark * 0.8;

    // Rescue 2: exact load for history (HEAD sampled the rgba32float C with the filtering sampler).
    let prevState = textureLoad(dataTextureC, pixel, 0);
    let prev = prevState.rgb;
    col = mix(prev * (0.9 - p4 * 0.1), col, 0.28 + p4 * 0.18);

    // ── Idea 2: Chladni sand (native) ──────────────────────────────────
    // Sand on a driven plate is shaken off the antinodes and collects on the nodal lines, where the figure is ~0. The
    // colour trail above is untouched; the sand lives in the history's alpha (raw scalar). trail_persistence keeps its
    // role and also sets how long grains stay put; bass shakes harder (faster collection).
    let nodal = 1.0 - smoothstep(0.0, 0.22, abs(standing));
    let antinode = smoothstep(0.55, 1.3, abs(standing));
    let sand = clamp(prevState.a * (0.90 + 0.08 * p4) * (1.0 - 0.25 * antinode) + nodal * 0.10 * (0.7 + bassEnv * 0.8), 0.0, 1.0);
    textureStore(dataTextureA, pixel, vec4<f32>(col, sand));
    col += vec3<f32>(1.0, 0.9, 0.7) * sand * 0.8;

    col *= mix(1.0, 0.55, depth);
    col = hue_preserve_clamp(col, 1.2);
    col = aces(max(col, vec3<f32>(0.0)) * (0.92 + bassEnv * 0.22));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    let density = ring * 0.6 + edge * 0.25 + nodeSpark * 0.15 + sand * 0.3;
    let alpha = clamp(density * (0.55 + bassEnv * 0.35) * (1.0 - depth * 0.35), 0.1, 0.92);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
