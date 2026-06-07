// ═══════════════════════════════════════════════════════════════════
//  Interactive Kuwahara
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params (radius pulses with bass, sat with mids)
    let radiusParam = (u.zoom_params.x * 8.0 + 2.0) * (1.0 + bass * 0.4);
    let satBoost = u.zoom_params.y * 2.0 * (1.0 + mids * 0.3);
    let mouseFalloff = u.zoom_params.z;

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    let mouseFactor = smoothstep(0.0, 0.5, dist);
    let effectiveRadius = mix(radiusParam, 0.0, (1.0 - mouseFactor) * mouseFalloff);

    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let radius = i32(max(effectiveRadius, 0.0));
    let pixelSize = vec2<f32>(1.0 / max(resolution.x, 1.0), 1.0 / max(resolution.y, 1.0));

    // Kuwahara: 4 sectors
    var mean: array<vec3<f32>, 4>;
    var sigma: array<vec3<f32>, 4>;
    for (var i = 0; i < 4; i++) {
        mean[i] = vec3<f32>(0.0);
        sigma[i] = vec3<f32>(0.0);
    }

    let offsets = array<vec2<i32>, 4>(
        vec2<i32>(-radius, -radius),
        vec2<i32>(0, -radius),
        vec2<i32>(-radius, 0),
        vec2<i32>(0, 0)
    );

    for (var k = 0; k < 4; k++) {
        var count = 0.0;
        let start = offsets[k];
        for (var j = 0; j <= radius; j++) {
            for (var i = 0; i <= radius; i++) {
                let sampleUV = clamp(uv + vec2<f32>(f32(start.x + i), f32(start.y + j)) * pixelSize, vec2<f32>(0.0), vec2<f32>(1.0));
                let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
                mean[k] += col;
                sigma[k] += col * col;
                count += 1.0;
            }
        }
        let safeCount = max(count, 0.001);
        mean[k] = mean[k] / safeCount;
        sigma[k] = abs(sigma[k] / safeCount - mean[k] * mean[k]);
    }

    // Pick min-variance sector (branchless selects)
    var minVar = sigma[0].r + sigma[0].g + sigma[0].b;
    var kuwaColor = mean[0];
    let v1 = sigma[1].r + sigma[1].g + sigma[1].b;
    kuwaColor = select(kuwaColor, mean[1], v1 < minVar);
    minVar = select(minVar, v1, v1 < minVar);
    let v2 = sigma[2].r + sigma[2].g + sigma[2].b;
    kuwaColor = select(kuwaColor, mean[2], v2 < minVar);
    minVar = select(minVar, v2, v2 < minVar);
    let v3 = sigma[3].r + sigma[3].g + sigma[3].b;
    kuwaColor = select(kuwaColor, mean[3], v3 < minVar);

    // Mix base color back in if radius is small (branchless)
    let smallRadiusMix = clamp(1.0 - effectiveRadius, 0.0, 1.0);
    let blendedRGB = mix(kuwaColor, baseSample.rgb, smallRadiusMix);

    // Saturation boost
    let lum = dot(blendedRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
    let satColor = mix(vec3<f32>(lum), blendedRGB, 1.0 + satBoost);

    // Treble shimmer
    let shimmer = sin(uv.x * 200.0 + u.config.x * 12.0) * treble * 0.05;
    let finalRGB = clamp(satColor + vec3<f32>(shimmer), vec3<f32>(0.0), vec3<f32>(4.0));

    // Meaningful alpha: stylization strength + base alpha + audio
    let stylization = clamp(effectiveRadius / 12.0, 0.0, 1.0);
    let alpha = clamp(baseSample.a * 0.5 + stylization * 0.4 + (1.0 - mouseFactor) * 0.2 + bass * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
