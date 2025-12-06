// =============================================================
//  Bioluminescent‑style “foreground warp” – depth‑aware version
// =============================================================
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
// ---------------------------------------------------

struct Uniforms {
  // x = time, y = rippleCount, z = resX, w = resY
  config: vec4<f32>,
  // x = foregroundDepth, y = depthFalloff,
  // z = parallaxStrength, w = (reserved)
  zoom_config: vec4<f32>,
  // x = speed, y = density, z = intensity, w = colourShift
  zoom_params: vec4<f32>,
  // ripples: x = uv.x, y = uv.y, z = startTime, w = unused
  ripples: array<vec4<f32>, 50>,
};

// ---------------------------------------------------
// Helper: 3×3 min‑depth kernel (cheap, works on any GPU)
// ---------------------------------------------------
fn min_depth_3x3(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    var minD = 1.0;
    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
        for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * texel;
            let d = textureSampleLevel(readDepthTexture,
                                      non_filtering_sampler,
                                      uv + offset, 0.0).r;
            minD = min(minD, d);
        }
    }
    return minD;
}

// ---------------------------------------------------
// Main
// ---------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ---------------------------------------------------
    // 1️⃣  Gather basic data
    // ---------------------------------------------------
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // ---------------------------------------------------
    // 2️⃣  Read original depth & colour
    // ---------------------------------------------------
    let depth          = textureSampleLevel(readDepthTexture,
                                            non_filtering_sampler,
                                            uv, 0.0).r;
    let baseColour     = textureSampleLevel(readTexture,
                                            u_sampler,
                                            uv, 0.0).rgb;

    // ---------------------------------------------------
    // 3️⃣  Compute a *foreground mask* based on the nearest depth
    // ---------------------------------------------------
    let nearestDepth   = min_depth_3x3(uv, texel);
    let fgDepthThresh  = u.zoom_config.x;   // user‑controlled threshold
    let fgFalloff      = u.zoom_config.y;   // soft edge width
    // mask = 1.0 → definitely foreground, 0.0 → definitely background
    let fgMask = smoothstep(fgDepthThresh - fgFalloff,
                            fgDepthThresh + fgFalloff,
                            nearestDepth);

    // ---------------------------------------------------
    // 4️⃣  Ambient “background waver” (only visible where depth is far)
    // ---------------------------------------------------
    var ambientDisp = vec2<f32>(0.0);
    // Background factor = 1 for far objects, 0 for near objects
    let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);
    if (backgroundFactor > 0.0) {
        let t      = time * 0.5;
        let freq   = 15.0;
        let motion = vec2<f32>( sin(uv.y * freq + t * 1.2),
                                cos(uv.x * freq + t) );
        ambientDisp = motion * 0.02 * backgroundFactor;
    }

    // ---------------------------------------------------
    // 5️⃣  Mouse‑ripple displacement (the part that *actually* moves geometry)
    // ---------------------------------------------------
    var mouseDisp = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age    = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let dir   = uv - ripple.xy;
            let dist  = length(dir);
            if (dist > 0.0001) {
                // Depth at the click position – used to make near clicks stronger
                let clickDepth = textureSampleLevel(readDepthTexture,
                                                   non_filtering_sampler,
                                                   ripple.xy, 0.0).r;
                // Inverse depth (0 = far, 1 = near) → stronger effect for nearer clicks
                let depthFactor = 1.0 - clickDepth;
                let speed  = mix(1.0, 2.0, depthFactor);
                let amp    = mix(0.005, 0.015, depthFactor);
                let wave   = sin(dist * 25.0 - age * speed);
                let atten  = 1.0 - smoothstep(0.0, 1.0, age / (3.0 * mix(0.5, 1.0, depthFactor)));
                let fall   = 1.0 / (dist * 20.0 + 1.0);
                mouseDisp += (dir / dist) * wave * amp * fall * atten;
            }
        }
    }

    // ---------------------------------------------------
    // 6️⃣  Parallax “slow background warp” (pure visual, no depth change)
    // ---------------------------------------------------
    let parallaxTime   = time * 0.2;
    let parallaxStrength = u.zoom_config.z; // user‑controlled (default ≈0.03)
    let parallaxFreq   = 2.0;
    let parallaxDisp   = vec2<f32>(
        sin(uv.y * parallaxFreq + parallaxTime) * parallaxStrength,
        cos(uv.x * parallaxFreq + parallaxTime) * parallaxStrength
    );

    // ---------------------------------------------------
    // 7️⃣  Combine everything – *only the foreground gets the final warp*
    // ---------------------------------------------------
    // The background parallax is blended in with the colour only,
    // because it does NOT affect geometry.
    let colourDisp = ambientDisp + mouseDisp + (parallaxDisp * (1.0 - fgMask));
    // The geometry‑changing part is *only* mouseDisp (the ripple)
    let geometryDisp = mouseDisp;

    // Apply the mask – foreground only
    let finalColourUV = uv + colourDisp * fgMask;
    let finalDepthUV  = uv + geometryDisp * fgMask;

    // ---------------------------------------------------
    // 8️⃣  Sample colour & depth at the displaced coordinates
    // ---------------------------------------------------
    let warpedColour = textureSampleLevel(readTexture,
                                         u_sampler,
                                         finalColourUV, 0.0).rgb;
    let warpedDepth  = textureSampleLevel(readDepthTexture,
                                         non_filtering_sampler,
                                         finalDepthUV, 0.0).r;

    // ---------------------------------------------------
    // 9️⃣  Blend with the original image so the effect fades at the mask edge
    // ---------------------------------------------------
    // Linear blend works fine because fgMask already has a smoothstep edge.
    let outColour = mix(baseColour, warpedColour, fgMask);
    let outDepth  = mix(depth, warpedDepth, fgMask);

    // ---------------------------------------------------
    // 10️⃣  Write results
    // ---------------------------------------------------
    textureStore(writeTexture, global_id.xy, vec4<f32>(outColour, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
