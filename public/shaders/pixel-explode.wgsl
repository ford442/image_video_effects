// ═══════════════════════════════════════════════════════════════════
//  Pixel Explode
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: tumbling shards; drop shadows of lifted tiles on the navy gap; bevelled tiles with true lift depth
//  A packing: ACES display RGBA (unread — no C feedback)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// ---------------------------------------------------

// Engine uniform truth (src/renderer/UniformBuffer.ts):
//   config      = [time, rippleCount, resW, resH]
//   zoom_config = [time, mouseX, mouseY, mouseDown]
//   zoom_params = [Intensity, Speed, Scale, Detail]  (wired below)
//   ripples[i]  = [clickX, clickY, clickTime, _]     (uv-space click points)

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Rotate an aspect-space offset into a tile's frame and back to uv units.
fn tile_frame(d_uv: vec2<f32>, aspect: f32, cs: vec2<f32>) -> vec2<f32> {
    let p = d_uv * vec2<f32>(aspect, 1.0);
    return vec2<f32>(p.x * cs.y + p.y * cs.x, -p.x * cs.x + p.y * cs.y) / vec2<f32>(aspect, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let time = u.config.x;

    // ── Slider wiring (u.zoom_params — previously all 4 dead) ─────────
    // x 'Intensity' -> explosion force:  mix(0.0, 0.16, x)  (default 0.5 -> 0.08)
    // y 'Speed'     -> wobble speed:     mix(0.0, 4.0,  y)  (default 0.5 -> 2.0)
    // z 'Scale'     -> grid density:     mix(16.0, 64.0, z) (default 0.5 -> 40.0)
    // w 'Detail'    -> neighbor search:  mix(2.0, 10.0, w)  (default 0.5 -> 6)
    let intensity    = u.zoom_params.x;
    let wobble_speed = mix(0.0, 4.0, u.zoom_params.y);
    let grid_size    = mix(16.0, 64.0, u.zoom_params.z);
    let range        = clamp(i32(mix(2.0, 10.0, u.zoom_params.w)), 2, 10);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Grid Setup — bass widens explosion radius
    let grid_dims = vec2<f32>(grid_size * aspect, grid_size);
    let cell_size = 1.0 / grid_dims;

    let mouse = u.zoom_config.yz;
    let treble = plasmaBuffer[0].z;
    let explosion_radius = 0.5 * (1.0 + bass * 0.2);
    let explosion_force  = mix(0.0, 0.16, intensity) * (1.0 + mids * 0.3);

    var final_color = vec4<f32>(0.0);
    var closest_z   = 1000.0;
    var hit         = 0.0;
    var hit_lift    = 0.0;
    var hit_depth   = 0.0;
    var shadow      = 0.0;
    var shadow_lift = 0.0;
    var best_tex_uv = vec2<f32>(0.0);
    var best_local  = vec2<f32>(0.5);
    var best_crack  = 0.0;
    var best_str    = 0.0;

    let current_cell = floor(uv * grid_dims);

    // Neighbor search — 'Detail' widens the search radius so enlarged
    // particles (high 'Scale') still get z-buffer coverage; bounds are a
    // runtime var (WGSL allows var loop bounds) clamped to [2, 10].
    for (var x = -range; x <= range; x++) {
        for (var y = -range; y <= range; y++) {
            let neighbor_cell = current_cell + vec2<f32>(f32(x), f32(y));
            let orig_center   = (neighbor_cell + 0.5) * cell_size;

            // Stable per-cell hash in [0, 1): drives wobble phase + treble bin
            let cellHash = fract(sin(dot(neighbor_cell, vec2<f32>(12.9898, 78.233))) * 43758.5453);

            let to_mouse        = orig_center - mouse;
            let to_mouse_aspect = to_mouse * vec2<f32>(aspect, 1.0);
            let dist            = length(to_mouse_aspect);

            let strength = smoothstep(explosion_radius, 0.0, dist);
            let safeDir  = normalize(to_mouse + vec2<f32>(0.0001));
            var offset   = safeDir * strength * explosion_force;

            // Click detonations — each live ripple acts as a decaying second
            // explosion center at its click point (same smoothstep(radius, 0,
            // dist) strength form, force decaying as exp(-age * 2.5), ~1.5 s),
            // so clicks scatter pixels without holding the cursor still.
            var click_strength = 0.0;
            let ripple_count = min(u32(u.config.y), 50u);
            for (var r = 0u; r < ripple_count; r = r + 1u) {
                let ripple = u.ripples[r];
                let age = time - ripple.z;
                if (age > 0.0 && age < 1.5) {
                    let to_click = orig_center - ripple.xy;
                    let cdist = length(to_click * vec2<f32>(aspect, 1.0));
                    let cs = smoothstep(explosion_radius, 0.0, cdist) * exp(-age * 2.5);
                    click_strength = click_strength + cs;
                    offset = offset + normalize(to_click + vec2<f32>(0.0001)) * cs * explosion_force;
                }
            }
            let total_strength = clamp(strength + click_strength, 0.0, 1.0);

            // 'Speed' wobble — gentle per-cell sinusoidal drift, still at y = 0.
            // Two phase-shifted sines give a 2D drift; amplitude scales with
            // blast strength so untouched background pixels never swim.
            let wphase     = time * wobble_speed + cellHash * 6.28;
            let wobble_dir = vec2<f32>(sin(wphase), sin(wphase + 2.0944));
            offset = offset + wobble_dir * 0.01 * total_strength;

            let new_center        = orig_center + offset;
            let scale             = 1.0 + strength * 2.0;
            let particle_half_size = (cell_size * 0.5) * scale * 0.9;

            // Idea 1: tumbling shards — each blown tile spins by its own hash,
            // scaled by blast strength (still tiles stay square and upright);
            // 'Speed' keeps them turning slowly while airborne.
            let spin  = (cellHash - 0.5) * 2.4 * total_strength + sin(wphase * 0.5) * 0.25 * total_strength;
            let cs    = vec2<f32>(sin(spin), cos(spin));
            let rel   = tile_frame(uv - new_center, aspect, cs);
            let diff  = abs(rel);

            // Branchless z-buffer and pixel coverage check
            let inParticle = select(0.0, 1.0, diff.x < particle_half_size.x && diff.y < particle_half_size.y);
            let z_depth    = dist;
            let lift       = total_strength;

            // Idea 2: drop shadow — the same rotated tile, offset down-right by
            // its lift (light from the top-left), with a soft box edge.
            let shadow_off = vec2<f32>(1.0, 1.4) * cell_size * (0.35 + 1.1 * lift) * lift;
            let srel = abs(tile_frame(uv - new_center - shadow_off, aspect, cs)) - particle_half_size;
            let sbox = max(srel.x / cell_size.x, srel.y / cell_size.y);
            let s_cov = (1.0 - smoothstep(-0.15, 0.25, sbox)) * smoothstep(0.02, 0.2, lift);
            if (s_cov > shadow) {
                shadow = s_cov;
                shadow_lift = lift;
            }

            if (inParticle > 0.5 && z_depth < closest_z) {
                closest_z = z_depth;
                hit = 1.0;
                hit_lift = lift;

                let local_uv = rel / max(particle_half_size * 2.0, vec2<f32>(0.0001)) + 0.5;
                best_tex_uv  = clamp(neighbor_cell * cell_size + local_uv * cell_size, vec2<f32>(0.0), vec2<f32>(1.0));
                best_local   = local_uv;
                best_str     = strength;
                // Treble crackle — cells inside the explosion zone flash with
                // plasmaBuffer[0].z (HEAD read never-written bins 1..8), gated
                // per cell by its hash so the blast edge sparkles.
                best_crack   = treble * total_strength * 0.3 * step(0.45, cellHash);
            }
        }
    }

    // Shade the winning tile once (2 texture taps per pixel, whatever the overlap).
    if (hit > 0.5) {
        final_color = textureSampleLevel(readTexture, u_sampler, best_tex_uv, 0.0);
        hit_depth   = textureSampleLevel(readDepthTexture, non_filtering_sampler, best_tex_uv, 0.0).r;
        final_color = vec4<f32>(final_color.rgb * (1.0 + best_str * 0.5), final_color.a);

        // Idea 3: bevel — tile edges darken and the top-left rim catches
        // light, more so the higher the tile is lifted.
        let edge  = min(min(best_local.x, 1.0 - best_local.x), min(best_local.y, 1.0 - best_local.y));
        let bevel = 1.0 - smoothstep(0.0, 0.12, edge);
        let lit   = select(-1.0, 1.0, best_local.x + best_local.y < 1.0);
        let bevel_gain = 1.0 + bevel * (0.35 * lit - 0.15) * (0.4 + hit_lift);
        final_color = vec4<f32>(final_color.rgb * bevel_gain + vec3<f32>(best_crack), final_color.a);
    }

    // Background — navy gap where no tile covers the pixel (coverage flag,
    // not source alpha, so transparent source texels are not mistaken for gaps)
    let isBg = 1.0 - hit;
    // Idea 2: shadows fall on the gap, and on lower tiles under a higher one.
    let shade = shadow * select(0.0, 1.0, isBg > 0.5 || shadow_lift > hit_lift + 0.05) * 0.65;
    var rgb = mix(final_color.rgb, vec3<f32>(0.05, 0.05, 0.1), isBg);
    rgb = rgb * (1.0 - shade);
    rgb = aces_tonemap(max(rgb, vec3<f32>(0.0)));

    // Idea 3: true lift depth — tiles carry their source depth plus their
    // lift toward the viewer; the gap sits behind everything.
    let depth = select(clamp(hit_depth * 0.8 + 0.2 + hit_lift * 0.3, 0.0, 1.0), 0.0, isBg > 0.5);

    // Semantic alpha: tile coverage (source alpha) vs the gap, which is
    // denser under a shadow; bass still thickens the gap slightly.
    let alpha = select(clamp(final_color.a * (0.92 + 0.08 * hit_lift), 0.0, 1.0),
                       clamp(0.75 + shade * 0.2 + bass * 0.05, 0.0, 1.0), isBg > 0.5);
    let fc = vec4<f32>(rgb, alpha);

    textureStore(writeTexture, vec2<i32>(gid.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), fc);
}
