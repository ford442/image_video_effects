// ═══════════════════════════════════════════════════════════════════
//  Chromatic Reaction-Diffusion
//  Category: advanced-hybrid
//  Features: advanced-hybrid, gray-scott-rd, multi-channel, chromatic-separation
//  Upgraded: 2026-11-01 (sonnet/batch-06, second pass)
//  Ideas: Turing morphogen wave dispersion, interfacial Marangoni shear, chemiluminescent boundary fluorescence; photo-seeded nucleation droplets, dispersive per-channel diffusivity, gel relief sheen
//  A packing: raw chemical states [newR, newG, newB, activity] in dataTextureA; writeTexture receives ACES display composite
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Clamped exact Laplacian kernel
fn laplacian9(coord: vec2<i32>, dims: vec2<i32>, channel: i32) -> f32 {
    var sum: f32 = 0.0;
    let kernel = array<f32, 9>(0.05, 0.2, 0.05, 0.2, -1.0, 0.2, 0.05, 0.2, 0.05);
    var k: i32 = 0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let neighbor = clamp(coord + vec2<i32>(i, j), vec2<i32>(0), dims - vec2<i32>(1));
            let sampleVal = textureLoad(dataTextureC, neighbor, 0)[channel];
            sum += sampleVal * kernel[k];
            k++;
        }
    }
    return sum;
}

fn hash21(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q += dot(q, q.yx + 33.33);
    return fract((q.x + q.y) * q.x);
}

fn reactDiffuse(current: f32, lap: f32, feed: f32, kill: f32, crossCoupling: f32, diffK: f32) -> f32 {
    let reaction = current * current * current;
    let diffusion = lap * diffK + crossCoupling * 0.05;
    let feedTerm = feed * (1.0 - current);
    let killTerm = (kill + feed) * current;
    
    return current + diffusion - reaction + feedTerm - killTerm;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    
    let dims = vec2<i32>(resolution);
    let id = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Parameters - separate feed rates for each channel with audio modulation
    let feedR = mix(0.01, 0.1, u.zoom_params.x) * (1.0 + bass * 0.2);
    let feedG = mix(0.02, 0.08, u.zoom_params.y) * (1.0 + mids * 0.15);
    let feedB = mix(0.005, 0.12, u.zoom_params.z) * (1.0 + treble * 0.25);
    let chromaticSep = mix(0.0, 0.03, u.zoom_params.w);
    
    // Kill rates derived from feed rates for complex Turing patterns
    let killR = feedR * 2.5 + 0.015;
    let killG = feedG * 2.2 + 0.02;
    let killB = feedB * 1.8 + 0.025;
    
    // Read current chemical states from dataTextureC
    let curState = textureLoad(dataTextureC, id, 0);
    let curR = curState.r;
    let curG = curState.g;
    let curB = curState.b;
    
    // Calculate Laplacian for each channel
    let lapR = laplacian9(id, dims, 0);
    let lapG = laplacian9(id, dims, 1);
    let lapB = laplacian9(id, dims, 2);
    
    // IDEA 1: Turing morphogen cross-gradient wave dispersion
    // Cross-channel chemical gradients couple to produce anisotropic wavebands
    let crossCouplingR = (lapG - lapB) * 0.3;
    let crossCouplingG = (lapB - lapR) * 0.3;
    let crossCouplingB = (lapR - lapG) * 0.3;

    // Reaction-diffusion update
    // IDEA 5: dispersive diffusivity — the three morphogens spread at different
    // speeds (R fast, B slow), so their fronts split into chromatic fringes
    // whose width scales with the chromatic slider.
    let disp = chromaticSep * 8.0;
    var newR = reactDiffuse(curR, lapR, feedR, killR, crossCouplingR, 0.2 * (1.0 + disp));
    var newG = reactDiffuse(curG, lapG, feedG, killG, crossCouplingG, 0.2);
    var newB = reactDiffuse(curB, lapB, feedB, killB, crossCouplingB, 0.2 * (1.0 - disp * 0.6));

    // IDEA 4: photo-seeded nucleation — drifting droplet sites precipitate
    // morphogen where the source image is bright, so patterns crystallise out
    // of the photo (and the dish never sits at the dead zero fixed point).
    let seedGrid = uv * vec2<f32>(aspect, 1.0) * 14.0;
    let seedCell = floor(seedGrid);
    let seedH = hash21(seedCell);
    let seedPhase = fract(time * 0.12 + seedH);
    let seedLum = dot(textureSampleLevel(readTexture, u_sampler, (seedCell + 0.5) / (vec2<f32>(aspect, 1.0) * 14.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let seedOn = step(seedPhase, 0.04) * step(0.35, seedH * 0.5 + seedLum * 0.7);
    let seedDist = length(fract(seedGrid) - vec2<f32>(0.5));
    let droplet = seedOn * smoothstep(0.32, 0.0, seedDist);
    newR += droplet * (0.45 + 0.4 * hash21(seedCell + 7.0));
    newG += droplet * (0.45 + 0.4 * hash21(seedCell + 13.0));
    newB += droplet * (0.45 + 0.4 * hash21(seedCell + 29.0));
    
    // Mouse injection with drag radius
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    if (mouseDist < 0.08) {
        let injection = (1.0 - mouseDist / 0.08) * (0.6 + bass * 0.4);
        newR += injection * 0.85;
        newG += injection * 0.65;
        newB += injection * 0.95;
    }

    // Click ripples disrupt the morphogen field with concentric shockwaves
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 3.0) {
            let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let rWave = sin(rDist * 35.0 - elapsed * 10.0) * exp(-elapsed * 1.2) * exp(-rDist * 2.5);
            let disturbance = max(rWave, 0.0) * 0.25;
            newR += disturbance * 0.5;
            newG += disturbance * 0.8;
            newB += disturbance * 1.0;
        }
    }
    
    newR = clamp(newR, 0.0, 1.0);
    newG = clamp(newG, 0.0, 1.0);
    newB = clamp(newB, 0.0, 1.0);
    let activity = abs(newR - curR) + abs(newG - curG) + abs(newB - curB);
    
    // Store raw chemical simulation state in dataTextureA (preserves simulation continuity)
    textureStore(dataTextureA, id, vec4<f32>(newR, newG, newB, activity));
    
    // Compute morphogen concentration gradients
    let id_r = clamp(id + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1));
    let id_l = clamp(id - vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1));
    let id_u = clamp(id + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1));
    let id_d = clamp(id - vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1));

    let gradR = vec2<f32>(
        textureLoad(dataTextureC, id_r, 0).r - textureLoad(dataTextureC, id_l, 0).r,
        textureLoad(dataTextureC, id_u, 0).r - textureLoad(dataTextureC, id_d, 0).r
    );
    let gradG = vec2<f32>(
        textureLoad(dataTextureC, id_r, 0).g - textureLoad(dataTextureC, id_l, 0).g,
        textureLoad(dataTextureC, id_u, 0).g - textureLoad(dataTextureC, id_d, 0).g
    );
    let gradB = vec2<f32>(
        textureLoad(dataTextureC, id_r, 0).b - textureLoad(dataTextureC, id_l, 0).b,
        textureLoad(dataTextureC, id_u, 0).b - textureLoad(dataTextureC, id_d, 0).b
    );

    // IDEA 2: Interfacial Marangoni surface tension shear
    // High chemical gradient disparity creates surface tension shear advecting optical sampling
    let marangoniForce = vec2<f32>(-gradR.y + gradB.y, gradR.x - gradB.x) * (0.02 + bass * 0.015);
    
    // Displace each channel differently based on the others' gradients + Marangoni shear
    let rUV = clamp(uv + (gradG + marangoniForce) * chromaticSep, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + ((gradR + gradB) * 0.5) * chromaticSep, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + (gradG - marangoniForce) * chromaticSep * 0.9, vec2<f32>(0.0), vec2<f32>(1.0));
    
    let bgR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let bgG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let bgB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let bgColor = vec3<f32>(bgR, bgG, bgB);
    
    // Combine RD pattern with chromatic background
    let patternIntensity = (newR + newG + newB) / 3.0;
    let rdColor = vec3<f32>(newR * 0.8 + newG * 0.2, newG * 0.7 + newB * 0.3, newB * 0.9 + newR * 0.1);
    var color = mix(bgColor, rdColor, patternIntensity * 0.7);
    
    // IDEA 3: Chemiluminescent boundary fluorescence
    // Sharp chemical boundaries fluoresce with wavelength-dependent emission proportional to reaction rate
    let edge = length(gradR) + length(gradG) + length(gradB);
    let chemiluminescence = vec3<f32>(edge * 0.7, edge * 0.4 + activity * 0.3, edge * 0.9 + treble * 0.3) * chromaticSep * 12.0;
    color += chemiluminescence;

    // IDEA 6: gel relief sheen — concentration height lit from the cursor,
    // so ridges between morphogen domains catch a specular glint.
    let hGrad = (gradR + gradG + gradB) * (1.0 / 3.0);
    let relN = normalize(vec3<f32>(-hGrad * 6.0, 1.0));
    let lightV = normalize(vec3<f32>((mouse - uv) * vec2<f32>(aspect, 1.0), 0.6));
    let halfV = normalize(lightV + vec3<f32>(0.0, 0.0, 1.0));
    let sheen = pow(max(dot(relN, halfV), 0.0), 40.0);
    color += vec3<f32>(0.9, 0.95, 1.0) * sheen * patternIntensity * 0.35;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.65, 0.98, patternIntensity);
    let finalRGB = acesFilm(max(color, vec3<f32>(0.0)));
    
    textureStore(writeTexture, id, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - patternIntensity * 0.2), 0.0, 0.0, 0.0));
}
