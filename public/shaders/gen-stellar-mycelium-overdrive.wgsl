// ═══════════════════════════════════════════════════════════════════
//  Stellar Mycelium Overdrive
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-31
//  Ideas: over-relaxed sphere tracing (§12.2E); gravity-well star as soft inverse-square
//         emitter, light + in-scatter (§12.2F); march-step occlusion (promoted loop counter);
//         two-faced sheet material (gyroid sign, fold-count analog §12.2E)
//  A packing: ACES display RGBA (new: HEAD wrote nothing to A)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// SDF functions
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) - bias) / scale - thickness;
}

// 3D Noise (fBm)
fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.3183099);
    p3 = p3 + dot(p3, p3.yxz + 50.0);
    return fract(p3.x * p3.y * p3.z);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(hash3(p + vec3<f32>(0.0,0.0,0.0)), hash3(p + vec3<f32>(1.0,0.0,0.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0,1.0,0.0)), hash3(p + vec3<f32>(1.0,1.0,0.0)), f2.x), f2.y),
        mix(mix(hash3(p + vec3<f32>(0.0,0.0,1.0)), hash3(p + vec3<f32>(1.0,0.0,1.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0,1.0,1.0)), hash3(p + vec3<f32>(1.0,1.0,1.0)), f2.x), f2.y), f2.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var p_curr = p;
    for(var i = 0; i < 4; i++) {
        f += w * noise(p_curr);
        w *= 0.5;
        p_curr *= 2.0;
    }
    return f;
}

// Warp applied to the lattice (gravity well + fBm). Shared by map() and the shading
// code so the material side-test below sees the same surface the marcher hit.
fn warpP(pos: vec3<f32>, mouse_grav: vec3<f32>, gravity_strength: f32) -> vec3<f32> {
    var p = pos;

    // Add distortion based on mouse gravity well
    let dist_to_mouse = length(p - mouse_grav);
    let gravity_effect = smoothstep(2.0, 0.0, dist_to_mouse) * gravity_strength;

    // Warp space towards mouse
    if (gravity_effect > 0.0) {
        let dir = normalize(mouse_grav - p);
        p += dir * gravity_effect * 0.5;
    }

    // Add fBm noise distortion
    p += fbm(p * 2.0 + u.config.x * 0.5) * 0.2;
    return p;
}

// Map function
fn map(pos: vec3<f32>, mouse_grav: vec3<f32>, gravity_strength: f32) -> f32 {
    let p = warpP(pos, mouse_grav, gravity_strength);

    // Density parameter mapping
    let density = u.zoom_params.x; // mapped to Density slider (1.0 - 5.0)

    // Basic structure
    let d = sdGyroid(p, density, 0.05, 0.0);

    return d;
}

fn calcNormal(p: vec3<f32>, mouse_grav: vec3<f32>, grav_strength: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, mouse_grav, grav_strength) - map(p - e.xyy, mouse_grav, grav_strength),
        map(p + e.yxy, mouse_grav, grav_strength) - map(p - e.yxy, mouse_grav, grav_strength),
        map(p + e.yyx, mouse_grav, grav_strength) - map(p - e.yyx, mouse_grav, grav_strength)
    ));
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(id.xy);

    if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;

    // Mouse Interaction
    var mouse_grav = vec3<f32>(0.0);
    var grav_strength = 0.0;
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = (u.zoom_config.yz - 0.5) * vec2<f32>(resolution.x/resolution.y, 1.0);
        mouse_grav = vec3<f32>(mouse_uv * 5.0, 0.0);
        grav_strength = 2.0; // Gravity well strength
    }

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    // ── Idea 1: over-relaxed sphere tracing (§12.2E) ────────────────────
    // Step omega*d; if consecutive spheres no longer overlap, retreat to the last safe
    // radius. Same picture as plain `t += d`; omega 1.2 keeps the 100-step cap from
    // clipping grazing rays into sky (omega 1.4 / 64 steps did).
    let omega = 1.2;
    let MAX_STEPS = 100;
    let star_on = f32(grav_strength > 0.0);
    var p = ro;
    var t = 0.0;
    var bloom = 0.0;
    var star_scatter = 0.0;      // Idea 2: in-scatter of the well's light along the ray
    var hit = false;
    var prev_d = 0.0;
    var step_len = 0.0;
    var iters = 0;

    for(var i = 0; i < MAX_STEPS; i++) {
        iters = i;
        p = ro + rd * t;
        let d = map(p, mouse_grav, grav_strength);

        if (step_len > 0.0 && (prev_d + d) < step_len) {
            // overstepped: go back to the previous position and advance by its safe radius
            t = t - step_len + prev_d;
            step_len = 0.0;
            prev_d = 0.0;
            continue;
        }

        // Volumetric bloom accumulation (HEAD per-step sum, weighted by omega so the
        // longer steps do not thin it out)
        bloom += exp(-d * (5.0 - u.zoom_params.z)) * 0.05 * omega; // u.zoom_params.z = Glow Intensity

        // ── Idea 2: soft inverse-square in-scatter from the gravity-well star ──
        let rs = p - mouse_grav;
        star_scatter += star_on * d / (dot(rs, rs) + 0.15);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 10.0) {
            break;
        }
        step_len = d * omega;
        prev_d = d;
        t += step_len;
    }

    // Parameters
    let pulse_speed = u.zoom_params.y; // Pulse Speed
    let color_shift = u.zoom_params.w; // Color Shift

    // Shading
    var col = vec3<f32>(0.05, 0.0, 0.1); // Base space color
    var depth = 0.0;
    let star_col = vec3<f32>(1.0, 0.2, 0.8);

    if (hit) {
        let n = calcNormal(p, mouse_grav, grav_strength);
        let lightDir = normalize(vec3<f32>(sin(u.config.x), 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        var baseCol = vec3<f32>(0.2, 0.1, 0.5) + vec3<f32>(0.0, 0.5, 0.5) * color_shift;

        // ── Idea 4: two-faced sheet material (§12.2E fold-count analog) ──
        // The gyroid shell has two faces, told apart by the sign of the field.
        // The far face leans toward the (existing) magenta of the gravity well.
        let pw = warpP(p, mouse_grav, grav_strength) * u.zoom_params.x;
        let side = dot(sin(pw), cos(pw.zxy));
        baseCol = mix(baseCol, baseCol.zxy * 0.85, smoothstep(-0.15, 0.15, side) * 0.7);

        // ── Idea 3: march-step occlusion (§12.1 t3) ──
        // Rays that needed many steps grazed neighbouring sheets: crevices darken.
        let ao = mix(1.0, 0.5, smoothstep(0.25, 0.9, f32(iters) / f32(MAX_STEPS)));

        // Energy pulses — Idea 2 (direction): radiate from the well while it is held,
        // run along z otherwise (HEAD)
        let phase_src = select(p.z, length(p - mouse_grav), grav_strength > 0.0);
        let pulse = sin(phase_src * 10.0 - u.config.x * pulse_speed * 5.0) * 0.5 + 0.5;
        let pulse_color = vec3<f32>(0.1, 0.8, 0.9) * pulse * (1.0 + bass);

        // ── Idea 2: the well is a star — soft inverse-square point light + glow ──
        let to_star = mouse_grav - p;
        let s2 = dot(to_star, to_star);
        let star_att = 1.0 / (s2 + 0.15);
        let star_diff = max(dot(n, to_star * inverseSqrt(max(s2, 1e-6))), 0.0);
        let star_lit = star_on * star_att * (0.12 + 0.2 * star_diff);
        let mouse_glow = star_col * star_lit * grav_strength * 1.2;

        col = baseCol * (diff + star_on * star_att * 0.06 * star_diff) * ao + pulse_color * ao + mouse_glow;
        depth = clamp(1.0 - t / 10.0, 0.0, 1.0);
    }

    // Add bloom
    let bloom_col = vec3<f32>(0.2, 0.5, 0.8) * bloom * (1.0 + mids * 0.5);
    col += bloom_col;
    col += star_col * star_scatter * 0.06;

    // Output: ACES on display RGB (clamped first), alpha = coverage / glow
    let glow_luma = dot(bloom_col + star_col * star_scatter * 0.06, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(select(0.4 + 0.6 * clamp(glow_luma * 2.0, 0.0, 1.0), 1.0, hit), 0.0, 1.0);
    col = aces_tonemap(max(col, vec3<f32>(0.0)));
    let outRGBA = vec4<f32>(col, alpha);

    textureStore(writeTexture, coords, outRGBA);
    textureStore(dataTextureA, coords, outRGBA);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
