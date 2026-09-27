// ═══════════════════════════════════════════════════════════════════
//  ASCII Flow
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21
//  Ideas: ink-coverage glyph ramp; coverage-weighted glyph blend;
//         typed-cell wake under the pointer
//  A packing: ACES display RGBA (C is read as colour history)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// 2D Noise
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Procedural Glyph drawing
fn draw_glyph(uv: vec2<f32>, index: i32) -> f32 {
    // uv is 0.0 to 1.0 inside the cell
    let c = uv - 0.5;
    var d = 1.0;

    // 0: Dot
    if (index == 0) {
        d = length(c) - 0.2;
    }
    // 1: Vertical Line
    else if (index == 1) {
        d = abs(c.x) - 0.1;
    }
    // 2: Horizontal Line
    else if (index == 2) {
        d = abs(c.y) - 0.1;
    }
    // 3: Plus
    else if (index == 3) {
        d = min(abs(c.x), abs(c.y)) - 0.08;
    }
    // 4: Diagonal /
    else if (index == 4) {
        d = abs(c.x + c.y) - 0.1;
    }
    // 5: Diagonal \
    else if (index == 5) {
        d = abs(c.x - c.y) - 0.1;
    }
    // 6: X
    else if (index == 6) {
        d = min(abs(c.x + c.y), abs(c.x - c.y)) - 0.08;
    }
    // 7: Box
    else {
        d = max(abs(c.x), abs(c.y)) - 0.4;
        d = abs(d) - 0.05; // Outline
    }

    return 1.0 - smoothstep(0.0, 0.05, d);
}

// Glyph indices re-sorted by the ink each shape actually lays down:
// dot < slash < backslash < bar < dash < X < plus < box. HEAD indexed them
// in authoring order (dot, bar, dash, plus, slash, backslash, X, box),
// whose coverage jumps around, so the brightness ramp was non-monotonic and
// the photo could not read through the grid. Same eight shapes, real ramp.
fn ramp_glyph(step_idx: i32) -> i32 {
    let order = array<i32, 8>(0, 4, 5, 1, 2, 6, 3, 7);
    return order[clamp(step_idx, 0, 7)];
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(gid.xy);
    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let intensity = u.zoom_params.x;
    let speed = mix(0.1, 2.5, u.zoom_params.y);
    let scale = mix(24.0, 120.0, u.zoom_params.z);
    let detail = mix(1.0, 6.0, u.zoom_params.w);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

    // Grid Setup
    let grid_dims = vec2<f32>(scale, scale * resolution.y / resolution.x);
    let cell_uv = fract(uv * grid_dims);
    let cell_id = floor(uv * grid_dims);

    // Flow Field
    let noise = hash22(cell_id * 0.1 + vec2<f32>(time * speed * (0.1 + audio.y * 0.08)));
    var flow = (noise - 0.5) * 2.0; // Direction

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    let cell_center_uv = (cell_id + 0.5) / grid_dims;
    let to_mouse = cell_center_uv - mouse;
    let dist_mouse = length(to_mouse);

    // Repel from mouse
    let repel = to_mouse / max(dist_mouse, 0.001) * smoothstep(0.3, 0.0, dist_mouse);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let vortex = vec2<f32>(-repel.y, repel.x) * held;
    flow += repel * (1.0 + intensity * 2.0) + vortex * detail;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length(uv - event.xy) - age * 0.4) * 60.0);
    }

    // Sample texture at offset position (simulate flow source)
    // We sample 'upstream'
    let sample_pos = cell_center_uv - flow * 0.05;
    let color = textureSampleLevel(readTexture, u_sampler, clamp(sample_pos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // ── Idea 1: ink-coverage glyph ramp ───────────────────────────────
    // Brightness now walks the glyphs in order of real ink coverage.
    let ramp_pos = clamp(gray, 0.0, 1.0) * 7.0;
    let step_idx = i32(floor(ramp_pos));
    let sub = fract(ramp_pos);

    let scanGlyph = sin((cell_uv.x + cell_uv.y) * detail * 6.283 + time * speed * 2.0) * 0.5 + 0.5;

    // ── Idea 2: coverage-weighted glyph blend ─────────────────────────
    // A cell sitting between two rungs of the ramp renders as a weighted
    // mix of both, so tone survives the quantisation instead of snapping to
    // eight hard steps and flattening every gradient in the picture.
    let glyph_lo = draw_glyph(cell_uv, ramp_glyph(step_idx));
    let glyph_hi = draw_glyph(cell_uv, ramp_glyph(step_idx + 1));
    let shape = mix(glyph_lo, glyph_hi, sub) * mix(0.65, 1.0, scanGlyph);

    // Green phosphor look or keep original color?
    // Let's do a mix: Tint green but keep some hue.
    let tint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + gray * 5.0 + time * (0.3 + audio.z));
    var final_color = mix(color, tint, 0.45 + intensity * 0.4) * shape * (1.0 + audio.x * 0.35) + tint * clickFront * 0.3;

    let prev = textureLoad(dataTextureC, coord, 0).rgb;

    // ── Idea 3: typed-cell wake ───────────────────────────────────────
    // Cells the pointer crosses latch a bright "just typed" state and then
    // fade, so the cursor writes characters into the grid instead of only
    // shoving them around the flow field. The latch is differential: the
    // wake is whatever the history holds *above* this frame's base render,
    // which decays on its own and cannot run away into a full-frame trail.
    let cellRadius = 1.6 / max(grid_dims.x, grid_dims.y);
    let typed = smoothstep(cellRadius, 0.0, dist_mouse) * mix(0.45, 1.0, held);
    let base_lum = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let prev_lum = dot(prev, vec3<f32>(0.299, 0.587, 0.114));
    let residue = max(prev_lum - base_lum, 0.0);
    let wake = clamp(max(typed, residue * 0.86 - 0.01), 0.0, 1.0);

    final_color = mix(final_color, prev, 0.06 * shape);
    final_color += vec3<f32>(0.32, 1.0, 0.48) * wake * mix(0.35, 1.0, shape) * (0.5 + intensity * 0.7);

    final_color = acesToneMap(final_color * (0.95 + audio.y * 0.05));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(0.7, 1.0, luma) * mix(0.8, 1.0, depth) + clickFront * 0.15 + wake * 0.12, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(final_color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
