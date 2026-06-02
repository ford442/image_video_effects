// ═══════════════════════════════════════════════════════════════════
//  Velvet Scatter Bloom
//  Category: image
//  Features: velvet, subsurface-scatter, bloom, audio-breathing, mouse-light, semantic-alpha, atmospheric
//  Complexity: Medium-High
//  Chunks From: _hash_library.wgsl (hash21, valueNoise), crystalline-fracture (edge feel)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — rich velvet scattering with living audio glow and moving light)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Scatter, y=Bloom, z=Subsurface, w=LightAngle
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash21 + valueNoise (from _hash_library.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var freq = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        v += a * valueNoise(p * freq);
        freq *= 2.0;
        a *= 0.5;
    }
    return v;
}

// Soft subsurface scatter approximation (cheap multiple scattering)
fn velvetScatter(col: vec3<f32>, uv: vec2<f32>, radius: f32, depth: f32) -> vec3<f32> {
    let texel = 1.0 / u.config.zw;
    var scatter = vec3<f32>(0.0);
    let samples = 5;
    for (var i = -samples; i <= samples; i = i + 2) {
        for (var j = -samples; j <= samples; j = j + 2) {
            let off = vec2<f32>(f32(i), f32(j)) * texel * radius * (0.6 + depth * 0.8);
            let s = textureSampleLevel(readTexture, u_sampler, uv + off, 0.0).rgb;
            let w = exp(-length(vec2<f32>(f32(i), f32(j))) * 0.25);
            scatter += s * w;
        }
    }
    return scatter / f32((samples * 2 / 2 + 1) * (samples * 2 / 2 + 1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    // Audio climate
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters (sliders)
    let scatterAmt = u.zoom_params.x * (1.0 + bass * 0.6);      // 0..2
    let bloomAmt = u.zoom_params.y * (0.8 + treble * 0.7);      // 0..1.5
    let subsurface = u.zoom_params.z;                           // 0..1
    let lightAngle = u.zoom_params.w * 6.28318;                 // 0..2π

    // Mouse as living key light
    let mouse = u.zoom_config.yz;
    let mouseDir = normalize(mouse - uv + vec2<f32>(0.0001));
    let mouseDist = length(mouse - uv);
    let mouseLight = smoothstep(0.55, 0.08, mouseDist) * (0.6 + bass * 0.5);

    // Input
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let edge = length(vec2<f32>(
        luma - dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0015, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114)),
        luma - dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 0.0015), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114))
    ));

    // Velvet scatter — stronger in darker, less detailed regions (classic velvet look)
    let darkMask = smoothstep(0.65, 0.15, luma);
    let scatterRadius = scatterAmt * (0.8 + darkMask * 1.4) * (1.0 + mids * 0.3);
    let scattered = velvetScatter(input.rgb, uv, scatterRadius, depth);

    // Subsurface color shift (warmth in shadows, cool on edges)
    let subColor = mix(vec3<f32>(0.85, 0.6, 0.45), vec3<f32>(0.4, 0.65, 0.95), 0.5 + 0.5 * sin(lightAngle + uv.y * 3.0));
    var velvet = mix(input.rgb, scattered, darkMask * subsurface * 0.85);

    // Add living subsurface glow
    let subGlow = fbm(uv * 7.0 + time * 0.04, 3) * darkMask * subsurface * 0.6;
    velvet = mix(velvet, subColor, subGlow * 0.7);

    // Edge bloom (audio reactive)
    let bloomMask = pow(smoothstep(0.03, 0.22, edge), 1.8) * bloomAmt;
    let bloomColor = mix(vec3<f32>(0.95, 0.9, 0.82), vec3<f32>(0.6, 0.75, 1.0), mids * 0.6);
    let bloom = bloomColor * bloomMask * (1.0 + treble * 0.8);

    // Mouse light interaction — "touching" the velvet reveals hidden color
    let lightTint = subColor * mouseLight * 0.9;
    velvet = velvet + lightTint * (0.6 + bass * 0.4);

    // Final composite
    var col = velvet + bloom;

    // Atmospheric haze on far depth
    let haze = (1.0 - depth) * 0.08 * (0.5 + bass * 0.3);
    col = mix(col, vec3<f32>(0.08, 0.06, 0.11), haze);

    // Film-like gentle contrast curve
    col = pow(col, vec3<f32>(0.92));

    // Semantic alpha — higher on glowing bloom and mouse-lit areas (beautiful for stacking)
    let glowEnergy = bloomMask + subGlow * 0.6 + mouseLight * 0.5;
    let semantic_alpha = clamp(0.72 + glowEnergy * 0.38, 0.55, 1.0);

    // Subtle grain that breathes with treble
    let grain = (hash21(uv * 920.0 + time * 19.0) - 0.5) * 0.018 * (0.3 + treble * 0.6);
    col += grain;

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Depth encodes glow energy for downstream effects
    let glowDepth = clamp(0.15 + glowEnergy * 0.55 + (1.0 - depth) * 0.1, 0.0, 0.98);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(glowDepth, 0.0, 0.0, 0.0));

    // Write light state for potential future temporal velvet (dataTextureA)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(scattered.r, subGlow, mouseLight, semantic_alpha));
}
