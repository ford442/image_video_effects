// ═══════════════════════════════════════════════════════════════════
//  Eroded Perlin Terrain
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, mouse-driven,
//            erosion-inspired, hydraulic-flow, stratified-color
//  Upgraded: 2026-05-23
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
    let h = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(dot(h, vec2<f32>(1.0, 1.3))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < 6; i = i + 1) {
        if (i >= octaves) {
            break;
        }
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

fn ridgedFbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.65;
    var frequency = 1.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        let n = valueNoise(p * frequency) * 2.0 - 1.0;
        value = value + (1.0 - abs(n)) * amplitude;
        amplitude = amplitude * 0.55;
        frequency = frequency * 2.1;
    }
    return value;
}

fn terrainHeight(uv: vec2<f32>, time: f32, mouse: vec2<f32>, terrainScale: f32) -> f32 {
    let scale = mix(1.8, 8.0, terrainScale);
    let mouseOffset = (mouse - 0.5) * vec2<f32>(1.8, -1.4);
    var p = uv * scale + mouseOffset * 0.7;

    let warp = vec2<f32>(
        fbm(p * 0.55 + vec2<f32>(time * 0.05, -time * 0.04), 4),
        fbm(p * 0.55 + vec2<f32>(4.8 - time * 0.03, 1.2 + time * 0.05), 4)
    );
    p = p + (warp - 0.5) * 1.5;

    let continental = fbm(p * 0.6 + vec2<f32>(-time * 0.02, time * 0.01), 5);
    let ridges = ridgedFbm(p * 1.35 + 3.1);
    let valleys = fbm(p * 2.3 - 11.7, 4);

    var h = continental * 0.58 + ridges * 0.42;
    h = h - valleys * 0.12;
    return clamp(h, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let px = 1.0 / resolution;
    let time = u.config.x * 0.1;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let erosionStrength = u.zoom_params.x;
    let waterLevel = mix(0.18, 0.62, u.zoom_params.y);
    let terrainScale = u.zoom_params.z;
    let sedimentContrast = u.zoom_params.w;
    let mouse = u.zoom_config.yz;

    let baseHeight = terrainHeight(uv, time, mouse, terrainScale);
    let hL = terrainHeight(uv + vec2<f32>(-px.x, 0.0), time, mouse, terrainScale);
    let hR = terrainHeight(uv + vec2<f32>( px.x, 0.0), time, mouse, terrainScale);
    let hD = terrainHeight(uv + vec2<f32>(0.0, -px.y), time, mouse, terrainScale);
    let hU = terrainHeight(uv + vec2<f32>(0.0,  px.y), time, mouse, terrainScale);

    let gradient = vec2<f32>(hR - hL, hU - hD);
    let slope = length(gradient);
    let waterMask = 1.0 - smoothstep(waterLevel, waterLevel + 0.09, baseHeight);
    let basinMask = 1.0 - smoothstep(0.03, 0.16, slope);
    let flowNoise = fbm((uv + gradient * 4.0) * mix(6.0, 24.0, terrainScale) + vec2<f32>(time * 0.05, -time * 0.02), 4);

    let erosion = erosionStrength * slope * (0.45 + waterMask * 0.9) * (0.6 + flowNoise * 0.7);
    let deposition = erosionStrength * basinMask * smoothstep(waterLevel + 0.03, waterLevel + 0.28, baseHeight);
    let height = clamp(baseHeight - erosion * 0.15 + deposition * 0.09 + waterMask * 0.025, 0.0, 1.0);

    let normal = normalize(vec3<f32>(-gradient.x * 12.0, 1.0, -gradient.y * 12.0));
    let lightDir = normalize(vec3<f32>(0.55, 0.78, -0.42));
    let diffuse = clamp(dot(normal, lightDir), 0.0, 1.0);
    let ambient = 0.32;
    let rim = pow(1.0 - clamp(normal.y, 0.0, 1.0), 2.0);
    let specular = pow(max(dot(normal, normalize(lightDir + vec3<f32>(0.0, 1.0, 0.0))), 0.0), 18.0);
    let strata = 0.5 + 0.5 * sin((height - erosion * 0.5 + deposition) * mix(34.0, 90.0, sedimentContrast) + flowNoise * 6.0);

    let deepWater = vec3<f32>(0.03, 0.10, 0.24);
    let shallowWater = vec3<f32>(0.10, 0.32, 0.55);
    var landColor = vec3<f32>(0.18, 0.16, 0.12);
    landColor = mix(landColor, vec3<f32>(0.55, 0.46, 0.30), smoothstep(waterLevel - 0.02, waterLevel + 0.08, height));
    landColor = mix(landColor, vec3<f32>(0.18, 0.38, 0.20), smoothstep(waterLevel + 0.04, waterLevel + 0.22, height));
    landColor = mix(landColor, vec3<f32>(0.42, 0.36, 0.30), smoothstep(0.55, 0.78, height));
    landColor = mix(landColor, vec3<f32>(0.92, 0.94, 0.98), smoothstep(0.78, 0.98, height));
    landColor = landColor + vec3<f32>(0.10, 0.07, 0.04) * (strata - 0.5) * (0.35 + sedimentContrast * 0.95);
    landColor = landColor + vec3<f32>(0.08, 0.10, 0.06) * deposition * (0.6 + mids * 0.6);

    let waterColor = mix(deepWater, shallowWater, clamp(waterMask * 1.1 + bass * 0.15, 0.0, 1.0));
    let glint = specular * (0.15 + waterMask * 0.65 + treble * 0.2);

    var generatedColor = mix(landColor, waterColor, waterMask);
    generatedColor = generatedColor * (ambient + diffuse * 0.95);
    generatedColor = generatedColor + vec3<f32>(glint);
    generatedColor = generatedColor + vec3<f32>(0.08, 0.10, 0.12) * rim * (0.3 + waterMask * 0.8);

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let generatedAlpha = 0.86 + 0.14 * height;
    let finalColor = mix(inputColor.rgb, generatedColor, generatedAlpha);
    let finalAlpha = max(inputColor.a, generatedAlpha);
    let finalDepth = mix(inputDepth, height, 0.92);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(height, slope, waterMask, deposition));
}
