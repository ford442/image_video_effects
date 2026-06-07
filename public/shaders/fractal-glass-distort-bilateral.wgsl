// ═══════════════════════════════════════════════════════════════════
//  fractal-glass-distort-bilateral
//  Category: advanced-hybrid
//  Features: fractal-glass-distortion, bilateral-filter, mouse-driven
//  Complexity: Very High
//  Chunks From: fractal-glass-distort.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Recursive fractal glass rotation layered with an adaptive bilateral
//  dream filter. The glass distortion creates recursive depth while the
//  bilateral smooths with edge-preservation. Mouse controls the lens
//  center and creates a sharp-focus zone surrounded by dreamy blur.
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

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Parameters
    let rot_speed = u.zoom_params.x * 3.14159;
    let scale_base = mix(0.9, 1.3, u.zoom_params.y);
    let refract_str = mix(0.0, 0.05, u.zoom_params.z);
    let bilateralMix = u.zoom_params.w;

    let aspect = u.config.z / u.config.w;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouse_p = (mousePos - 0.5) * vec2<f32>(aspect, 1.0);

    // Fractal glass distortion
    var total_disp = vec2<f32>(0.0);
    var curr_p = p;
    for (var i = 0; i < 4; i++) {
        let rel_p = curr_p - mouse_p;
        let angle = rot_speed * (f32(i) + 1.0) * 0.3;
        let rotated = rotate(rel_p, angle);
        let sine_warp = vec2<f32>(
            sin(rotated.y * 10.0 + time),
            cos(rotated.x * 10.0 + time)
        );
        total_disp = total_disp + sine_warp * refract_str / (f32(i) + 1.0);
        curr_p = rotated * scale_base + mouse_p;
    }

    let final_p = p + total_disp;
    let distortedUV = final_p / vec2<f32>(aspect, 1.0) + 0.5;

    // Sample distorted image
    let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Bilateral filter on the distorted result
    // Mouse distance modulates sigma: near = sharp, far = dreamy
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0);
    let spatialSigmaBase = mix(0.1, 1.0, bilateralMix);
    let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);
    let colorSigma = 0.3;

    // Ripple shockwaves sharpen the image
    var rippleSharpness = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rElapsed = time - ripple.z;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - ripple.xy);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
            rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
        }
    }
    let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);

    let radius = i32(ceil(finalSigma * 2.5));
    let maxRadius = min(radius, 5);
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, distortedUV + offset, 0.0);
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
            let colorDist = length(neighbor.rgb - distortedColor.rgb);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
        }
    }

    var result = distortedColor.rgb;
    if (accumWeight > 0.001) {
        result = mix(distortedColor.rgb, accumColor / accumWeight, bilateralMix);
    }

    // Subtle chromatic aberration on edges
    let aberration = 0.03 * bilateralMix;
    let r_uv = distortedUV + vec2<f32>(aberration, 0.0);
    let b_uv = distortedUV - vec2<f32>(aberration, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = result.g;
    let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
    result = vec3<f32>(r, g, b);

    textureStore(writeTexture, global_id.xy, vec4<f32>(result, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
