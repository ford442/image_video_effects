// ═══════════════════════════════════════════════════════════════════
//  Chrono-Voronoi Mycelium
//  Category: generative
//  Description: Multi-temporal Voronoi fungal growth system with layered
//  temporal states, organic branching networks that evolve across time.
//  Audio controls growth vs decay rates. Mouse introduces nutrients/barriers.
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
  config: vec4<f32>,       // x=Time, y=Audio, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic
  zoom_params: vec4<f32>,  // x=GrowthRate, y=Generations, z=Decay, w=Glow
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// FBM noise for organic texture
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < octaves; i++) {
        v += amp * (sin(pos.x + sin(pos.y)) * 0.5 + 0.5);
        pos = pos * 2.1 + vec2<f32>(1.7, 0.3);
        amp *= 0.5;
    }
    return v;
}

// Voronoi with temporal generation layers
fn voronoiLayer(uv: vec2<f32>, scale: f32, timeLayer: f32, growthRate: f32) -> vec4<f32> {
    let s = uv * scale;
    let n = floor(s);
    let f = fract(s);

    var minDist1 = 9.0;
    var minDist2 = 9.0;
    var minCell = vec2<f32>(0.0);
    var minSeed = vec2<f32>(0.0);

    for (var j: i32 = -2; j <= 2; j++) {
        for (var i: i32 = -2; i <= 2; i++) {
            let cell = n + vec2<f32>(f32(i), f32(j));
            let seed = hash22(cell);
            // Temporal animation: seeds drift over generations
            let phase = seed * TAU;
            let drift = vec2<f32>(
                sin(phase.x + timeLayer * growthRate * 0.3) * 0.4,
                cos(phase.y + timeLayer * growthRate * 0.25) * 0.4
            );
            let o = vec2<f32>(f32(i), f32(j)) + seed + drift - f;
            let d = dot(o, o);
            if (d < minDist1) {
                minDist2 = minDist1;
                minDist1 = d;
                minCell = cell;
                minSeed = seed;
            } else if (d < minDist2) {
                minDist2 = d;
            }
        }
    }
    let border = minDist2 - minDist1;
    return vec4<f32>(sqrt(minDist1), sqrt(minDist2), border, hash21(minCell));
}

// Mycelium branch SDF approximation using distance transform
fn myceliumBranch(uv: vec2<f32>, t: f32, generation: f32, bass: f32) -> f32 {
    let scale = 4.0 + generation * 2.0;
    let v = voronoiLayer(uv, scale, t, 1.0 + bass * 0.5);

    // Branch-like pattern from Voronoi borders
    let border = v.z;
    let cell_id = v.w;

    // Growth mask: cells "activate" based on time layer and cell identity
    let birthTime = cell_id * 3.0;
    let alive = smoothstep(birthTime, birthTime + 0.5, t * 0.2);
    let aged = 1.0 - smoothstep(birthTime + 1.5, birthTime + 2.5, t * 0.2);
    let lifeState = alive * aged;

    let branchWidth = 0.08 + bass * 0.03;
    let branchIntensity = smoothstep(branchWidth, 0.0, border) * lifeState;
    return branchIntensity;
}

// Glowing tip effect at Voronoi seed points
fn glowingTips(uv: vec2<f32>, t: f32, generation: f32, treble: f32) -> f32 {
    let scale = 4.0 + generation * 2.0;
    let v = voronoiLayer(uv, scale, t, 1.0);
    let tipRadius = 0.05 + treble * 0.02;
    return smoothstep(tipRadius, 0.0, v.x) * (0.5 + 0.5 * sin(t * 2.0 + v.w * TAU));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let growthRate  = u.zoom_params.x * 2.0 + 0.5;  // 0.5..2.5
    let generations = u.zoom_params.y * 3.0 + 1.0;   // 1..4
    let decay       = u.zoom_params.z * 0.8 + 0.1;   // 0.1..0.9
    let glowAmt     = u.zoom_params.w * 2.0 + 0.5;   // 0.5..2.5

    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * vec2<f32>(aspect, 1.0);

    // Nutrient gradient around mouse — affects growth locally
    let mouseDist = length(uvAspect - mousePos);
    let nutrient = exp(-mouseDist * mouseDist * 8.0);

    // Accumulate multiple temporal generations
    var totalMycelium = 0.0;
    var totalGlow = 0.0;
    var generationColor = vec3<f32>(0.0);

    let numGen = i32(clamp(generations, 1.0, 4.0));
    for (var g = 0; g < numGen; g++) {
        let gf = f32(g);
        // Each generation has a different temporal offset and scale
        let timeOffset = gf * 1.7 + bass * 0.3;
        let layerTime = t * growthRate + timeOffset;

        let branches = myceliumBranch(uvAspect, layerTime, gf, bass);
        let tips = glowingTips(uvAspect, layerTime, gf, treble);

        // Nutrient boosts this generation's intensity
        let genStrength = pow(decay, gf) * (1.0 + nutrient * 0.5);
        totalMycelium += branches * genStrength;
        totalGlow += tips * genStrength * glowAmt;

        // Each generation has a unique color (age gradient: young=cyan, old=amber)
        let ageHue = gf / max(f32(numGen) - 1.0, 1.0);
        let genHue = mix(0.5, 0.08, ageHue); // cyan -> amber
        let genCol = vec3<f32>(
            0.5 + 0.5 * cos(genHue * TAU),
            0.5 + 0.5 * cos(genHue * TAU + 2.094),
            0.5 + 0.5 * cos(genHue * TAU + 4.189)
        );
        generationColor += genCol * (branches + tips * 0.5) * genStrength;
    }

    // Background: deep organic dark
    var color = vec3<f32>(0.02, 0.04, 0.06);

    // Mycelium network glow
    let networkIntensity = clamp(totalMycelium, 0.0, 1.0);
    let tipIntensity = clamp(totalGlow, 0.0, 1.0);

    // Normalize generation color
    let colorMag = length(generationColor) + 0.001;
    let normColor = generationColor / colorMag;

    // Translucent network layer
    color = mix(color, normColor * (0.4 + mids * 0.3), networkIntensity * 0.7);

    // Bright glowing tips
    let tipColor = vec3<f32>(0.8 + treble * 0.2, 0.95, 0.6 + mids * 0.3);
    color += tipColor * tipIntensity * 1.5;

    // Spore-like particles: scattered bright dots driven by treble
    let sporeNoise = hash31(vec3<f32>(uvAspect * 30.0, floor(t * 2.0)));
    if (sporeNoise > 0.97 + (1.0 - treble) * 0.02) {
        color += vec3<f32>(1.0, 0.9, 0.5) * treble * 0.8;
    }

    // Vignette
    let vignette = 1.0 - dot(uv - 0.5, uv - 0.5) * 1.5;
    color *= max(vignette, 0.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
