// ═══════════════════════════════════════════════════════════════════
//  Pixel Explode
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
//  Slider wiring: 2026-07-31 (batch 22 — all 4 sliders were dead)
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

// Engine uniform truth (src/renderer/UniformBuffer.ts):
//   config      = [time, rippleCount, resW, resH]
//   zoom_config = [time, mouseX, mouseY, mouseDown]
//   zoom_params = [Intensity, Speed, Scale, Detail]  (wired below)
//   ripples[i]  = [clickX, clickY, clickTime, _]     (uv-space click points)
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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
    let explosion_radius = 0.5 * (1.0 + bass * 0.2);
    let explosion_force  = mix(0.0, 0.16, intensity) * (1.0 + mids * 0.3);

    var final_color = vec4<f32>(0.0);
    var closest_z   = 1000.0;

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

            let diff = abs(uv - new_center);

            // Branchless z-buffer and pixel coverage check
            let inParticle = select(0.0, 1.0, diff.x < particle_half_size.x && diff.y < particle_half_size.y);
            let z_depth    = dist;

            if (inParticle > 0.5 && z_depth < closest_z) {
                closest_z = z_depth;

                let local_uv = (uv - new_center) / max(particle_half_size * 2.0, vec2<f32>(0.0001)) + 0.5;
                let tex_uv   = clamp(neighbor_cell * cell_size + local_uv * cell_size, vec2<f32>(0.0), vec2<f32>(1.0));
                final_color  = textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0);
                final_color  = final_color * (1.0 + strength * 0.5);

                // Treble crackle — cells inside the explosion zone flash
                // brighter by treble bins, so the blast edge sparkles.
                let treble = plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x;
                final_color = final_color + vec4<f32>(vec3<f32>(treble * total_strength * 0.3), 0.0);
            }
        }
    }

    // Background — branchless: if final_color.a == 0 use dark bg
    let isBg = select(0.0, 1.0, final_color.a == 0.0);
    final_color = mix(final_color, vec4<f32>(0.05, 0.05, 0.1, 1.0), isBg);

    final_color = clamp(final_color, vec4<f32>(0.0), vec4<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: particle coverage (non-bg) + bass energy
    let alpha = clamp(final_color.a * 0.8 + bass * 0.15 + (1.0 - isBg) * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(final_color.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(gid.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), fc);
}
