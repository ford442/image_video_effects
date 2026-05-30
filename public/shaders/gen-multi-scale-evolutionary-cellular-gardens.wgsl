// ═══════════════════════════════════════════════════════════════════
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Description: Multi-state cellular automata with evolving rules.
//  Audio drives genetic pressure; mouse seeds invasive species or
//  protected zones. Organic plant-like structures emerge and slowly
//  change their fundamental behavior over time.
//  Complexity: High
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ─── Hash utilities ───────────────────────────────────────────────
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    let p4 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ─── Smooth noise for organic patterns ────────────────────────────
fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

// ─── Rule kernel: evolved growth behaviour ────────────────────────
// Returns growth impulse for a species given its neighbourhood average
// and the current "genetic" ruleset encoded in rulePhase
fn growthKernel(selfDensity: f32, neighborAvg: f32, rulePhase: f32,
                resource: f32, fertility: f32) -> f32 {
    // Evolving activation threshold (shifts with rulePhase)
    let activateThreshold = 0.15 + rulePhase * 0.3;
    let inhibitThreshold = 0.7 - rulePhase * 0.15;

    // Growth if neighbours in sweet-spot, decay if isolated or overcrowded
    let activation = smoothstep(activateThreshold - 0.05, activateThreshold + 0.05, neighborAvg);
    let inhibition = smoothstep(inhibitThreshold, inhibitThreshold + 0.15, neighborAvg);

    let growthImpulse = activation * (1.0 - inhibition) * resource * fertility;
    let decayRate = 0.02 + (1.0 - resource) * 0.03;

    return growthImpulse - selfDensity * decayRate;
}

// ─── Multi-scale neighbourhood sampling ───────────────────────────
fn sampleNeighbourhood(uv: vec2<f32>, ps: vec2<f32>, scale: f32) -> vec4<f32> {
    let offset = ps * scale;
    let n0 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( offset.x, 0.0), 0.0);
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>( offset.x, 0.0), 0.0);
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0,  offset.y), 0.0);
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0,  offset.y), 0.0);
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( offset.x,  offset.y), 0.0);
    let n5 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>( offset.x,  offset.y), 0.0);
    let n6 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( offset.x, -offset.y), 0.0);
    let n7 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>( offset.x, -offset.y), 0.0);
    return (n0 + n1 + n2 + n3 + n4 + n5 + n6 + n7) * 0.125;
}

// ─── Species coloring ─────────────────────────────────────────────
fn speciesColor(s1: f32, s2: f32, s3: f32, resource: f32,
                rulePhase: f32, t: f32) -> vec3<f32> {
    // Species 1: green-teal coral growth
    let c1 = vec3<f32>(0.1, 0.7, 0.5) * s1;
    // Species 2: magenta-violet fungal network
    let c2 = vec3<f32>(0.7, 0.2, 0.6) * s2;
    // Species 3: golden-amber crystalline lichen
    let c3 = vec3<f32>(0.8, 0.6, 0.1) * s3;
    // Resource substrate glow
    let rCol = vec3<f32>(0.15, 0.25, 0.15) * resource * 0.5;

    // Iridescent shift based on rule evolution
    let shift = sin(rulePhase * TAU + t * 0.3) * 0.15;
    let iridescence = vec3<f32>(shift, -shift * 0.5, shift * 0.7);

    return c1 + c2 + c3 + rCol + iridescence * (s1 + s2 + s3) * 0.3;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);
    let ps = 1.0 / res;

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // User parameters
    let mutationRate = u.zoom_params.x * 2.0 + 0.2;   // 0.2..2.2
    let competition  = u.zoom_params.y * 0.8 + 0.1;   // 0.1..0.9
    let fertility    = u.zoom_params.z * 1.5 + 0.3;   // 0.3..1.8
    let diversity    = u.zoom_params.w;                // 0..1

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist) * mouseDown;

    // Read previous state from temporal feedback
    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let s1 = state.r;       // Species 1 density
    let s2 = state.g;       // Species 2 density
    let s3 = state.b;       // Species 3 density
    let resource = state.a; // Local resource level

    // Evolving rule phase — slowly drifts with time and audio mutation pressure
    // This makes the CA rules themselves change over the life of the system
    let rulePhase = fract(t * 0.01 * mutationRate + bass * 0.15 + mids * 0.08);
    let rulePhase2 = fract(rulePhase + 0.33 + treble * 0.1);
    let rulePhase3 = fract(rulePhase + 0.67 + mids * 0.12);

    // Multi-scale neighbourhood averages (near + far = multi-scale competition)
    let nearNeighbours = sampleNeighbourhood(uv, ps, 1.0);
    let farNeighbours  = sampleNeighbourhood(uv, ps, 3.0);

    // Weighted neighbourhood for each species (multi-scale awareness)
    let nearWeight = 0.7;
    let farWeight = 0.3;
    let avgS1 = nearNeighbours.r * nearWeight + farNeighbours.r * farWeight;
    let avgS2 = nearNeighbours.g * nearWeight + farNeighbours.g * farWeight;
    let avgS3 = nearNeighbours.b * nearWeight + farNeighbours.b * farWeight;
    let avgRes = nearNeighbours.a * nearWeight + farNeighbours.a * farWeight;

    // Apply evolving growth kernels per species
    let grow1 = growthKernel(s1, avgS1, rulePhase, resource, fertility);
    let grow2 = growthKernel(s2, avgS2, rulePhase2, resource, fertility * 0.9);
    let grow3 = growthKernel(s3, avgS3, rulePhase3, resource, fertility * 0.85) * diversity;

    // Inter-species competition
    let comp12 = s1 * s2 * competition;
    let comp13 = s1 * s3 * competition * 0.8;
    let comp23 = s2 * s3 * competition * 0.9;

    // Audio-driven genetic pressure modifies growth rates
    let audioPressure1 = bass * 0.06;
    let audioPressure2 = mids * 0.05;
    let audioPressure3 = treble * 0.04;

    // Update species densities
    var newS1 = s1 + grow1 - comp12 - comp13 + audioPressure1;
    var newS2 = s2 + grow2 - comp12 - comp23 + audioPressure2;
    var newS3 = s3 + grow3 - comp13 - comp23 + audioPressure3;

    // Resource dynamics: slowly regenerates, consumed by all species
    let totalConsumption = (newS1 + newS2 + newS3) * 0.012;
    let regeneration = 0.015 * fertility + avgRes * 0.01;
    var newRes = resource + regeneration - totalConsumption;

    // Mouse interaction: seeds invasive burst or creates protected zone
    if (mouseInfluence > 0.01) {
        // Seed a burst of the currently dominant species in that region
        if (newS1 >= newS2 && newS1 >= newS3) {
            newS1 += mouseInfluence * 0.4;
        } else if (newS2 >= newS3) {
            newS2 += mouseInfluence * 0.4;
        } else {
            newS3 += mouseInfluence * 0.4;
        }
        newRes += mouseInfluence * 0.3; // Inject resources
    }

    // Random seeding for new growth when population is low
    let totalPop = newS1 + newS2 + newS3;
    if (totalPop < 0.05) {
        let seed = hash13(vec3<f32>(uv * 100.0, floor(t * 2.0)));
        if (seed > 0.97) {
            let which = hash12(uv * 57.3 + t);
            if (which < 0.33) { newS1 += 0.3; }
            else if (which < 0.66) { newS2 += 0.3; }
            else { newS3 += 0.3; }
            newRes += 0.2;
        }
    }

    // Clamp all values
    newS1 = clamp(newS1, 0.0, 1.5);
    newS2 = clamp(newS2, 0.0, 1.5);
    newS3 = clamp(newS3, 0.0, 1.5);
    newRes = clamp(newRes, 0.0, 1.2);

    // Store state for next frame temporal feedback
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newS1, newS2, newS3, newRes));

    // ─── Visualization ────────────────────────────────────────────
    var color = speciesColor(newS1, newS2, newS3, newRes, rulePhase, t);

    // Growth tip glow (where species are actively expanding)
    let growthActivity = max(grow1, max(grow2, grow3));
    let tipGlow = smoothstep(0.0, 0.04, growthActivity);
    color += vec3<f32>(0.9, 0.95, 0.8) * tipGlow * 0.5;

    // Competition boundary highlighting
    let boundaryGlow = comp12 + comp13 + comp23;
    color += vec3<f32>(1.0, 0.3, 0.2) * smoothstep(0.0, 0.02, boundaryGlow) * 0.3;

    // Resource substrate visibility
    let resGlow = smoothstep(0.5, 1.0, newRes);
    color += vec3<f32>(0.2, 0.4, 0.1) * resGlow * 0.2;

    // Vignette for focus
    let vig = 1.0 - smoothstep(0.35, 0.8, length(uv - 0.5) * 1.3);
    color *= vig;

    // Overall intensity modulation
    let alpha = clamp(totalPop * 0.6 + newRes * 0.3 + 0.05, 0.0, 1.0);
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, global_id.xy, vec4<f32>(color * alpha, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(totalPop * 0.4, 0.0, 0.0, 0.0));
}
