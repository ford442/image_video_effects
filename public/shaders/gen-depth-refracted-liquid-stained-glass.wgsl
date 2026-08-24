// ═══════════════════════════════════════════════════════════════════
//  Depth-Refracted Liquid Stained Glass
//  Category: generative
//  Features: facet-refraction, depth-aware, chromatic-aberration, upgraded-rgba,
//            temporal-rotation, audio-refraction, chromatic-edge-dispersion
//  Complexity: High
//  Upgraded: 2026-06-06
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

fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Returns leading mask, rosette inlay mask, and a stable cell material id.
fn ornamentSample(uv: vec2<f32>, facets: f32, drift: f32) -> vec3<f32> {
    let centered = uv - 0.5;
    let radius = length(centered);
    let angle = atan2(centered.y, centered.x) + drift;
    let wedge = abs(fract(angle * facets / (2.0 * PI)) - 0.5);
    let ringCoord = fract(radius * (4.0 + facets * 0.45));
    let ringDistance = abs(ringCoord - 0.5);
    let spokeDistance = wedge * max(radius, 0.08);
    let leading = max(
        1.0 - smoothstep(0.012, 0.045, ringDistance),
        1.0 - smoothstep(0.004, 0.025, spokeDistance));
    let rosetteWave = abs(sin(angle * facets) * cos(radius * PI * (3.0 + facets * 0.2)));
    let rosette = 1.0 - smoothstep(0.08, 0.32, rosetteWave);
    let cell = floor(vec2<f32>(
        angle * facets / (2.0 * PI),
        radius * (4.0 + facets * 0.45)));
    return vec3<f32>(leading, rosette, hash12(cell));
}

fn thinFilmTint(viewCosine: f32, thickness: f32) -> vec3<f32> {
    let phase = (1.0 - clamp(viewCosine, 0.0, 1.0)) * mix(5.0, 18.0, thickness);
    return 0.55 + 0.45 * cos(vec3<f32>(phase, phase + 2.094, phase + 4.188));
}

fn threePointLighting(n: vec3<f32>) -> f32 {
    let key = max(dot(n, normalize(vec3<f32>(0.55, 0.75, 0.8))), 0.0);
    let fill = max(dot(n, normalize(vec3<f32>(-0.7, 0.15, 0.65))), 0.0);
    let back = max(dot(n, normalize(vec3<f32>(0.1, -0.8, 0.55))), 0.0);
    return 0.3 + key * 0.7 + fill * 0.22 + back * 0.14;
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
    return textureSampleLevel(
        readDepthTexture,
        non_filtering_sampler,
        clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)),
        0.0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));

    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let aspect = f32(res.x) / f32(res.y);
    let uv = (vec2<f32>(coords) + 0.5) / vec2<f32>(res);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    let center = u.zoom_config.yz * 2.0 - 1.0;
    var centered_p = p - vec2<f32>(center.x * aspect, center.y);

    let facetParam = clamp(u.zoom_params.x, 0.0, 1.0);
    let bevelParam = clamp(u.zoom_params.y, 0.0, 1.0);
    let driftParam = clamp(u.zoom_params.z, 0.0, 1.0);
    let chromaParam = clamp(u.zoom_params.w, 0.0, 1.0);
    let heldGain = select(1.0, 1.65, u.zoom_config.w > 0.5);

    // Click fronts flex the virtual glass sheet. Each event is timestamp-bound
    // and capped to the uniform array's declared capacity.
    var clickWave = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = u.config.x - ripple.z;
        if (age < 0.0 || age > 2.6) { continue; }
        let rippleDistance = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
        clickWave += sin((rippleDistance - age * 0.2) * 72.0)
          * exp(-rippleDistance * 2.4 - age * 1.25);
    }
    clickWave = clamp(clickWave, -1.0, 1.0);
    centered_p += normalize(centered_p + vec2<f32>(0.0001)) * clickWave * 0.028;

    // Every saved control keeps its named role: 3..16 facets, bevel sampling
    // radius, temporal drift rate, and chromatic dispersion amount.
    let facetCount = floor(mix(3.0, 16.0, facetParam) + 0.5);
    let angleStep = PI * 2.0 / facetCount;

    let sourceAngle = atan2(centered_p.y, centered_p.x);
    let r = length(centered_p);

    let drift = u.config.x * mix(0.025, 0.42, driftParam);
    let sector = fract((sourceAngle + drift) / angleStep + 0.5);
    let foldedAngle = abs(sector - 0.5) * angleStep;
    var folded_p = vec2<f32>(cos(foldedAngle), sin(foldedAngle)) * r;

    folded_p.x /= aspect;
    var sample_uv = folded_p * 0.5 + 0.5;
    sample_uv = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let depth_val = sampleDepth(sample_uv);
    let texel = 1.0 / vec2<f32>(textureDimensions(readDepthTexture));
    let eps = texel * mix(0.75, 4.0, bevelParam);
    let dLeft = sampleDepth(sample_uv - vec2<f32>(eps.x, 0.0));
    let dRight = sampleDepth(sample_uv + vec2<f32>(eps.x, 0.0));
    let dDown = sampleDepth(sample_uv - vec2<f32>(0.0, eps.y));
    let dUp = sampleDepth(sample_uv + vec2<f32>(0.0, eps.y));
    let gradient = vec2<f32>(dLeft - dRight, dDown - dUp);
    let normal = normalize(vec3<f32>(gradient * mix(2.0, 8.0, bevelParam), 0.35));

    // Audio is sourced exclusively from the engine-owned aggregate sample.
    let audio = plasmaBuffer[0].xyz;
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    let depthPulse = 0.65 + 0.35 * sin(u.config.x * mix(0.35, 2.2, driftParam) + mids * PI);
    let refractionStrength = mix(0.008, 0.09, bevelParam) * depthPulse
      * (1.0 + bass * 0.35) * heldGain;
    let offset = normal.xy * refractionStrength * (1.0 - depth_val);

    // Facet seams become glass leading; dispersion grows only around those seams.
    let edgeDistance = abs(sector - 0.5) * angleStep * max(r, 0.08);
    let edgeWidth = mix(0.006, 0.065, bevelParam);
    let edgeFactor = 1.0 - smoothstep(0.0, edgeWidth, edgeDistance);
    let dispersion = mix(0.001, 0.035, chromaParam) * (0.25 + edgeFactor) * (1.0 + treble * 0.3);
    let dispersionAxis = normalize(normal.xy + vec2<f32>(0.001, 0.0));
    let r_offset = dispersionAxis * dispersion;
    let g_offset = vec2<f32>(0.0);
    let b_offset = -dispersionAxis * dispersion;

    var col = vec3<f32>(0.0);
    col.r = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + offset + r_offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    col.g = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + offset + g_offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    col.b = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + offset + b_offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let sourceAlpha = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).a;

    // Heightfield normal, three-point lighting, Fresnel glass, and a stable
    // tessellated palette turn source depth into visible material structure.
    let fresnel = pow(1.0 - max(normal.z, 0.0), 4.0);
    let tileCell = floor(sample_uv * facetCount);
    let materialHue = fract(hash12(tileCell) + floor((sourceAngle + drift) / angleStep) * 0.071 + mids * 0.08);
    let glassTint = hue2rgb(materialHue) * mix(0.35, 0.85, chromaParam);
    let lighting = threePointLighting(normal);
    let ornament = ornamentSample(sample_uv, facetCount, drift);
    let film = thinFilmTint(normal.z, chromaParam + treble * 0.15);
    col = col * lighting * mix(vec3<f32>(1.0), glassTint + 0.45, 0.24 + chromaParam * 0.24);
    col += glassTint * (fresnel * (0.35 + treble * 0.25) + edgeFactor * (0.22 + bass * 0.18));
    col += mix(glassTint, film, 0.55) * ornament.y * (0.05 + chromaParam * 0.14);
    col += film * abs(clickWave) * (0.12 + treble * 0.18);
    col *= 1.0 - ornament.x * 0.18;

    // Temporal color rotation via dataTextureC tint blend
    let prevTint = textureLoad(dataTextureC, coords, 0).rgb;
    col = mix(col, prevTint * 0.9, 0.04 + mids * 0.02);

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let materialCoverage = clamp(edgeFactor * 0.35 + fresnel * 0.3 + luma * 0.35 + abs(clickWave) * 0.12, 0.0, 1.0);
    let alpha = max(sourceAlpha, materialCoverage);

    let reliefDepth = clamp(depth_val + edgeFactor * 0.1 + length(gradient) * mix(0.5, 2.0, bevelParam), 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(col * 1.1), alpha);
    textureStore(writeDepthTexture, coords, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
}
