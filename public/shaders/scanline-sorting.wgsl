// ═══════════════════════════════════════════════════════════════════
//  Scanline Sorting
//  Category: interactive-mouse
//  Features: mouse-driven, sorting, audio-reactive, palette-mapped,
//            chromatic-edge, aces-tone-map, early-exit, branchless,
//            shared-memory, bitonic-sort
//  Complexity: Medium
//  Created: 2026-01-01
//  Upgraded: 2026-07-08
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const EPS: f32 = 1e-4;

// ── Core helpers ─────────────────────────────────────────────────
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

// ── Shared scanline tile ─────────────────────────────────────────
var<workgroup> s_tile: array<vec3<f32>, 256>;
var<workgroup> s_active: atomic<u32>;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>,
        @builtin(local_invocation_id) local_id: vec3<u32>) {
    // ── Pixel setup ────────────────────────────────────────────────
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    let inside = pixel.x < i32(res.x) && pixel.y < i32(res.y);
    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;

    // ── Audio & uniforms ───────────────────────────────────────────
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sort_threshold   = clamp(u.zoom_params.x, 0.0, 1.0);
    let scan_width       = u.zoom_params.y * 0.2 * (1.0 + bass * 0.3);
    let scan_speed       = u.zoom_params.z;
    let direction_toggle = step(0.5, u.zoom_params.w);
    let mouseDown        = u.zoom_config.w;
    let mouse            = u.zoom_config.yz;

    // ── Scanline band ──────────────────────────────────────────────
    let scan_pos = mix(mix(mouse.y, mouse.x, direction_toggle),
                       fract(time * scan_speed),
                       step(0.01, scan_speed));

    let coord_along = mix(uv.y, uv.x, direction_toggle);
    let dist_to_scan = abs(coord_along - scan_pos);
    let band_t = 1.0 - smoothstep(0.0, max(scan_width, EPS), dist_to_scan);

    // ── Mouse cursor boost ─────────────────────────────────────────
    let aspect = res.x / max(res.y, 1.0);
    let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let cursorBoost = fast_exp(-dMouse * dMouse * 6.0) * (0.4 + mouseDown * 0.6);

    // ── Load one texel per thread into shared tile ─────────────────
    var original = vec3<f32>(0.0);
    var depth = 0.0;
    if (inside) {
        original = textureLoad(readTexture, pixel, 0).rgb;
        depth = textureLoad(readDepthTexture, pixel, 0).r;
    }

    let li = local_id.y * 16u + local_id.x;
    s_tile[li] = original;

    // Zero the activity counter before the tile-wide vote
    atomicStore(&s_active, 0u);

    // Vote on whether this tile needs sorting at all
    if (band_t >= EPS && inside) {
        atomicAdd(&s_active, 1u);
    }
    workgroupBarrier();

    let tile_active = atomicLoad(&s_active) > 0u;

    // ── Early tile-wide exit: most tiles are outside the scan band ─
    if (!tile_active) {
        if (inside) {
            let alpha = clamp(0.55 + cursorBoost * 0.2 + treble * 0.05, 0.0, 1.0);
            let finalColor = vec4<f32>(original.rgb, alpha);
            textureStore(writeTexture, pixel, finalColor);
            textureStore(dataTextureA, pixel, finalColor);
            textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
        }
        return;
    }

    // ── Bitonic sort of the local 16-pixel scanline ────────────────
    // Map lane/base to either rows (horizontal) or columns (vertical)
    let lane = select(local_id.y, local_id.x, direction_toggle > 0.5);
    let base = select(local_id.y * 16u, local_id.x, direction_toggle > 0.5);
    let stride = select(16u, 1u, direction_toggle > 0.5);

    for (var stage: u32 = 2u; stage <= 16u; stage = stage << 1u) {
        for (var step: u32 = stage >> 1u; step > 0u; step = step >> 1u) {
            let partner = lane ^ step;
            if (partner > lane) {
                let idxA = base + lane * stride;
                let idxB = base + partner * stride;
                let a = s_tile[idxA];
                let b = s_tile[idxB];
                let ascending = (lane & stage) == 0u;
                let swap = (luma(a) > luma(b)) == ascending;
                s_tile[idxA] = select(a, b, swap);
                s_tile[idxB] = select(b, a, swap);
            }
            workgroupBarrier();
        }
    }

    // ── Luminance sort blend ───────────────────────────────────────
    var color = original;
    let lf = luma(original);
    let sort_strength = smoothstep(sort_threshold, 1.0, lf)
                        * (20.0 + bass * 20.0 + mids * 10.0)
                        * (1.0 + cursorBoost);

    let sorted = s_tile[base + lane * stride];
    let sortMix = band_t * clamp(sort_strength * 0.05, 0.0, 1.0);
    color = mix(color, sorted, sortMix);

    // ── Chromatic edge shift ───────────────────────────────────────
    let pix = mix(vec2<f32>(0.0, -1.0 / res.y),
                  vec2<f32>(-1.0 / res.x, 0.0),
                  direction_toggle);
    let sample_pos = clamp(uv + pix * sort_strength, vec2<f32>(0.0), vec2<f32>(1.0));

    let ghost = (1.0 - band_t) * scan_width * 8.0;
    let r_uv = sample_pos + pix * ghost;
    let b_uv = sample_pos - pix * ghost;
    let r2 = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let b2 = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
    color = mix(color, vec3<f32>(r2, color.g, b2), band_t * 0.4);

    // ── Palette overlay ────────────────────────────────────────────
    let pIdx = u32(clamp((lf + sort_strength * 0.005) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[pIdx].rgb;
    color = mix(color, color * (0.6 + palette * 0.8), band_t * 0.5);

    // ── Tone map & semantic alpha ──────────────────────────────────
    let lf2 = luma(color);
    let bloom = max(0.0, lf2 - 0.7) * 3.0;

    color = acesToneMap(color * (1.0 + mids * 0.15 + treble * 0.05));

    let alpha = clamp(0.55 + band_t * 0.35 + bloom * 0.5
                      + cursorBoost * 0.2 + treble * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(color, alpha);

    if (inside) {
        textureStore(writeTexture, pixel, finalColor);
        textureStore(dataTextureA, pixel, finalColor);
        textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    }
}
