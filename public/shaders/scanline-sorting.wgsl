// ═══════════════════════════════════════════════════════════════════
//  Scanline Sorting
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-09
//  Ideas: threshold run streak; sort-front tear; sorted-rank tint
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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
var<workgroup> s_flag: u32;

fn hash11(x: f32) -> f32 { return fract(sin(x * 127.1) * 43758.5453); }

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
    let scan_width       = u.zoom_params.y * 0.2 * (1.0 + bass * 0.3) * select(1.0, 1.3, u.zoom_config.w > 0.5);
    let scan_speed       = u.zoom_params.z;
    let direction_toggle = step(0.5, u.zoom_params.w);
    let held = u.zoom_config.w > 0.5;
    let mouse            = u.zoom_config.yz;

    let smoothMouse = mouse;
    let mouseDown = select(u.zoom_config.w, 1.0, held);

    var rippleBoost = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
      let rp = u.ripples[ri];
      let age = time - rp.z;
      if (age >= 0.0 && age < 1.2) {
        rippleBoost = max(rippleBoost, smoothstep(0.14, 0.0, distance(uv, rp.xy)) * (1.0 - age * 0.85));
      }
    }

    let scan_pos = mix(mix(smoothMouse.y, smoothMouse.x, direction_toggle),
                       fract(time * scan_speed),
                       step(0.01, scan_speed));

    let coord_along = mix(uv.y, uv.x, direction_toggle);
    let dist_to_scan = abs(coord_along - scan_pos);
    let band_t = 1.0 - smoothstep(0.0, max(scan_width, EPS), dist_to_scan);

    // ── Mouse cursor boost ─────────────────────────────────────────
    let aspect = res.x / max(res.y, 1.0);
    let dMouse = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
    let cursorBoost = fast_exp(-dMouse * dMouse * 6.0) * (0.4 + mouseDown * 0.6) + rippleBoost * 0.35;

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

    if (li == 0u) { s_flag = atomicLoad(&s_active); }
    let tile_active = workgroupUniformLoad(&s_flag) > 0u;

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
    // Idea 3 — sorted-rank tint: cool at the dark end of the run, warm at the bright end
    let rank = f32(lane) / 15.0;
    let rankTint = mix(vec3<f32>(0.85, 0.95, 1.15), vec3<f32>(1.15, 1.0, 0.82), rank);
    let sortMix = band_t * clamp(sort_strength * 0.05, 0.0, 1.0);
    color = mix(color, sorted * mix(vec3<f32>(1.0), rankTint, 0.6), sortMix);

    // Idea 1 — threshold run streak: drag the brightest above-threshold texel along the sort axis
    let axis = mix(vec2<f32>(0.0, 1.0 / res.y), vec2<f32>(1.0 / res.x, 0.0), direction_toggle);
    var streak = vec3<f32>(0.0);
    var streakL = 0.0;
    for (var k = 1; k <= 8; k = k + 1) {
        let su = clamp(uv - axis * f32(k) * (2.0 + bass * 2.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let sc = textureSampleLevel(readTexture, u_sampler, su, 0.0).rgb;
        let w = smoothstep(sort_threshold, min(sort_threshold + 0.25, 1.0), luma(sc)) * (1.0 - f32(k) / 9.0);
        if (luma(sc) * w > streakL) { streakL = luma(sc) * w; streak = sc * w; }
    }
    color = max(color, mix(color, streak, band_t * 0.85));

    // Idea 2 — sort-front tear: hashed row/column shift on the band's leading edge
    let lead = scan_pos + scan_width * 0.7;
    let front = smoothstep(scan_width * 0.2, 0.0, abs(coord_along - lead)) * (0.6 + mouseDown * 0.4);
    let rowId = floor(coord_along * res.y * 0.25 + time * 7.0);
    let tearOff = (hash11(rowId) - 0.5) * 0.12 * (1.0 + mids) * front;
    let tuv = select(vec2<f32>(fract(uv.x + tearOff), uv.y), vec2<f32>(uv.x, fract(uv.y + tearOff)), direction_toggle > 0.5);
    let torn = textureSampleLevel(readTexture, u_sampler, tuv, 0.0).rgb;
    color = mix(color, torn, front * step(0.5, hash11(rowId + 3.1)));

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
