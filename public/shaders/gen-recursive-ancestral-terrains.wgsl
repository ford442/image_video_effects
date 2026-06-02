// ═══════════════════════════════════════════════════════════════════
//  Recursive Ancestral Terrains
//  Category: generative
//  Description: Fractal landscape generator where terrain features carry
//  genetic parameters from parent generations. Mouse position locally
//  selects which ancestral lineage is expressed. Audio controls mutation.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// "Genetic" FBM: each octave inherits slightly mutated parameters from parent
fn ancestralFbm(p: vec2<f32>, generations: i32, mutationRate: f32,
                lineageSelector: f32, t: f32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pos = p;
    var freq = 1.0;
    var parentAngle = 0.0;

    for (var g = 0; g < generations; g++) {
        let gf = f32(g);
        // Genetic parameters mutate per generation using lineageSelector
        let genSeed = hash22(vec2<f32>(gf, lineageSelector * 10.0 + 1.0));
        let mutation = (genSeed - 0.5) * mutationRate;

        // Each generation selects a slightly different "ancestral" direction
        let inheritedAngle = parentAngle + mutation.x * PI * 0.5;
        parentAngle = inheritedAngle;

        // Rotation of sampling space based on genetic lineage
        let c = cos(inheritedAngle);
        let s = sin(inheritedAngle);
        let rotPos = vec2<f32>(c * pos.x - s * pos.y, s * pos.x + c * pos.y);

        // Frequency and amplitude also mutate
        let mutFreq = freq * (1.8 + mutation.y * 0.4);
        let sample = smoothNoise(rotPos * mutFreq + vec2<f32>(gf * 1.3, t * 0.05));

        // Geological warping: higher generations fold the terrain
        value += amplitude * sample;
        pos += vec2<f32>(cos(sample * TAU), sin(sample * TAU)) * 0.1 * mutationRate;

        amplitude *= 0.5;
        freq = mutFreq;
    }
    return value;
}

// Simple atmospheric fog based on height and distance
fn atmosphericFog(height: f32, depth: f32, mids: f32) -> f32 {
    return exp(-depth * 2.0) * (0.3 + mids * 0.2) * (1.0 - height);
}

// Terrain color palette: alien geological strata
fn terrainColor(height: f32, normal: f32, bass: f32, t: f32) -> vec3<f32> {
    // Deep stone: dark purple-grey
    let rock = vec3<f32>(0.15 + bass * 0.05, 0.10, 0.20);
    // Mid terrain: rust-orange alien minerals
    let mineral = vec3<f32>(0.45 + bass * 0.1, 0.25, 0.10);
    // High peaks: crystalline pale blue
    let crystal = vec3<f32>(0.6, 0.75, 0.9);
    // Snow caps tinted by treble
    let snow = vec3<f32>(0.85, 0.90, 0.95);

    var col = rock;
    col = mix(col, mineral, smoothstep(0.2, 0.5, height));
    col = mix(col, crystal, smoothstep(0.5, 0.75, height));
    col = mix(col, snow,    smoothstep(0.75, 0.9, height));

    // Lighting from normal
    col *= 0.5 + 0.5 * normal;
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mutationRate  = u.zoom_params.x * 1.5 + 0.2;  // 0.2..1.7
    let generBlend    = u.zoom_params.y;               // generational blending 0..1
    let heightScale   = u.zoom_params.z * 1.5 + 0.3;  // 0.3..1.8
    let erosionAmt    = u.zoom_params.w * 0.6 + 0.1;  // 0.1..0.7

    // Mouse selects which ancestral lineage to express locally
    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDist = length(uvA - mousePos);
    // Lineage selector: smooth spatial blend influenced by mouse proximity
    let lineageBase = hash12(uvA * 3.0 + 0.5);
    let lineageFromMouse = hash12(mousePos * 3.0 + 0.5);
    let mouseBlend = exp(-mouseDist * mouseDist * 5.0);
    let lineageSelector = mix(lineageBase, lineageFromMouse, mouseBlend);

    // Audio controls mutation: bass=tectonic activity, treble=fine erosion
    let audioMutation = mutationRate + bass * 0.4 + treble * 0.15;
    let numGen = i32(3.0 + mids * 3.0 + generBlend * 2.0);
    let clampedGen = clamp(numGen, 3, 8);

    // Terrain height from ancestral fractal
    let height = ancestralFbm(uvA * 2.0, clampedGen, audioMutation, lineageSelector, t);
    let scaledHeight = height * heightScale;

    // Approximate surface normal via finite differences
    let eps = 0.003;
    let hx = ancestralFbm((uvA + vec2<f32>(eps, 0.0)) * 2.0, clampedGen, audioMutation, lineageSelector, t);
    let hy = ancestralFbm((uvA + vec2<f32>(0.0, eps)) * 2.0, clampedGen, audioMutation, lineageSelector, t);
    let nx = (hx - height) / eps;
    let ny = (hy - height) / eps;
    let nz = 1.0;
    let normalLen = length(vec3<f32>(nx, ny, nz));
    let normalizedNormal = vec3<f32>(nx, ny, nz) / normalLen;

    // Directional light: sun angle drifting slowly with bass
    let lightDir = normalize(vec3<f32>(cos(t * 0.1 + bass * 0.3), 0.5, sin(t * 0.1 + bass * 0.3)));
    let diffuse = clamp(dot(normalizedNormal, lightDir), 0.0, 1.0);

    // Erosion: carves channels, driven by audio
    let erosionNoise = smoothNoise(uvA * 8.0 + vec2<f32>(t * 0.03, 0.0));
    let eroded = scaledHeight * (1.0 - erosionNoise * erosionAmt);

    // Depth (viewer distance from top)
    let terrainDepth = 1.0 - clamp(eroded, 0.0, 1.0);

    var color = terrainColor(clamp(eroded, 0.0, 1.0), diffuse, bass, t);

    // Atmospheric fog in valleys
    let fog = atmosphericFog(clamp(eroded, 0.0, 1.0), terrainDepth, mids);
    let fogColor = vec3<f32>(0.3 + mids * 0.2, 0.35 + bass * 0.1, 0.5 + treble * 0.2);
    color = mix(color, fogColor, fog * 0.6);

    // Ancestral glow at lineage boundaries
    let lineageGrad = abs(fract(lineageSelector * 5.0) - 0.5) * 2.0;
    let lineageGlow = smoothstep(0.85, 1.0, lineageGrad) * treble * 0.4;
    color += vec3<f32>(0.5, 0.3, 0.8) * lineageGlow;

    // Horizon sky blend
    let skyT = smoothstep(0.55, 0.75, uv.y);
    let skyColor = vec3<f32>(0.05 + bass * 0.05, 0.08, 0.15 + mids * 0.1);
    color = mix(color, skyColor, skyT);

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(1.0 - eroded));
}
