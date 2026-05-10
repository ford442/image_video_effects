// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Cross — May 2026 Batch D Upgrade
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Upgraded: 2026-05-10
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

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = get_mouse();
    let time = u.config.x;

    let hStretch = u.zoom_params.x * 0.3;
    let vStretch = u.zoom_params.y * 0.3;
    let depthInfluence = u.zoom_params.z;
    let turbulence = u.zoom_params.w;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Depth-aware stretch: greater depth = less stretch
    let depthFactor = 1.0 - depth * depthInfluence;

    // Bass → stretch magnitude
    let stretchScale = 1.0 + bass * 0.5;

    var accum = vec3<f32>(0.0);
    var weight = 0.0;
    var maxStretch = 0.0;

    // Fibonacci disk sampling for multi-direction stretch
    let numSamples = 16;
    let goldenAngle = 2.39996322972865332;

    for (var i: i32 = 0; i < numSamples; i = i + 1) {
        let fi = f32(i) + 0.5;
        let r = sqrt(fi / f32(numSamples));
        let theta = fi * goldenAngle;

        let dir = vec2<f32>(cos(theta), sin(theta));
        let aniso = mix(hStretch, vStretch, abs(dir.y));
        let stretchBand = aniso * stretchScale * depthFactor;

        let toMouse = uv - mouse;
        let parallel = dot(toMouse, dir);
        let perp = toMouse - dir * parallel;
        let perpDist = length(perp);

        let inBand = 1.0 - smoothstep(0.0, stretchBand * (1.0 + turbulence * 0.5), perpDist);

        if (inBand > 0.01) {
            let decay = 10.0 + turbulence * 10.0 + mids * 5.0;
            let alongDist = abs(parallel);
            let factor = exp(-alongDist * decay) * inBand;

            let sampleUv = mouse + dir * parallel;
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUv, 0.0).rgb;

            accum += sampleColor * factor;
            weight += factor;
            maxStretch = max(maxStretch, factor);
        }
    }

    var color = src.rgb;
    if (weight > 0.001) {
        let smearColor = accum / weight;
        color = mix(color, smearColor, min(weight * 2.0, 1.0));
    }

    // Effect-mask alpha: high stretch = slight transparency
    let alpha = src.a * (1.0 - maxStretch * 0.25);

    // Center hot spot with treble shimmer
    let centerDist = length(uv - mouse);
    let hotSpot = exp(-centerDist * 18.0) * 0.3 * (hStretch + vStretch) * stretchScale * (1.0 + treble * 0.5);
    color += src.rgb * hotSpot;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
