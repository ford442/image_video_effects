// ═══════════════════════════════════════════════════════════════════
//  Worley Cellular v2 - Audio-reactive cellular fields
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural,
//            organic-cellular, animated
//  Scientific: Worley noise (F1, F2) with FBM layering
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Creative additions: micro-cosmic starfields inside cells,
//                      thin-film interference (oil-slick) edge glow
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let h = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(h) * 43758.5453);
}

fn hash3(p: vec2<f32>) -> vec3<f32> {
    let h = vec3<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3)),
        dot(p, vec2<f32>(419.2, 371.9))
    );
    return fract(sin(h) * 43758.5453);
}

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

struct WorleyResult {
    f1: f32,
    f2: f32,
    cell_id: vec2<f32>,
    cell_index: vec2<f32>,
};

fn worley_noise(uv: vec2<f32>, scale: f32, time: f32, drift_speed: f32) -> WorleyResult {
    let st = uv * scale;
    let cell = floor(st);
    let frac = fract(st);

    var f1 = 1e10;
    var f2 = 1e10;
    var cell_id = vec2<f32>(0.0);
    var cell_index = cell;

    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let current_cell = cell + neighbor;
            let hash_val = hash2(current_cell);
            let drift = vec2<f32>(
                sin(time * drift_speed + hash_val.x * 6.28),
                cos(time * drift_speed + hash_val.y * 6.28)
            ) * 0.3;
            let feature_point = neighbor + hash_val + drift;
            let diff = feature_point - frac;
            let dist = length(diff);

            if (dist < f1) {
                f2 = f1;
                f1 = dist;
                cell_id = hash_val;
                cell_index = current_cell;
            } else if (dist < f2) {
                f2 = dist;
            }
        }
    }
    return WorleyResult(f1, f2, cell_id, cell_index);
}

fn fbm_worley(uv: vec2<f32>, time: f32, base_scale: f32, octaves: i32) -> vec3<f32> {
    var total_f1: f32 = 0.0;
    var total_f2: f32 = 0.0;
    var amplitude: f32 = 1.0;
    var frequency: f32 = 1.0;
    var max_value: f32 = 0.0;

    for (var i: i32 = 0; i < 4; i = i + 1) {
        if (i >= octaves) { break; }
        let worley = worley_noise(uv, base_scale * frequency, time, 0.5 + f32(i) * 0.2);
        total_f1 = total_f1 + worley.f1 * amplitude;
        total_f2 = total_f2 + worley.f2 * amplitude;
        max_value = max_value + amplitude;
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }

    total_f1 = total_f1 / max_value;
    total_f2 = total_f2 / max_value;
    let edge_value = total_f2 - total_f1;
    return vec3<f32>(total_f1, total_f2, edge_value);
}

fn get_inner_color(cell_hash: vec2<f32>) -> vec3<f32> {
    let palette = array<vec3<f32>, 5>(
        vec3<f32>(0.15, 0.08, 0.12),
        vec3<f32>(0.08, 0.15, 0.10),
        vec3<f32>(0.12, 0.10, 0.18),
        vec3<f32>(0.18, 0.12, 0.08),
        vec3<f32>(0.10, 0.12, 0.15)
    );
    let idx = i32(clamp(cell_hash.x * 4.99, 0.0, 4.0));
    return palette[idx];
}

// Thin-film interference edge color (oil-slick / soap-bubble)
fn get_edge_color(cell_hash: vec2<f32>, time: f32, edgeT: f32) -> vec3<f32> {
    let phase = edgeT * 14.0 + cell_hash.x * 6.28 + time * 0.7;
    return vec3<f32>(
        0.5 + 0.5 * cos(phase),
        0.5 + 0.5 * cos(phase + 2.094),
        0.5 + 0.5 * cos(phase + 4.188)
    );
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-specific params
    let cellDensityP = u.zoom_params.x;   // Cell Density (bass-pulse)
    let edgeGlowP = u.zoom_params.y;      // Edge Glow (mids)
    let colorShift = u.zoom_params.z;     // Color Shift
    let parallax = u.zoom_params.w;       // Parallax

    let density = mix(3.0, 12.0, cellDensityP) * (1.0 + bass * 0.35);
    let edges = mix(0.3, 1.5, edgeGlowP) * (1.0 + mids * 0.6);

    let uv1 = uv + vec2<f32>(sin(time * 0.05), cos(time * 0.03)) * parallax * 0.02;
    let worley1 = fbm_worley(uv1, time * 0.1, density, 3);
    let uv2 = uv - vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * parallax * 0.03;
    let worley2 = fbm_worley(uv2, time * 0.15 + 100.0, density * 1.5, 2);
    let uv3 = uv + vec2<f32>(cos(time * 0.1), sin(time * 0.08)) * parallax * 0.01;
    let worley3 = fbm_worley(uv3, time * 0.2 + 200.0, density * 3.0, 2);

    let combined_f1 = worley1.x * 0.5 + worley2.x * 0.3 + worley3.x * 0.2;
    let combined_f2 = worley1.y * 0.5 + worley2.y * 0.3 + worley3.y * 0.2;
    let combined_edge = worley1.z * 0.5 + worley2.z * 0.3 + worley3.z * 0.2;

    let edge_value = combined_edge * edges;
    // Need primary cell index for stable per-cell features
    let primary = worley_noise(uv1, density, time * 0.1, 0.5);
    let cell_hash = primary.cell_id;
    let cell_index = primary.cell_index;

    let inner_color = get_inner_color(cell_hash + colorShift);
    let edge_color = get_edge_color(cell_hash + colorShift, time, edge_value);
    let depth_shading = 1.0 - combined_f1 * 0.5;

    let edge_mask = smoothstep(0.0, 0.15, edge_value);
    var final_color = mix(inner_color * depth_shading, edge_color, edge_mask);
    let glow = pow(edge_value, 2.0) * edgeGlowP * 0.5;
    final_color = final_color + edge_color * glow;

    // ─── Creative: micro-cosmic starfield inside each cell ───
    // Independent rotation per cell, hashed offset
    let cellRot = cell_hash.y * 6.28 + time * (0.1 + cell_hash.x * 0.4);
    let cR = cos(cellRot);
    let sR = sin(cellRot);
    let localFrac = fract(uv1 * density) - 0.5;
    let starUV = vec2<f32>(localFrac.x * cR - localFrac.y * sR, localFrac.x * sR + localFrac.y * cR);
    let starGrid = floor(starUV * 30.0);
    let starHash = hash1(starGrid + cell_index * 13.0);
    let starThresh = 0.97 - bass * 0.04;
    let inCell = 1.0 - edge_mask;
    var starField = step(starThresh, starHash) * inCell;
    // Treble flicker
    let flicker = step(1.0 - treble * 0.4, hash1(starGrid + vec2<f32>(time * 12.0, cell_index.x)));
    starField = starField * (0.5 + flicker * 0.5);
    final_color = final_color + vec3<f32>(starField) * (0.6 + cell_hash.x * 0.4);

    // Vignette
    let vignette = 1.0 - length((uv - 0.5) * 1.2);
    final_color = final_color * smoothstep(0.0, 0.7, vignette);

    // Tone map
    final_color = acesToneMapping(final_color);

    // Sample input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let opacity = 0.9;
    let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let edgeAlpha = mix(0.6, 1.0, edge_mask);
    let generatedAlpha = max(edgeAlpha, smoothstep(0.05, 0.5, luma));

    let finalColor = mix(inputColor.rgb, final_color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));

    // Depth uses combined_f1 (Worley F1) for interesting depth-aware downstream
    let depth_out = mix(inputDepth, combined_f1, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_out, 0.0, 0.0, 0.0));

    // dataTextureA: cell ID (R, G), edge mask (B), F1 distance (A)
    textureStore(dataTextureA, coord, vec4<f32>(
        cell_hash.x,
        cell_hash.y,
        edge_mask,
        combined_f1
    ));
}
