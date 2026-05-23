// ═══════════════════════════════════════════════════════════════════
//  Liquid (Interactive)
//  Category: image
//  Features: mouse-driven, capillary-waves, fluid-transparency, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-03-15
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265358979323846;

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn proceduralHeight(
    uv: vec2<f32>,
    currentTime: f32,
    surfaceTension: f32,
    backgroundFactor: f32,
    bass: f32,
    mids: f32
) -> f32 {
    var h = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rippleData = u.ripples[i];
        let timeSinceClick = currentTime - rippleData.z;
        let rippleActive = f32(timeSinceClick > 0.0 && timeSinceClick < 3.0);
        let dist = distance(uv, rippleData.xy);
        let validDist = f32(dist > 0.0001);
        let contribMask = rippleActive * validDist;
        let phase = dist * 20.0 - timeSinceClick * 5.0;
        let packetWidth = 0.3 + timeSinceClick * 0.1;
        let envelope = exp(-(dist * dist) / (packetWidth * packetWidth));
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 2.5);
        let amp = 0.01 * attenuation * envelope;
        h += sin(phase) * amp * contribMask;
    }
    let time = currentTime * 0.5;
    let ambientFreq = 25.0 + mids * 15.0;
    let wave1 = sin(uv.x * ambientFreq + time * 2.0);
    let wave2 = sin(uv.y * ambientFreq * 1.3 + time * 1.7);
    let wave3 = sin((uv.x + uv.y) * ambientFreq * 0.7 + time * 2.3);
    let wave4 = sin(length(uv - vec2<f32>(0.5)) * ambientFreq * 1.5 - time * 3.0);
    h += (wave1 + wave2 * 0.5 + wave3 * 0.3 + wave4 * 0.2) * 0.003 * surfaceTension * backgroundFactor;
    let audioDist = distance(uv, vec2<f32>(0.5));
    let audioWave = sin(audioDist * 30.0 - currentTime * 8.0) * exp(-audioDist * 3.0);
    h += audioWave * bass * 0.015 * backgroundFactor;
    return h;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;
    let pixelSize = vec2<f32>(1.0) / resolution;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

    let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
    let gravityScale = (u.zoom_params.y * 2.0 + 0.5) * (1.0 + bass * 0.4);
    let damping = u.zoom_params.z * 0.15 + 0.02;
    let turbidity = u.zoom_params.w;

    let heightScale = 0.5 * surfaceTension;
    let hCenter = proceduralHeight(uv, currentTime, surfaceTension, backgroundFactor, bass, mids);
    let hLeft = proceduralHeight(uv - vec2<f32>(pixelSize.x, 0.0), currentTime, surfaceTension, backgroundFactor, bass, mids);
    let hRight = proceduralHeight(uv + vec2<f32>(pixelSize.x, 0.0), currentTime, surfaceTension, backgroundFactor, bass, mids);
    let hBottom = proceduralHeight(uv - vec2<f32>(0.0, pixelSize.y), currentTime, surfaceTension, backgroundFactor, bass, mids);
    let hTop = proceduralHeight(uv + vec2<f32>(0.0, pixelSize.y), currentTime, surfaceTension, backgroundFactor, bass, mids);

    let dx = (hRight - hLeft) * heightScale;
    let dy = (hTop - hBottom) * heightScale;
    let normal = normalize(vec3<f32>(-dx, -dy, 2.0));

    let refractionStrength = 0.02 * surfaceTension;
    let refractDisplacement = normal.xy * refractionStrength * backgroundFactor;
    let totalDisplacement = refractDisplacement + vec2<f32>(hCenter * 0.01);

    let colorUV = clamp(uv + totalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let baseColor = textureSampleLevel(readTexture, u_sampler, colorUV, 0.0).rgb;

    let curvature = (hLeft + hRight + hBottom + hTop - 4.0 * hCenter);
    let laplacePressure = abs(curvature) * surfaceTension * 2.0;
    let specular = pow(max(0.0, normal.z), 20.0) * laplacePressure * 0.3 * (1.0 + treble * 0.5);

    let liquidThickness = abs(hCenter) * 2.0 + 0.1;

    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let viewDotNormal = dot(viewDir, normal);

    let F0 = 0.02;
    let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);

    let effectiveDepth = liquidThickness * (1.0 + turbidity * 2.0);
    let absorptionR = exp(-effectiveDepth * 2.0);
    let absorptionG = exp(-effectiveDepth * 1.6);
    let absorptionB = exp(-effectiveDepth * 1.2);
    let absorption = (absorptionR + absorptionG + absorptionB) / 3.0;

    let heightTint = vec3<f32>(0.0, 0.1, 0.15) * hCenter * 0.5;
    let liquidColor = vec3<f32>(
        baseColor.r * absorptionR,
        baseColor.g * absorptionG + heightTint.g,
        baseColor.b * absorptionB + heightTint.b
    );

    let finalLiquidColor = liquidColor + vec3<f32>(specular);
    let baseAlpha = mix(0.3, 0.95, absorption * backgroundFactor);
    let alpha = baseAlpha * (1.0 - fresnel * 0.5);
    let finalAlpha = clamp(alpha, 0.0, 1.0);

    let finalColor = mix(baseColor, finalLiquidColor, finalAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
