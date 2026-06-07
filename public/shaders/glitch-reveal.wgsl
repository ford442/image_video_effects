// ═══════════════════════════════════════════════════════════════
//  Glitch Reveal - Block Scatter with Alpha Masking
//  Category: retro-glitch
//
//  Interactive reveal effect with block-based scattering:
//  - Grid-based block offset scattering
//  - Mouse proximity reveals unscattered image
//  - Channel shifting on scattered blocks
//  - Digital border with alpha masking
//  - Alpha preserved for reveal transitions
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let pixel = vec2<i32>(global_id.xy);

    // Depth awareness: foreground revealed from farther away
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Audio reactivity: bass drives scatter intensity, mids drive jitter
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let scatter = u.zoom_params.y * (1.0 + bass * 2.0);
    let blockSize = u.zoom_params.x * 0.2 + 0.01;
    let revealRadius = u.zoom_params.z * 0.5 + 0.05;
    let speed = u.zoom_params.w * 10.0;

    // Depth-based reveal radius
    let effectiveRadius = revealRadius * mix(0.6, 1.4, depth);

    // Grid coordinates with audio jitter
    let gridUV = floor(uv / blockSize);
    let seed = gridUV + floor(u.config.x * speed * (1.0 + mids));
    let rand = hash22(seed);

    var blockOffset = (rand - 0.5) * scatter;

    // Mouse proximity reveal
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    var mask = 0.0;
    if (dist < effectiveRadius) {
        mask = smoothstep(effectiveRadius * 0.8, effectiveRadius, dist);
    } else {
        mask = 1.0;
    }

    blockOffset = blockOffset * mask;

    let sampleUV = clamp(uv + blockOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic aberration (enhanced glitch)
    let caDir = (uv - 0.5) * 0.03 * mask * scatter * (1.0 + depth);
    let rSampleUV = clamp(sampleUV + caDir, vec2<f32>(0.0), vec2<f32>(1.0));
    let bSampleUV = clamp(sampleUV - caDir, vec2<f32>(0.0), vec2<f32>(1.0));

    var colorSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let rSample = textureSampleLevel(readTexture, u_sampler, rSampleUV, 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, bSampleUV, 0.0).b;
    var color = vec3<f32>(rSample, colorSample.g, bSample);
    var alpha = colorSample.a;

    if (mask > 0.01 && scatter > 0.0) {
         if (rand.x > 0.8) {
             let shiftSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.01 * mask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
             color = vec3<f32>(shiftSample.r, colorSample.g, colorSample.b);
             alpha = mix(colorSample.a, shiftSample.a * 0.9 + 0.1, mask * 0.3);
         } else if (rand.x < 0.2) {
             color = vec3<f32>(1.0 - colorSample.r, 1.0 - colorSample.g, 1.0 - colorSample.b);
             alpha = colorSample.a * 0.95;
         }
    }

    // Temporal glitch persistence from previous frame
    let prev = textureLoad(dataTextureC, pixel, 0);
    let persistence = 0.7;
    color = mix(color, prev.rgb, mask * scatter * persistence);

    // Digital border around reveal zone
    let border = smoothstep(effectiveRadius, effectiveRadius + 0.01, dist)
               - smoothstep(effectiveRadius + 0.01, effectiveRadius + 0.02, dist);
    if (border > 0.0 && mask < 0.9) {
        let borderColor = vec3<f32>(0.0, 1.0, 0.5);
        color = mix(color, borderColor, border * 0.5);
        alpha = mix(alpha, 1.0, border * 0.3);
    }

    // ACES tone mapping
    color = acesToneMap(color);

    // Semantic alpha: data integrity — scattered blocks transparent, revealed foreground solid
    alpha = mix(mix(0.5, 1.0, depth), 1.0, 1.0 - mask * scatter);
    alpha = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
