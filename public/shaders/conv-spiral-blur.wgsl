// ═══════════════════════════════════════════════════════════════════
//  Spiral Blur
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, depth-aware, temporal
//  Convolution Type: logarithmic-spiral-convolution
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Accumulated color along the logarithmic spiral (HDR, can exceed 1.0)
//    Alpha: Spiral energy — rotational motion intensity modulated by
//           audio and depth, indicating how much the pixel was "swept."
//
//  Samples along a logarithmic spiral centered on each pixel. Creates
//  rotational motion blur following a golden ratio spiral.
//
//  MOUSE INTERACTIVITY:
//    Mouse position controls the spiral center. Near mouse = tighter spiral,
//    far from mouse = wider arms. Creates a vortex-like pull effect.
//    Ripples inject transient spiral arm distortions.
//
//  UPGRADES: ACES tone mapping, chromatic aberration on spiral arms,
//    plasmaBuffer bass-driven spiral tightness/rotation, dataTextureC temporal
//    spiral persistence, depth-based blur radius, semantic alpha.
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

const PHI: f32 = 1.61803398874989484820;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let pixel = vec2<i32>(global_id.xy);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Depth for blur radius modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = smoothstep(0.0, 1.0, depth);

    // Parameters
    let spiralTightness = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + bass * 0.4);
    let numArms = mix(1.0, 5.0, u.zoom_params.y);
    let sampleCount = i32(mix(16.0, 48.0, u.zoom_params.z));
    let mouseInfluence = u.zoom_params.w;

    // Spiral center from mouse
    let spiralCenter = mix(vec2<f32>(0.5), mousePos, mouseInfluence);

    // Ripple spiral distortions
    var rippleTwist = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.2) * 10.0, 2.0));
            rippleTwist = rippleTwist + wave * (1.0 - rElapsed / 3.0) * 2.0;
        }
    }

    // Convert to polar around spiral center
    let relPos = uv - spiralCenter;
    let r = length(relPos);
    let theta = atan2(relPos.y, relPos.x);

    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    var coverage = 0.0;
    var maxArmDist = 0.0;

    let maxSamples = min(sampleCount, 40);
    let depthBlurFactor = mix(1.0, 0.3, depthFactor);

    for (var arm = 0; arm < i32(numArms); arm++) {
        let armOffset = f32(arm) * 6.28318 / numArms + bass * 0.2;

        for (var s = 0; s < maxSamples; s++) {
            let t = f32(s) / f32(maxSamples);
            let spiralR = t * 0.15 * exp(spiralTightness * 3.0) * depthBlurFactor;
            let spiralTheta = theta + armOffset + t * 6.28318 * 2.0 + rippleTwist * t + time * 0.1 * (1.0 + bass);

            let sampleOffset = vec2<f32>(
                spiralR * cos(spiralTheta),
                spiralR * sin(spiralTheta)
            );

            let sampleUV = uv + sampleOffset;
            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) { continue; }

            let w = exp(-t * 3.0) * (1.0 - t * 0.5);
            let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            accumColor += sample * w;
            accumWeight += w;
            coverage += 1.0;
            maxArmDist = max(maxArmDist, t);
        }
    }

    var result = vec3<f32>(0.0);
    if (accumWeight > 0.001) {
        result = accumColor / accumWeight;
    } else {
        result = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }

    let coverageFactor = coverage / (f32(numArms) * f32(maxSamples));

    // Golden ratio color enhancement
    let goldenAngle = theta * PHI + time * 0.1;
    let goldenColor = vec3<f32>(
        0.5 + 0.5 * cos(goldenAngle),
        0.5 + 0.5 * cos(goldenAngle + 2.094),
        0.5 + 0.5 * cos(goldenAngle + 4.189)
    );
    result = mix(result, result * goldenColor * 1.5, coverageFactor * 0.3);

    // Chromatic aberration on spiral arms
    let caStrength = maxArmDist * 0.015 + treble * 0.005;
    let caDir = vec2<f32>(cos(theta + time), sin(theta + time));
    let rUV = uv + caDir * caStrength;
    let bUV = uv - caDir * caStrength;
    let rSample = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let chromatic = vec3<f32>(rSample, result.g, bSample);
    result = mix(result, chromatic, clamp(caStrength * 25.0, 0.0, 0.45));

    // Temporal spiral persistence
    let prevFrame = textureLoad(dataTextureC, pixel, 0);
    let temporalDecay = mix(0.5, 0.8, depthFactor);
    result = mix(result, prevFrame.rgb, temporalDecay * 0.12);

    // ACES tone mapping
    result = acesToneMap(result * (1.0 + mids * 0.3));

    // Semantic alpha: spiral energy modulated by coverage and depth
    let spiralEnergy = clamp(coverageFactor * 1.5 + maxArmDist * 0.5, 0.0, 1.0);
    let semanticAlpha = mix(spiralEnergy, 0.2, depthFactor * 0.5);

    textureStore(writeTexture, global_id.xy, vec4<f32>(result, semanticAlpha));

    // Depth pass-through
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
