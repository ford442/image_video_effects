// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Volumetric Zoom Shader with Alpha Physics
//  Category: interactive-mouse
//  Features: volumetric layers, zoom effect, chromatic separation, upgraded-rgba
//  Upgraded: 2026-10-27
//  Ideas: depth-weighted layer parallax; flow-convergence caustics
//  A packing: ACES display RGBA; C unused
//
//  ALPHA PHYSICS:
//  - Layer depth affects opacity
//  - Fog density controls transparency falloff
//  - Source alpha is averaged across the sampled layers
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=fg_speed, y=bg_speed, z=parallax_str, w=fog_density

fn ping_pong(a: f32) -> f32 { return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0); }
fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> { return vec2<f32>(ping_pong(v.x), ping_pong(v.y)); }

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + (dot(p3, p3 + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// Reconstruct a simple normal from depth samples
fn reconstruct_normal(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    var resolution = vec2<f32>(u.config.z, u.config.w);
    let offset = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r - textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r - textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let n = vec3<f32>(-dx, -dy, 1.0);
    return normalize(n);
}

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Calculate volumetric alpha
fn calculateVolumetricAlpha(
    layerDepth: f32,
    fogDensity: f32,
    viewDotNormal: f32,
    accumulatedWeight: f32
) -> f32 {
  // Fresnel at volume boundaries
  let F0 = 0.03;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Fog density affects transparency
  let fogAmount = exp(-layerDepth * fogDensity * 3.0);
  
  // Deeper layers = more fog = more transparent
  let depthAlpha = mix(0.95, 0.4, fogAmount);
  
  // Accumulated weight affects opacity
  let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
  
  let alpha = depthAlpha * weightAlpha * (1.0 - fresnel * 0.2);
  
  return clamp(alpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    var resolution = vec2<f32>(u.config.z, u.config.w);
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    let zoom_time = u.zoom_config.x;
    let zoom_center = u.zoom_config.yz;

    let clickIntensity = u.zoom_config.w;

    var accumulatedColor = vec3<f32>(0.0);
    var accumulatedAlpha = 0.0;
    var accumulatedDepth = 0.0;
    var totalWeight = 0.0;

    let layers = 5;
    for (var i: i32 = 0; i < layers; i = i + 1) {
        let layerDepth = f32(i) / f32(layers - 1);
        let layerSpeed = mix(u.zoom_params.x, u.zoom_params.y, layerDepth);
        let layerZoom = 1.0 + fract(zoom_time * layerSpeed) * 4.0;

        // Vortex spin
        let toCenter = uv - zoom_center;
        let dist = length(toCenter);
        let vortexStrength = clickIntensity * 0.3 / (dist + 0.1);
        let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);
        let rotatedUV = vec2<f32>(cos(spinAngle) * toCenter.x - sin(spinAngle) * toCenter.y, sin(spinAngle) * toCenter.x + cos(spinAngle) * toCenter.y) + zoom_center;

        // Plasma flow
        let flowScale = 6.0;
        let flowSpeed = 0.15;
        let nX = noise(rotatedUV * flowScale + vec2<f32>(time * flowSpeed, 0.0));
        let nY = noise(rotatedUV * flowScale + vec2<f32>(0.0, time * flowSpeed));
        let flowUV = rotatedUV + vec2<f32>(nX, nY) * 0.015 * layerDepth;
        let flowDx = noise((rotatedUV + vec2<f32>(0.012, 0.0)) * flowScale + vec2<f32>(time * flowSpeed, 0.0));
        let flowDy = noise((rotatedUV + vec2<f32>(0.0, 0.012)) * flowScale + vec2<f32>(0.0, time * flowSpeed));
        let convergence = clamp((nX - flowDx + nY - flowDy) * 4.0, 0.0, 1.0);

        // Zoom and sample
        let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(flowUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let parallax = (flowUV - zoom_center) * (centerDepth - 0.5) * layerDepth * u.zoom_params.z * 0.12;
        let transformed = (flowUV + parallax - zoom_center) / layerZoom + zoom_center;
        let wrapped = ping_pong_v2(transformed);
        let sampleColor = textureSampleLevel(readTexture, u_sampler, wrapped, 0.0);
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped, 0.0).r;

        let density = exp(-layerDepth * 1.5);
        let weight = density * (1.0 + sampleDepth * 0.5);

        accumulatedColor = accumulatedColor + sampleColor.rgb * weight * (1.0 + convergence * layerDepth * 0.5);
        accumulatedAlpha = accumulatedAlpha + sampleColor.a * weight;
        accumulatedDepth = accumulatedDepth + sampleDepth * weight;
        totalWeight = totalWeight + weight;
    }

    let baseColor = accumulatedColor / max(totalWeight, 0.0001);
    let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

    // Chromatic separation
    let chroma = 0.006 * baseDepth * u.zoom_params.z;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let chromaticColor = baseColor + vec3<f32>(r.r - b.r, 0.0, b.b - r.b) * 0.15;

    // Edge glow
    let ps = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
    let edgeGlow = exp(-depthGrad * 30.0) * baseDepth * 2.0;

    let finalColor = chromaticColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    let fogDensity = u.zoom_params.w;
    let normal = reconstruct_normal(uv, baseDepth);
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let viewDotNormal = dot(viewDir, normal);
    
    // Average layer depth for alpha calculation
    let avgLayerDepth = 0.5;
    let normalizedWeight = totalWeight / f32(layers);
    
    // Calculate alpha
    let alpha = calculateVolumetricAlpha(avgLayerDepth, fogDensity, viewDotNormal, normalizedWeight) * accumulatedAlpha / max(totalWeight, 0.0001);
    
    // Fog
    let fog = exp(-baseDepth * fogDensity * 3.0);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outColor = mix(finalColor, fogColor, 1.0 - fog);

    
    let display = vec4<f32>(aces(max(outColor, vec3<f32>(0.0))), alpha);
    textureStore(writeTexture, vec2<u32>(gid.xy), display);
    textureStore(dataTextureA, vec2<u32>(gid.xy), display);
    textureStore(writeDepthTexture, vec2<u32>(gid.xy), vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
