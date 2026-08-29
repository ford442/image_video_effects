// ═══════════════════════════════════════════════════════════════════
//  Ember Drift Dissolve — Batch 60
//  Category: image
//  Features: ember, dissolve, advection, heat, audio-sparks, held-furnace,
//            semantic-alpha, temporal, aces-tone-mapping, depth-aware
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — bright regions lift as glowing embers
//       carried by rising heat, beautiful disintegration on video)
//  Upgraded: 2026-07-31 by Kimi (swarm b22)
//    - Click ignition: live ripples burst embers at the click point
//    - Mouse heat plume + per-region FFT crackle
//  Upgraded: 2026-08-23 Batch 60
//    - Exact textureLoad for dataTextureC (pixel + advected sample)
//    - Held furnace: stronger rise + birth under cursor
//    - Richer white-hot → amber → ash palette; deeper crackle / ash wisps
//    - ACES on writeTexture only; A packing never tonemapped
//  A packing (SACRED — do not tonemap):
//    dataTextureA = (age, lateral, intensity, glow)
//    dataTextureC is previous A (engine copy). Exact texel loads only.
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
  zoom_params: vec4<f32>,  // x=Rise, y=Spark, z=Heat, w=Decay
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let aspect = res.x / res.y;
    let held = u.zoom_config.w > 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let riseSpeed = u.zoom_params.x * (0.7 + bass * 0.4);
    let sparkDensity = u.zoom_params.y * (0.6 + treble * 1.1);
    let heat = u.zoom_params.z;
    let decay = u.zoom_params.w * 0.9 + 0.1;

    // Exact previous ember state (age, lateral, intensity, glow)
    let prev = textureLoad(dataTextureC, pixel, 0);

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    // Only bright areas produce embers
    let emberMask = smoothstep(0.35, 0.82, luma);

    // Rising heat advection field (with some curl)
    let heatField = vec2<f32>(
        sin(uv.y * 6.0 + time * 0.6) * 0.018,
        -riseSpeed * (0.018 + heat * 0.012 + prev.g * 0.008)
    );

    // Mouse heat plume — the pointer stirs the thermals (aspect-corrected ~0.3 radius)
    let mousePos = u.zoom_config.yz;
    let mouseDelta = vec2<f32>((uv.x - mousePos.x) * aspect, uv.y - mousePos.y);
    let mouseDist = length(mouseDelta);
    let mouseMask = smoothstep(0.3, 0.0, mouseDist);
    // Held furnace: tighter, hotter core under the cursor
    let furnaceMask = select(0.0, smoothstep(0.22, 0.0, mouseDist), held);
    var heatFlow = heatField;
    heatFlow.y *= 1.0 + mouseMask * 0.8 + furnaceMask * 1.4;
    heatFlow.x += mouseMask * sin(time * 3.1 + uv.y * 9.0) * 0.006;
    heatFlow.x += furnaceMask * sin(time * 7.0 + uv.y * 14.0) * 0.01;

    // Sample previous location (advection) via exact texel load
    let prevUV = clamp(uv - heatFlow * 1.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectPixel = vec2<i32>(clamp(round(prevUV * res), vec2<f32>(0.0), res - 1.0));
    let carried = textureLoad(dataTextureC, advectPixel, 0);

    // New ember birth from bright pixels + audio sparks
    let birthBoost = select(1.0, 1.0 + furnaceMask * 2.2, held);
    let birth = emberMask * (0.4 + sparkDensity * 0.7) * birthBoost
              * step(0.82 - furnaceMask * 0.12, hash21(uv * 140.0 + floor(time * 7.0)));
    let spark = step(0.91, hash21(uv * 290.0 + time * 19.0)) * treble * 0.9 * emberMask;

    // Per-region FFT crackle — 8 vertical bands each ride their own spectrum bin
    let band = min(u32(uv.x * 8.0), 7u);
    let bandBin = plasmaBuffer[(band % 8u) + 1u].x;
    let crackleSeed = hash21(uv * 340.0 + vec2<f32>(time * 23.0, f32(band) * 17.0));
    let crackle = step(0.94 - bandBin * 0.05, crackleSeed) * bandBin * 0.7 * emberMask;
    // Secondary ash-wisp crackle: finer, cooler sparks that linger
    let wispSeed = hash21(uv * 520.0 + vec2<f32>(time * 31.0, f32(band) * 9.0));
    let ashWisp = step(0.965 - treble * 0.04, wispSeed) * (0.35 + bandBin * 0.5) * emberMask;

    var age = carried.r * decay + birth * 0.9 + spark * 0.6;
    age = clamp(age, 0.0, 1.0);

    // Band crackle + ash wisps feed the ember age
    age = clamp(age + crackle * 0.6 + ashWisp * 0.35, 0.0, 1.0);
    // Furnace birth under held cursor
    age = clamp(age + furnaceMask * emberMask * 0.55, 0.0, 1.0);

    // Click ignition — each live ripple sets a fire at its click point
    let rippleCount = min(u32(u.config.y), 50u);
    var ignite = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rAge = time - ripple.z;
        if (rAge >= 0.0 && rAge < 1.5) {
            let rDelta = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
            let rDist = length(rDelta);
            let burst = smoothstep(0.2, 0.0, rDist) * max(0.0, 1.0 - rAge / 1.5);
            ignite = max(ignite, burst);
        }
    }
    // Bright regions catch fire more readily; dark areas only smoulder
    ignite *= 0.35 + emberMask * 0.65;
    age = clamp(age + ignite * 0.85, 0.0, 1.0);

    // Lateral turbulence increases with age and treble
    let turb = (hash21(uv * 17.0 + time * 2.3) - 0.5) * 0.008 * (age * 0.7 + treble * 0.4);
    let lateral = carried.g * 0.92 + turb + furnaceMask * (hash21(uv * 41.0 + time) - 0.5) * 0.01;

    let intensity = age * (0.7 + mids * 0.3) * smoothstep(1.0, 0.2, age);

    // Ignition flash — fresh click / furnace fires burn white-hot before cooling
    let flash = (ignite * ignite + furnaceMask * furnaceMask * 0.6) * smoothstep(0.9, 0.2, age);

    // Ember color: white-hot → amber → ash (richer than flat orange)
    let hotCore = vec3<f32>(1.0, 0.95, 0.75);
    let amber = vec3<f32>(1.0, 0.42, 0.08);
    let coolAsh = vec3<f32>(0.22, 0.08, 0.04);
    let emberCol = mix(mix(hotCore, amber, smoothstep(0.0, 0.35, age)), coolAsh, smoothstep(0.35, 1.0, age));
    let glow = pow(intensity, 1.6) * (0.9 + bass * 0.4 + furnaceMask * 0.35);

    // Composite: original darkens as embers lift, bright embers added on top
    var col = input.rgb * (1.0 - intensity * 0.65);
    col += emberCol * glow * 1.6;

    // White-hot ignition core on fresh click / furnace fires
    col += hotCore * flash * 0.95;

    // Faint cursor glow lift — the pointer's heat plume shimmers
    col += emberCol * (mouseMask * 0.08 * emberMask) * 1.6;
    col += hotCore * furnaceMask * 0.22 * emberMask;

    // Band crackle flashes + cooler ash wisps
    col += emberCol * crackle * 0.4;
    col += coolAsh * ashWisp * 0.55;

    // Heat haze on rising areas
    let haze = intensity * 0.12 * (1.0 - depth);
    col = mix(col, col + vec3<f32>(0.15, 0.08, 0.02), haze);

    // ACES on display path only
    col = acesToneMap(col * (1.05 + bass * 0.15));

    // Semantic alpha — embers are ethereal and glow
    let semantic_alpha = clamp(0.55 + glow * 0.65 + intensity * 0.3 + furnaceMask * 0.1, 0.4, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, semantic_alpha));

    // Write new ember state for next frame — NEVER tonemap A
    textureStore(dataTextureA, pixel, vec4<f32>(age, lateral, intensity, glow));

    // Depth from ember height in scene
    let d = clamp(0.2 + intensity * 0.55, 0.0, 0.96);
    textureStore(writeDepthTexture, pixel, vec4<f32>(d, 0.0, 0.0, 0.0));
}
