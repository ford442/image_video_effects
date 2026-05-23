// ═══════════════════════════════════════════════════════════════════════════════
//  SmoothLife Predator-Prey — Two-Species Audio-Reactive Cellular Automaton
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural, animated
//  Complexity: Very High
//  Scientific: Rafler 2011 SmoothLife for two interacting species:
//              - Species A (prey, green): standard SmoothLife birth/survival,
//                locally suppressed by species B density (predation pressure)
//              - Species B (predator, red): grows proportional to A density
//                (Lotka-Volterra α·A·B term), decays to zero without prey
//              - Predator-prey Lotka-Volterra oscillations at population scale
//              - Audio bass drives prey birth-rate, treble drives predator decay,
//                mids modulate coupling strength
//  Upgraded: Phase B
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,  // x=TimeStep, y=Sharpness, z=ColorSpeed, w=InitDensity
    ripples:     array<vec4<f32>, 50>,
}

fn smooth_interval(x: f32, a: f32, b: f32, sharp: f32) -> f32 {
    return smoothstep(a - sharp, a + sharp, x) * (1.0 - smoothstep(b - sharp, b + sharp, x));
}

// Annular neighbourhood convolution for species channel (2-pass)
fn sampleNeighbourhood(px: vec2<i32>, res: vec2<f32>, channel: i32) -> vec4<f32> {
    let inner_radius = 3.0;
    let outer_radius = 9.0;
    var inner_sum = 0.0; var inner_w = 0.0;
    var outer_sum = 0.0; var outer_w = 0.0;
    for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
            let npx = (px + vec2<i32>(dx, dy) + vec2<i32>(i32(res.x), i32(res.y))) & vec2<i32>(2047, 2047);
            let s = textureLoad(dataTextureC, npx, 0);
            let val = select(s.r, s.g, channel == 1);
            let dist = sqrt(f32(dx*dx + dy*dy));
            if (dist < inner_radius) {
                let w = 1.0 - smoothstep(0.0, inner_radius, dist);
                inner_sum += val * w; inner_w += w;
            }
            if (dist < outer_radius && dist >= inner_radius * 0.5) {
                let mid = (inner_radius + outer_radius) * 0.5;
                let w = max(0.0, (1.0 - abs(dist - mid) / (outer_radius - inner_radius)));
                let ww = w * w;
                outer_sum += val * ww; outer_w += ww;
            }
        }
    }
    let n = select(inner_sum / inner_w, 0.0, inner_w < 0.001);
    let m = select(outer_sum / outer_w, 0.0, outer_w < 0.001);
    return vec4<f32>(n, m, 0.0, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let px     = vec2<i32>(global_id.xy);
    let mouse  = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);
    let mDown  = u.zoom_config.w > 0.0;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let dt        = clamp(u.zoom_params.x, 0.01, 0.5);
    let sharpness = max(0.01, u.zoom_params.y * 2.0);
    let colSpeed  = u.zoom_params.z;
    let initDens  = u.zoom_params.w;

    // ─── Read current state ───
    let stateData = textureLoad(dataTextureC, px, 0);
    let stateA    = stateData.r;   // prey
    let stateB    = stateData.g;   // predator
    let age       = stateData.b;
    let activity  = stateData.a;

    // ─── Neighbourhoods for both species ───
    let nbA = sampleNeighbourhood(px, resolution, 0);
    let nbB = sampleNeighbourhood(px, resolution, 1);
    let nA  = nbA.x; let mA = nbA.y;   // inner/outer averages for A
    let nB  = nbB.x;                    // inner average for B (predator density)

    // ─── SmoothLife update for Species A (prey) ───
    // Standard SmoothLife with audio bass modulating birth range
    let bassBoost = bass * 0.04;
    let b1 = 0.257 - bassBoost; let b2 = 0.336 + bassBoost;
    let d1 = 0.365;              let d2 = 0.549;
    let sharp = sharpness * 0.05;
    let birthA    = smooth_interval(nA, b1, b2, sharp);
    let surviveA  = smooth_interval(nA, d1, d2, sharp);
    var transA    = birthA * (1.0 - stateA) + surviveA * stateA;
    transA       += mA * 0.05 * (0.5 - stateA);
    // Predation pressure: predator suppresses prey locally
    let coupling  = mix(0.0, 0.6, mids);
    transA       -= nB * stateA * coupling;

    // ─── SmoothLife update for Species B (predator) ───
    // Predator grows proportional to prey density (Lotka-Volterra)
    let predGrowth   = nA * stateB * coupling;             // α·A·B growth
    let trebleDecay  = 0.05 * (1.0 + treble * 0.5);       // intrinsic decay
    var transB       = predGrowth - stateB * trebleDecay;
    // Also needs prey neighbourhood to establish
    let birthB = smooth_interval(nA, 0.3, 0.7, sharp * 2.0) * (1.0 - stateB) * coupling * 0.5;
    transB += birthB;

    // ─── Discrete time update ───
    var newA = clamp(stateA + dt * (transA - stateA), 0.0, 1.0);
    var newB = clamp(stateB + dt * transB, 0.0, 1.0);

    // ─── Mouse interaction ───
    let mdist = distance(uv, mouse);
    if (mDown && mdist < 0.03) {
        let blob = 1.0 - smoothstep(0.0, 0.03, mdist);
        newA = max(newA, blob);
    }

    // ─── Random seeding ───
    let noise = fract(sin(dot(uv + time * 0.001, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let thresh = 1.0 - max(0.001, initDens * 0.01);
    if (noise > thresh) {
        let seedPos = vec2<f32>(fract(noise * 1.618), fract(noise * 2.718));
        let sdist = distance(uv, seedPos);
        if (sdist < 0.05) { newA = max(newA, 1.0 - smoothstep(0.0, 0.05, sdist)); }
    }

    // ─── Age & activity ───
    var newAge  = fract(age + 0.02 * (newA - 0.1));
    let newAct  = mix(activity, abs(newA - stateA) + abs(newB - stateB), 0.1);

    // ─── Colouring ───
    // Prey: green spectrum; Predator: red-orange spectrum; mixed: yellow-white
    let cycle     = newAge * 6.28318 + time * colSpeed;
    let preyCol   = vec3<f32>(0.1 + 0.15 * sin(cycle), 0.6 + 0.3 * sin(cycle + 1.0), 0.15);
    let predCol   = vec3<f32>(0.9 + 0.1 * sin(cycle * 2.0), 0.1 + 0.2 * sin(cycle * 2.0 + 1.0), 0.05);
    let deadCol   = vec3<f32>(0.04, 0.06, 0.12);
    let actColor  = vec3<f32>(1.0, 0.9, 0.3) * smoothstep(0.01, 0.1, newAct) * 0.5;

    var color = deadCol;
    color = mix(color, preyCol, smoothstep(0.0, 0.3, newA));
    // Predator overlay tints alive regions red
    color = mix(color, predCol, smoothstep(0.0, 0.3, newB) * newA);
    // Combined peak → yellow-white
    let coExist = newA * newB;
    color = mix(color, vec3<f32>(1.0, 1.0, 0.7), smoothstep(0.4, 0.9, coExist));
    color += actColor;
    // Vignette
    let cdist = length(uv - 0.5) * 1.4;
    color *= 1.0 - cdist * cdist * 0.3;

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalColor = mix(inputColor.rgb, color, 0.9);

    textureStore(writeTexture, vec2<u32>(px), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newA, newB, newAge, newAct));
    textureStore(writeDepthTexture, vec2<u32>(px), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
