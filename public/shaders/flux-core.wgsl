// --- FLUX CORE ---
// Electrical arc reactor anchored to the cursor: fbm-perturbed lightning bolts
// conduct through bright areas of the source image.
// Features: electrical, arcs, glow, distortion, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-10
//  Ideas: luma-gradient steering; forked branches; ionization contact tint
//  A packing: ACES display RGBA

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    // Rotation matrix
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);

    // Uniforms
    let time = u.config.x;
    var mouse = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let aspect = f32(dims.x) / f32(dims.y);

    // Adjust UV for aspect ratio for distance calcs
    var p = uv;
    let m = mouse;
    let p_aspect = vec2<f32>(p.x * aspect, p.y);
    let m_aspect = vec2<f32>(m.x * aspect, m.y);

    let dist = length(p_aspect - m_aspect);
    let angle = atan2(p_aspect.y - m_aspect.y, p_aspect.x - m_aspect.x);

    // Sample original image
    let baseColorSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseColor = baseColorSample.rgb;
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

    // Flux Core Effect
    // 1. Central Glow
    let glow = 0.05 / (dist + 0.001);

    // 2. Electrical Arcs
    // Use angle and distance to create lightning bolts emanating from center
    // Perturb angle with noise based on distance and time
    let angle_noise = fbm(vec2<f32>(dist * 5.0 - time * 2.0, angle * 2.0));
    // Idea 1: luma-gradient steering — the bolt bends toward brighter neighbours,
    // so arcs visibly seek out conductive (bright) edges in the plate.
    let px = 2.0 / vec2<f32>(dims);
    let lw = vec3<f32>(0.299, 0.587, 0.114);
    let gx = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb - textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb, lw);
    let gy = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb - textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb, lw);
    let tangent = vec2<f32>(-sin(angle), cos(angle));
    let steer = dot(vec2<f32>(gx, gy), tangent) * (2.0 + u.zoom_params.y * 6.0);
    let bolt_path = abs(sin(angle * (10.0 + mids * 6.0) + angle_noise * 5.0 + steer));

    // Sharpen the bolt — bass widens the arc so beats throw thicker lightning
    let arcSharp = mix(0.9, 0.98, u.zoom_params.x);
    let boltEdge = arcSharp - bass * 0.08;
    let mainBolt = smoothstep(boltEdge, boltEdge + 0.03, bolt_path);
    // Idea 2: forked branches — a thinner, faster-flickering bolt that only
    // exists where the main arc is already near, so it reads as forking.
    let branchNoise = fbm(vec2<f32>(dist * 11.0 - time * 3.7, angle * 5.0 + 7.0));
    let branchPath = abs(sin(angle * (23.0 + mids * 9.0) + branchNoise * 9.0 + steer * 1.5));
    let nearMain = smoothstep(boltEdge - 0.25, boltEdge, bolt_path);
    let branch = smoothstep(arcSharp + 0.01, arcSharp + 0.02, branchPath) * nearMain * smoothstep(0.03, 0.12, dist);
    let bolt = max(mainBolt, branch * 0.6);

    // Fade bolts with distance, but allow them to connect to bright spots
    // If luma is high, the bolt can travel further or be brighter
    let conductivity = luma * mix(1.0, 4.0, u.zoom_params.y);
    let attenuation = smoothstep(0.5 + conductivity * 0.5, 0.0, dist);

    // Bolt Color
    let fluxColor = vec3<f32>(0.4, 0.8, 1.0); // Cyan
    let hotColor = vec3<f32>(1.0, 1.0, 1.0); // White core

    // Idea 3: ionization tint — where the arc strikes a bright surface the
    // discharge shifts violet (contact plasma) instead of open-air cyan.
    let contact = smoothstep(0.55, 0.9, luma) * bolt;
    let arcColor = mix(fluxColor, vec3<f32>(0.75, 0.45, 1.0), contact);
    var finalBolt = mix(arcColor, hotColor, mainBolt) * bolt * attenuation * 5.0 + arcColor * contact * attenuation * 1.5;

    // 3. Distortion Shockwave
    // Distort the background image based on the bolt intensity
    let distort = bolt * mix(0.0, 0.05, u.zoom_params.w) * (1.0 / (dist + 0.1));
    let distortedUV = uv + vec2<f32>(cos(angle), sin(angle)) * distort;

    let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

    // 4. Combine
    // Add bolts to distorted image
    // Mouse hover adds extra energy
    let energy = 1.0 + sin(time * 10.0) * 0.2 + bass * 0.8;

    var finalColor = distortedColor + finalBolt * energy;

    // Add central core — bass detonates the core
    let coreIntensity = mix(0.5, 3.0, u.zoom_params.z);
    finalColor += hotColor * smoothstep(0.05 + bass * 0.04, 0.0, dist) * 2.0 * (1.0 + bass) * coreIntensity;
    finalColor += fluxColor * glow * 0.5 * (1.0 + bass * 0.6) * coreIntensity;

    // Alpha: electrical energy above the source plate
    let boltEnergy = bolt * attenuation + smoothstep(0.05, 0.0, dist);
    let alpha = clamp(baseColorSample.a + boltEnergy * (0.5 + bass * 0.5), 0.0, 1.0);
    let outColor = vec4<f32>(acesToneMap(max(finalColor, vec3<f32>(0.0))), alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
