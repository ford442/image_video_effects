// ═══════════════════════════════════════════════════════════════════
//  Scanline Sorting
//  Category: interactive-mouse
//  Features: mouse-driven, sorting, audio-reactive, palette-mapped, chromatic-edge
//  Complexity: Medium
//  Phase B / Visualist
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SortThreshold, y=ScanWidth, z=ScanSpeed, w=DirectionToggle
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn luma_of(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

// Compare-exchange step (one pass of an ordered stride-1 sort) on (a,b)
// Returns the brighter sample for the upstream cell, dimmer for downstream.
fn cmp_exchange(a: vec3<f32>, b: vec3<f32>, reverse: f32) -> vec3<f32> {
    let la = luma_of(a);
    let lb = luma_of(b);
    let want_a_brighter = step(0.5, reverse);
    let a_is_brighter = step(lb, la);
    // Keep 'a' if its order matches reverse, else swap to 'b'
    let keep_a = step(0.5, abs(want_a_brighter - 1.0 + a_is_brighter));
    return mix(b, a, keep_a);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let sort_threshold   = clamp(u.zoom_params.x, 0.0, 1.0);
    let scan_width       = u.zoom_params.y * 0.2 * (1.0 + bass * 0.3);
    let scan_speed       = u.zoom_params.z;
    let direction_toggle = step(0.5, u.zoom_params.w);  // 0 horizontal-band, 1 vertical-band
    let mouseDown        = u.zoom_config.w;
    let mouse            = u.zoom_config.yz;

    // Scanline position: time-driven if speed>0, else mouse-controlled
    let scan_pos = mix(mix(mouse.y, mouse.x, direction_toggle),
                       fract(time * scan_speed),
                       step(0.01, scan_speed));

    let coord_along = mix(uv.y, uv.x, direction_toggle);
    let dist_to_scan = abs(coord_along - scan_pos);
    let band_t = 1.0 - smoothstep(0.0, max(scan_width, 1e-4), dist_to_scan);

    // Mouse cursor focuses sort intensity (Gaussian)
    let aspect = resolution.x / max(resolution.y, 1.0);
    let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let cursorBoost = exp(-dMouse * dMouse * 6.0) * (0.4 + mouseDown * 0.6);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var color = original.rgb;

    if (band_t > 0.001) {
        let luma = luma_of(color);
        let sort_strength = smoothstep(sort_threshold, 1.0, luma) * (20.0 + bass * 20.0) * (1.0 + cursorBoost);

        // Sort axis (perpendicular to scan motion)
        let pix = mix(vec2<f32>(0.0, -1.0 / resolution.y),
                      vec2<f32>(-1.0 / resolution.x, 0.0),
                      direction_toggle);
        let sample_pos = clamp(uv + pix * sort_strength, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0).rgb;

        // Bitonic-style: order pair (color, neighbor); higher luma drifts upstream
        color = cmp_exchange(color, neighbor, 0.0);

        // Chromatic ghost on band edges — sample R/B with slight extra offset
        let ghost = (1.0 - band_t) * scan_width * 8.0;
        let r2 = textureSampleLevel(readTexture, u_sampler, sample_pos + pix * ghost, 0.0).r;
        let b2 = textureSampleLevel(readTexture, u_sampler, sample_pos - pix * ghost, 0.0).b;
        color = mix(color, vec3<f32>(r2, color.g, b2), band_t * 0.4);

        // Plasma palette tint by sort displacement (ramps brightness through hue)
        let pIdx = u32(clamp((luma + sort_strength * 0.005) * 255.0, 0.0, 255.0));
        let palette = plasmaBuffer[pIdx % 256u].rgb;
        color = mix(color, color * (0.6 + palette * 0.8), band_t * 0.5);
    }

    // Bloom-style alpha: HDR shoulder above 0.7 for the sort streaks
    let lf = luma_of(color);
    let bloom = max(0.0, lf - 0.7) * 3.0;
    let alpha = clamp(0.55 + band_t * 0.35 + bloom * 0.5 + cursorBoost * 0.2, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
