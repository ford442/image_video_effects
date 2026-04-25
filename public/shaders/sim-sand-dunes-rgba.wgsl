// ═══════════════════════════════════════════════════════════════════
//  Sim: Sand Dunes RGBA
//  Category: simulation
//  Features: simulation, rgba-state-machine, temporal, mouse-driven
//  Complexity: High
//  Chunks From: sim-sand-dunes.wgsl, alpha-fluid-simulation-paint.wgsl
//  Created: 2026-04-18
//  By: Agent CB-2 - RGBA Simulation Upgrader
// ═══════════════════════════════════════════════════════════════════
//  Four-grain-type physics with distinct falling, sliding, and wind
//  behaviors. Each grain type competes for space.
//  RGBA Channels:
//    R = Fine sand (light, easily wind-blown, falls slow)
//    G = Coarse sand (heavy, stable, high angle of repose)
//    B = Moist sand (clumpy, intermediate, sticks together)
//    A = Dust/salt (very light, rises on wind, settles slowly)
//  Why f32: Grain fractions require sub-unit precision for stable
//  accumulation and smooth slope transitions.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Parameters
    let gravity = mix(0.5, 2.0, u.zoom_params.x);
    let wind = mix(-0.2, 0.2, u.zoom_params.y);
    let moisture = mix(0.0, 1.0, u.zoom_params.z);
    let dustiness = mix(0.0, 1.0, u.zoom_params.w);

    // Read current cell (4 grain types)
    let state = textureLoad(dataTextureC, gid.xy, 0);
    var fine = state.r;
    var coarse = state.g;
    var moist = state.b;
    var dust = state.a;

    // Total material at this cell
    let totalHere = fine + coarse + moist + dust;

    // Read neighbors
    let below = textureLoad(dataTextureC, gid.xy - vec2<u32>(0u, 1u), 0);
    let belowLeft = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 1u), 0);
    let belowRight = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 1u), 0);
    let left = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 0u), 0);
    let right = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 0u), 0);
    let above = textureLoad(dataTextureC, gid.xy + vec2<u32>(0u, 1u), 0);

    var newFine = fine;
    var newCoarse = coarse;
    var newMoist = moist;
    var newDust = dust;

    // === FALLING PHYSICS (gravity) ===
    // Fine sand: falls if below has < 0.3 capacity
    if (fine > 0.01 && (below.r + below.g + below.b + below.a) < 0.3) {
        newFine *= 0.7;
    }
    // Coarse sand: falls if below has < 0.5 capacity (needs support)
    if (coarse > 0.01 && (below.r + below.g + below.b + below.a) < 0.5) {
        newCoarse *= 0.8;
    }
    // Moist sand: falls if below has < 0.4 capacity, but clumps
    if (moist > 0.01 && (below.r + below.g + below.b + below.a) < 0.4) {
        let clumpChance = 0.5 + moisture * 0.3;
        newMoist *= mix(1.0, 0.75, clumpChance);
    }
    // Dust: rises on updrafts, falls very slowly
    if (dust > 0.01) {
        let riseChance = smoothstep(0.0, 0.1, wind) * 0.3;
        newDust *= 1.0 - riseChance;
    }

    // === SLIDING PHYSICS (angle of repose) ===
    let totalBelowLeft = belowLeft.r + belowLeft.g + belowLeft.b + belowLeft.a;
    let totalBelowRight = belowRight.r + belowRight.g + belowRight.b + belowRight.a;
    let totalLeft = left.r + left.g + left.b + left.a;
    let totalRight = right.r + right.g + right.b + right.a;

    // Fine sand slides easily
    if (newFine > 0.05 && totalBelowLeft < totalBelowRight - 0.2) {
        newFine *= 0.85;
    } else if (newFine > 0.05 && totalBelowRight < totalBelowLeft - 0.2) {
        newFine *= 0.85;
    }

    // Coarse sand has high angle of repose
    if (newCoarse > 0.05 && totalBelowLeft < totalBelowRight - 0.4) {
        newCoarse *= 0.9;
    } else if (newCoarse > 0.05 && totalBelowRight < totalBelowLeft - 0.4) {
        newCoarse *= 0.9;
    }

    // Moist sand slides least
    if (newMoist > 0.05 && totalBelowLeft < totalBelowRight - 0.6) {
        newMoist *= 0.95;
    } else if (newMoist > 0.05 && totalBelowRight < totalBelowLeft - 0.6) {
        newMoist *= 0.95;
    }

    // === WIND EROSION ===
    let windStrength = abs(wind) * 5.0;
    let h = hash12(uv + time * 0.1);

    // Fine sand blown by wind
    if (h < windStrength && newFine > 0.01) {
        if (wind > 0.0 && totalRight < 0.2) { newFine *= 0.85; }
        else if (wind < 0.0 && totalLeft < 0.2) { newFine *= 0.85; }
    }

    // Dust very easily blown
    if (h < windStrength * 2.0 && newDust > 0.01) {
        if (wind > 0.0 && totalRight < 0.3) { newDust *= 0.7; }
        else if (wind < 0.0 && totalLeft < 0.3) { newDust *= 0.7; }
    }

    // Moist sand resists wind
    let moistResistance = moisture * 0.5;
    if (h < windStrength * (1.0 - moistResistance) && newMoist > 0.01) {
        if (wind > 0.0 && totalRight < 0.15) { newMoist *= 0.95; }
        else if (wind < 0.0 && totalLeft < 0.15) { newMoist *= 0.95; }
    }

    // === RECEIVING FROM ABOVE ===
    let totalAbove = above.r + above.g + above.b + above.a;
    if (totalAbove > 0.3) {
        // Some material falls in from above
        newFine += above.r * 0.15 * gravity;
        newCoarse += above.g * 0.1 * gravity;
        newMoist += above.b * 0.12 * gravity;
        newDust += above.a * 0.08;
    }

    // Dust settles from above even without much material
    if (above.a > 0.01) {
        newDust += above.a * 0.1 * (1.0 - dustiness * 0.5);
    }

    // === MOUSE INJECTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    if (mouseDist < 0.03) {
        let drop = 1.0 - mouseDist / 0.03;
        let type = hash12(vec2<f32>(time * 0.5, 0.0));
        if (type < 0.25) { newFine += drop; }
        else if (type < 0.5) { newCoarse += drop; }
        else if (type < 0.75) { newMoist += drop; }
        else { newDust += drop * 0.5; }
    }

    // === INITIALIZATION ===
    if (time < 1.0 && uv.y < 0.15) {
        let h = hash12(uv * 20.0);
        if (h > 0.3) {
            if (h < 0.5) { newFine = 0.8; }
            else if (h < 0.7) { newCoarse = 0.7; }
            else if (h < 0.85) { newMoist = 0.6; }
            else { newDust = 0.4; }
        }
    }

    // Clamp
    newFine = clamp(newFine, 0.0, 1.0);
    newCoarse = clamp(newCoarse, 0.0, 1.0);
    newMoist = clamp(newMoist, 0.0, 1.0);
    newDust = clamp(newDust, 0.0, 1.0);

    // === STORE STATE ===
    textureStore(dataTextureA, gid.xy, vec4<f32>(newFine, newCoarse, newMoist, newDust));

    // === STATE -> VISUAL COLOR MAPPING ===
    let fineColor = vec3<f32>(0.94, 0.85, 0.60);   // Light gold
    let coarseColor = vec3<f32>(0.82, 0.68, 0.45);  // Darker tan
    let moistColor = vec3<f32>(0.65, 0.55, 0.40);   // Dark wet sand
    let dustColor = vec3<f32>(0.92, 0.88, 0.78);    // Pale dust

    let totalNew = newFine + newCoarse + newMoist + newDust;
    var sandColor = vec3<f32>(0.0);
    if (totalNew > 0.01) {
        sandColor = (fineColor * newFine + coarseColor * newCoarse + moistColor * newMoist + dustColor * newDust) / totalNew;
    }

    // Shading based on height differences
    let totalAboveVal = above.r + above.g + above.b + above.a;
    let totalBelowVal = below.r + below.g + below.b + below.a;
    let heightDiff = totalAboveVal - totalBelowVal;
    sandColor *= (0.85 + heightDiff * 0.15);

    // Blend with background
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(bgColor * 0.4, sandColor, smoothstep(0.0, 0.1, totalNew));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.8, 1.0, smoothstep(0.0, 0.2, totalNew));

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - totalNew * 0.15), 0.0, 0.0, 0.0));
}
