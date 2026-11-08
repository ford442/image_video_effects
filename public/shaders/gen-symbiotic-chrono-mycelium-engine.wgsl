// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Chrono-Mycelium Engine
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13, 2026-11-08
//  Ideas: hyphal wrapping around the gear; chrono lag vs gear rotation; golden-angle fruiting primordia (§12.2E); cytoplasmic streaming pulses along the stalk; twisted three-strand rhizomorph cord (§12.2E)
//  A packing: ACES display RGBA (C unused)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Mycelial Density, y=Plasma Glow, z=Temporal Warp, w=Mouse Influence

const PI: f32 = 3.14159265359;
const GOLDEN_ANGLE: f32 = 2.39996323;
const BUD_PITCH: f32 = 0.55;        // vertical spacing of the primordia along the stalk
const CORD_TWIST: f32 = 4.5;        // radians of strand twist per unit of stalk height

fn rotate3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let ic = 1.0 - c;
    let a = normalize(axis);
    return mat3x3<f32>(
        vec3<f32>(a.x * a.x * ic + c, a.y * a.x * ic - a.z * s, a.z * a.x * ic + a.y * s),
        vec3<f32>(a.x * a.y * ic + a.z * s, a.y * a.y * ic + c, a.z * a.y * ic - a.x * s),
        vec3<f32>(a.x * a.z * ic - a.y * s, a.y * a.z * ic + a.x * s, a.z * a.z * ic + c)
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += sin(pos.x + sin(pos.y + sin(pos.z))) * amp;
        pos *= 2.0;
        amp *= 0.5;
    }
    return v;
}

fn sdf_gear(p: vec3<f32>) -> f32 {
    var pos = p;
    pos = rotate3D(vec3<f32>(0.0, 1.0, 0.0), u.config.x * 0.5) * pos;
    for (var i = 0; i < 4; i++) {
        pos = vec3<f32>(abs(pos.x), abs(pos.y), abs(pos.z)) - vec3<f32>(0.2);
        pos = rotate3D(vec3<f32>(1.0, 1.0, 1.0), 0.5) * pos;
    }
    return length(pos) - 0.5;
}

fn sdf_mycelium(p: vec3<f32>) -> f32 {
    var pos = p;
    let density = u.zoom_params.x;
    let audio_react = plasmaBuffer[0].x * 0.5;
    let warp = u.zoom_params.z;
    let mouseInf = clamp(u.zoom_params.w, 0.0, 1.0);
    // Idea 2 — chrono lag: living net trails the gear clock
    let lagTime = u.config.x - 0.55;
    let mouse_offset = vec2<f32>((u.zoom_config.y - 0.5) * 2.0, (0.5 - u.zoom_config.z) * 2.0) * mouseInf;   // y flipped: world +y is up
    pos.x += sin(pos.y * warp + lagTime) * mouse_offset.x;
    pos.y += sin(pos.x * warp + lagTime) * mouse_offset.y;

    let noise = fbm(pos * density + vec3<f32>(lagTime)) * (0.5 + audio_react);
    // ── Idea 5: twisted three-strand rhizomorph cord (§12.2E additive domain twist) ──
    // The cross-section angle is twisted by CORD_TWIST * y before the (unchanged) radius test, so the stalk
    // reads as a braided cord whose strands wind up it and keep winding with the chrono lag. 3 lobes (integer)
    // keep the atan2 seam invisible. The existing fbm radius noise is untouched.
    var strands = 0.0;
    if (length(pos.xz) < 0.5) {   // the cord is at most ~0.3 wide; skip the atan2/cos for rays far from the stalk
        let cordAng = atan2(pos.z, pos.x) - pos.y * CORD_TWIST - lagTime * 0.35;
        strands = 0.035 * cos(3.0 * cordAng);
    }
    return length(vec2<f32>(pos.x, pos.z)) - 0.1 - strands - noise * 0.2;
}

// ── Idea 3: golden-angle fruiting primordia (§12.2E golden-angle layout) ──────
// Buds pin off the stalk in phyllotactic order: bud i sits at height i*BUD_PITCH and azimuth i*GOLDEN_ANGLE.
// Domain repetition along y (the two nearest cells, no loop); the cell count is capped so the column ends.
fn sdf_buds(p: vec3<f32>) -> f32 {
    let rxz = length(p.xz);
    if (rxz > 0.8) { return rxz - 0.31; }   // every bud lies within 0.16 + 0.135 of the stalk axis: cheap lower bound
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let cy = p.y / BUD_PITCH;
    let i0 = round(cy);
    let i1 = i0 + select(-1.0, 1.0, cy >= i0);
    let rb = 0.1 + 0.035 * bass;
    var best = 1e5;
    for (var k = 0; k < 2; k = k + 1) {
        let i = clamp(select(i0, i1, k == 1), -4.0, 4.0);
        let az = i * GOLDEN_ANGLE;
        let c = vec3<f32>(cos(az) * 0.16, i * BUD_PITCH, sin(az) * 0.16);
        let q = (p - c) * vec3<f32>(1.0, 1.15, 1.0);
        best = min(best, length(q) - rb);
    }
    return best;
}

// Idea 1 — hyphal wrapping: helical tube coiling around the gear spin axis
fn sdf_wrap(p: vec3<f32>) -> f32 {
    let ang = atan2(p.z, p.x) + u.config.x * 0.5;
    let rad = length(p.xz);
    let coil = 6.0;
    let helixY = p.y - sin(ang * coil) * 0.16;
    let helixR = rad - (0.58 + 0.07 * sin(ang * coil + p.y * 4.0));
    return length(vec2<f32>(helixR, helixY)) - 0.055;
}

fn smooth_min(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / max(k, 0.001);
    return min(a, b) - h * h * k * 0.25;
}

fn map(p: vec3<f32>) -> f32 {
    let d_gear = sdf_gear(p);
    let d_mycelium = sdf_mycelium(p);
    let d_wrap = sdf_wrap(p);
    return smooth_min(smooth_min(smooth_min(d_gear, d_mycelium, 0.5), d_wrap, 0.22), sdf_buds(p), 0.1);
}

fn calc_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var uv = (fragCoord - 0.5 * res) / res.y;
    uv.y = -uv.y;   // Rescue R1: texture row 0 is the TOP; world +y must point up the image
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var p = ro;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let plasma_glow = u.zoom_params.y * (1.0 + mids * 0.6);
    let hit = t < 20.0;
    var lum = 0.0;
    var wrapLit = 0.0;

    if (hit) {
        let n = calc_normal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let glow = fbm(p * 5.0 - vec3<f32>(u.config.x * 2.0)) * plasma_glow;

        let gear_color = vec3<f32>(0.2, 0.2, 0.3) * diff;
        let mycelium_color = vec3<f32>(0.0, 1.0, 1.0) * glow * diff + vec3<f32>(1.0, 0.0, 1.0) * (1.0 - glow) * diff;

        col = mix(gear_color, mycelium_color, smoothstep(0.0, 1.0, length(p)));
        col += vec3<f32>(0.8, 0.9, 1.0) * abs(glow) * treble * 0.15;
        wrapLit = 1.0 - smoothstep(0.0, 0.08, max(sdf_wrap(p), 0.0));
        col += vec3<f32>(0.45, 0.95, 0.7) * wrapLit * (0.35 + mids * 0.25);

        // Idea 3 (surface): primordia caps are pale and warm against the magenta net
        let budLit = 1.0 - smoothstep(0.0, 0.05, max(sdf_buds(p), 0.0));
        col = mix(col, vec3<f32>(1.0, 0.78, 0.55) * (0.3 + diff), budLit * 0.75);

        // ── Idea 4: cytoplasmic streaming pulses ──────────────────────────
        // Pulses leave the gear and travel outward along the stalk (|y|), phase taken from the chrono lag so they
        // trail the gear's clock; masked to the stalk axis and kept out of the gear itself.
        let stalkMask = 1.0 - smoothstep(0.18, 0.4, length(p.xz));
        let flowPhase = abs(p.y) * 6.0 - (u.config.x - 0.55) * 2.4;
        let streamPulse = pow(0.5 + 0.5 * sin(flowPhase), 6.0);
        let stream = streamPulse * stalkMask * smoothstep(0.35, 0.9, abs(p.y)) * (0.45 + bass * 0.9);
        col += vec3<f32>(0.5, 1.0, 0.9) * stream;

        lum = clamp(diff + abs(glow) * 0.5 + wrapLit * 0.3 + stream * 0.3 + budLit * 0.2, 0.0, 1.0);
    }

    let alpha = clamp(select(0.0, 0.3, hit) + lum * 0.6, 0.0, 1.0);
    let display = acesToneMap(col);
    let outColor = vec4<f32>(display, alpha);

    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
