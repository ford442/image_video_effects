// ═══════════════════════════════════════════════════════════════
//  Nebulous Dream - Volumetric Alpha Upgrade
//  Category: artistic
//  Features: volumetric, depth-aware, temporal-feedback, mouse-driven, upgraded-rgba
//  Upgraded: 2026-11-01
//  Ideas: smooth value-noise fbm; dust-lane extinction (per-channel Beer-Lambert reddening from the warp field); ionisation-front rim (fbm gradient at density edges); embedded stars dimmed by dust; pointer stirs the existing warp
//  A packing: linear pre-ACES colour + alpha history; ACES on writeTexture only
//  A swirling vortex of rainbow candy clouds with physically-based
//  volumetric density and optical depth rendering.
//  
//  Scientific Implementation:
//  - FBM-generated density field with optical depth accumulation
//  - Beer-Lambert extinction for realistic cloud edges
//  - Flow-field warping with volumetric blending
//  - Temporal accumulation with density-based trails
// ═══════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Volumetric constants for nebula clouds
const SIGMA_T_NEBULA: f32 = 1.5;        // Nebula extinction
const SIGMA_S_NEBULA: f32 = 1.3;        // Scattering albedo
const STEP_SIZE: f32 = 0.02;            // Ray step through cloud

// ═══════════════════════════════════════════════════════════════
//  Noise & Color Utilities
// ═══════════════════════════════════════════════════════════════
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + (dot(p3, p3 + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
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

// Fractal Brownian Motion (FBM) for cloud noise
// Idea 1: smooth value noise. HEAD summed raw hash21 samples, i.e. per-pixel
// static instead of billowing cloud.
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 2.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amplitude * (vnoise(p * frequency) - 0.5);
        frequency = frequency * 2.1;
        amplitude = amplitude * 0.5;
    }
    return value;
}

// ═══════════════════════════════════════════════════════════════
//  Main Compute
// ═══════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;

    // ═══════════════════════════════════════════════════════════════
    //  Parameters. HEAD declared its own struct with zoom_params/zoom_config
    //  swapped, so the sliders were mis-routed (cloud scale was driven by
    //  time, flow/colour/persistence by the mouse). Roles now follow the
    //  saved JSON names; the four formerly-slider constants are fixed.
    // ═══════════════════════════════════════════════════════════════
    let cloudScale = u.zoom_params.x * 9.0 + 1.0;           // 1 - 10
    let flowSpeed = u.zoom_params.y * 0.4;                   // 0 - 0.4
    let colorSpeed = u.zoom_params.z * 0.2;                  // 0 - 0.2
    let persistence = u.zoom_params.w * 0.95;                // 0 - 0.95
    let cloudSharpness = 0.08;
    let satBoost = 1.0;
    let depthInf = 0.5;
    let blendStrength = 0.55;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Sample depth for depth-aware effects
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══════════════════════════════════════════════════════════════
    //  Create a swirling flow field
    // ═══════════════════════════════════════════════════════════════
    let flow_uv = uv * cloudScale * 0.3;
    let q = vec2<f32>(
        fbm(flow_uv + time * flowSpeed * 0.1),
        fbm(flow_uv + vec2<f32>(5.2, 1.3) + time * flowSpeed * 0.15)
    );
    
    // Use another FBM layer to stir the first one
    let r_uv = uv * cloudScale * 1.2 + q * 2.5;
    let r = vec2<f32>(
        fbm(r_uv + time * flowSpeed * 0.2),
        fbm(r_uv + vec2<f32>(8.3, 2.8) + time * flowSpeed * 0.25)
    );
    
    // Depth influences distortion amount
    let depthDistort = 1.0 + (1.0 - depth) * depthInf * 0.5;
    
    // Final distorted UV for sampling the clouds
    // Pointer stirs the existing warp: a gentle vortex around the cursor
    let dm = uv - mouse;
    let stir = vec2<f32>(-dm.y, dm.x) * exp(-dot(dm, dm) * 14.0) * (0.04 + 0.46 * mouseDown);
    let distortedUV = uv + q * 0.2 * depthDistort + r * 0.1 * depthDistort + stir;
    
    // ═══════════════════════════════════════════════════════════════
    //  Generate the Cloud Density with Volumetric Properties
    // ═══════════════════════════════════════════════════════════════
    let cloudNoise = fbm(distortedUV * cloudScale);
    
    // Reshape the noise to create billowy cloud shapes
    let rawDensity = smoothstep(0.0, cloudSharpness + 0.1, abs(cloudNoise) * 3.0);
    
    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Light Transport
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate optical depth
    let opticalDepth = rawDensity * STEP_SIZE * SIGMA_T_NEBULA;
    
    // Transmittance (Beer-Lambert): T = exp(-τ)
    let transmittance = exp(-opticalDepth);
    
    // Volumetric alpha: α = 1 - T
    let alpha = 1.0 - transmittance;
    
    // Effective density for rendering (0-1 range)
    let cloudDensity = rawDensity;

    // ═══════════════════════════════════════════════════════════════
    //  Generate Rainbow Candy Colors (In-scattered Light)
    // ═══════════════════════════════════════════════════════════════
    let baseHue = fract(distortedUV.x + distortedUV.y * 0.5 + time * colorSpeed);
    
    // Read the source video to influence the colors
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(srcColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // In bright areas, make clouds more saturated and brighter
    let saturation = mix(0.7, satBoost, luminance);
    var value = mix(0.5, 1.0, luminance);
    
    // In-scattered light color (rainbow cloud)
    let cloudColor = hsv2rgb(baseHue, saturation, value);

    // ═══════════════════════════════════════════════════════════════
    //  Blend Clouds with Source Video
    // ═══════════════════════════════════════════════════════════════
    // Blend based on cloud density (alpha) and luminance
    let blendFactor = cloudDensity * smoothstep(0.1, 0.5, luminance) * blendStrength;
    
    // In-scattered light from cloud
    let inScattered = cloudColor * blendFactor * SIGMA_S_NEBULA;
    
    // ── Idea 2: dust-lane extinction. The warp magnitude |q| already computed
    // for the flow is reused as a dust column; per-channel Beer-Lambert
    // absorbs blue most, reddening the light behind a lane.
    let dust = smoothstep(0.08, 0.32, length(q)) * (1.0 - 0.5 * rawDensity);
    let dustT = exp(-dust * vec3<f32>(0.45, 0.85, 1.4));

    // ── Idea 3: ionisation-front rim. Gradient of the same fbm field: the
    // bright rim where hot gas meets the dust-bounded edge of a cloud.
    let np = distortedUV * cloudScale;
    let gx = fbm(np + vec2<f32>(0.02, 0.0)) - cloudNoise;
    let gy = fbm(np + vec2<f32>(0.0, 0.02)) - cloudNoise;
    let rim = clamp(length(vec2<f32>(gx, gy)) * 14.0, 0.0, 1.0) * cloudDensity;
    let rimColor = hsv2rgb(fract(baseHue + 0.45), 0.55, 1.0);

    // ── Idea 4: embedded stars, dimmed by the dust column and the cloud
    let sp = uv * vec2<f32>(dims.x / dims.y, 1.0) * 80.0;
    let cellId = floor(sp);
    let starH = hash21(cellId);
    let starPos = vec2<f32>(hash21(cellId + 7.1), hash21(cellId + 3.3)) * 0.6 + 0.2;
    let starD = length(fract(sp) - starPos);
    let twinkle = 0.75 + 0.25 * sin(time * 3.0 + starH * 40.0);
    let stars = step(0.975, starH) * exp(-starD * starD * 90.0) * twinkle;

    // Transmitted source color (dust-reddened)
    let transmitted = srcColor * transmittance * dustT;

    // Volumetric blend
    let blendedColor = inScattered * mix(vec3<f32>(1.0), dustT, 0.5) + transmitted
                     + rimColor * rim * 0.35 * blendStrength
                     + vec3<f32>(1.0, 0.92, 0.85) * stars * dustT.g * (1.0 - 0.7 * cloudDensity);
    
    // ═══════════════════════════════════════════════════════════════
    //  Feedback Loop for Smoky Trails
    // ═══════════════════════════════════════════════════════════════
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    let prevFrame = prev.rgb;
    let prevAlpha = prev.a;
    
    // Blend the current frame with the dimmed previous frame
    let temporalBlend = 0.7 + persistence * 0.25;
    let finalColor = mix(blendedColor, prevFrame, persistence);
    let finalAlpha = mix(alpha, prevAlpha, persistence * 0.5);
    
    // Store this frame's result for the next frame
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));

    // ═══════════════════════════════════════════════════════════════
    //  Output with Volumetric Alpha
    // ═══════════════════════════════════════════════════════════════
    let hdr = max(finalColor, vec3<f32>(0.0));
    let display = clamp((hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(display, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, opticalDepth, 0.0, finalAlpha));
}
