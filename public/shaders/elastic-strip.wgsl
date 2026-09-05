// ═══════════════════════════════════════════════════════════════════
//  Elastic Strip — Batch 60
//  Category: distortion
//  Spring-physics strips with sharper bevel sub-ribs, traveling
//  pluck packets, stronger soap-film iridescence from stretch energy,
//  held drag punch, bounded click plucks. V/H via dir param.
//
//  A packing: display RGBA (tonemapped rgb, semantic alpha)
//  B unused. C = previous-frame trail (exact textureLoad).
//  No extraBuffer writes.
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

const TAU: f32 = 6.28318530718;

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn damped_oscillator(t: f32, freq: f32, decay: f32, phase: f32) -> f32 {
  return exp(-decay * t) * sin(t * freq + phase);
}

fn anisotropic_highlight(viewDir: vec2<f32>, lightDir: vec2<f32>, tangent: vec2<f32>, roughness: f32) -> f32 {
  let halfDir = normalize(viewDir + lightDir);
  let tdoth = max(dot(tangent, halfDir), 0.0);
  return pow(tdoth, 1.0 / max(roughness, 0.01));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let prev = textureLoad(dataTextureC, pixel, 0);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let tension = mix(0.4, 1.6, depth);

    let stripCount = mix(8.0, 80.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let strength = (u.zoom_params.y - 0.5) * 2.5;
    let falloff = u.zoom_params.z;
    let direction = u.zoom_params.w;

    let isHoriz = step(0.5, direction);
    let stripCoord = mix(uv.x, uv.y, isHoriz);
    let alongCoord = mix(uv.y, uv.x, isHoriz);
    let mouseStrip = mix(mouse.x, mouse.y, isHoriz);
    let mouseDisplace = mix(mouse.y, mouse.x, isHoriz);

    let cell = floor(stripCoord * stripCount);
    let stripCenter = (cell + 0.5) / stripCount;
    let cellPhase = cell * 1.618;
    let stripLocal = fract(stripCoord * stripCount);

    let dist = abs(stripCenter - mouseStrip);
    let influence = exp(-pow(dist / max(falloff * 0.5 + 0.01, 0.0001), 2.0));

    let pluckDecay = 2.0 + treble * 3.0;
    let pluckFreq = 6.0 + bass * 12.0;
    let springShift1 = damped_oscillator(time + cellPhase * 0.1, pluckFreq * tension, pluckDecay, cellPhase) * bass * 0.06;
    let springShift2 = damped_oscillator(time * 1.3 + cellPhase * 0.2, pluckFreq * 1.7 * tension, pluckDecay * 1.5, cellPhase + 1.0) * bass * 0.03;
    // Held drag punch — stronger stretch under press
    let dragShift = (mouseDisplace - 0.5) * strength * influence * tension * (1.0 + held * 0.85);
    var totalShift = dragShift + (springShift1 + springShift2) * influence;

    var clickPluck = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.3) {
            let rStrip = mix(rp.x, rp.y, isHoriz);
            let rAlong = mix(rp.y, rp.x, isHoriz);
            let band = exp(-abs(stripCenter - rStrip) * stripCount * 0.55);
            let wave = exp(-abs(alongCoord - rAlong - age * 0.55) * 28.0) * (1.0 - age / 1.3);
            // Secondary harmonic packet trailing the primary pluck
            let harmonic = exp(-abs(alongCoord - rAlong - age * 0.78) * 42.0) * max(1.0 - age / 1.0, 0.0);
            clickPluck = max(clickPluck, band * (wave + harmonic * 0.55));
        }
    }
    totalShift += clickPluck * 0.14 * strength * (1.0 + held * 0.25);

    let sourceUV = vec2<f32>(
        uv.x - select(0.0, totalShift, isHoriz > 0.5),
        uv.y - select(totalShift, 0.0, isHoriz > 0.5)
    );
    let clampedUV = clamp(sourceUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let baseColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);

    let chromaShift = abs(totalShift) * 0.028 * (1.0 + treble + held * 0.35);
    let rUV = clamp(sourceUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sourceUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var rgb = vec3<f32>(r, baseColor.g, b);

    // Sharper bevel + nested sub-ribs
    let stripEdge = abs(stripLocal - 0.5) * 2.0;
    let bevel = smoothstep(0.78, 1.0, stripEdge);
    let bevelHard = pow(bevel, 1.45);
    let subRib = smoothstep(0.055, 0.0, abs(fract(stripCoord * stripCount * 3.0) - 0.5));
    let microRib = smoothstep(0.04, 0.0, abs(fract(stripCoord * stripCount * 7.0) - 0.5));
    let ribMask = subRib * 0.7 + microRib * 0.45 + bevelHard;

    // Traveling pluck packets along strip length
    let packetSpeed = 2.8 + bass * 2.6 + held * 1.2;
    let packets = pow(max(0.0, sin(alongCoord * 38.0 - time * (packetSpeed * 2.4) + cellPhase * 0.2)), 10.0);
    let packets2 = pow(max(0.0, sin(alongCoord * 56.0 + time * (3.2 + mids * 2.0) + cellPhase * 0.35)), 14.0);
    let runners = smoothstep(0.06, 0.0, abs(fract(alongCoord * 5.0 + time * (1.9 + mids) + clickPluck) - 0.5));
    let edgeGlow = bevelHard * influence;

    let normal = vec2<f32>(select(1.0, 0.0, isHoriz > 0.5), select(0.0, 1.0, isHoriz > 0.5));
    let lightDir = normalize(vec2<f32>(0.3, 0.7));
    let viewDir = normalize(vec2<f32>(0.0, 0.0) - uv + 0.5);
    let ndotl = max(dot(normal, lightDir), 0.0);
    let specular = pow(ndotl, 36.0) * mids * 0.55;
    let aniso = anisotropic_highlight(viewDir, lightDir, normal, 0.12 + treble * 0.18) * mids * 0.45;

    // Stronger soap-film iridescence from stretch energy
    let stretchEnergy = abs(totalShift) * (4.5 + held * 1.8) + clickPluck * 0.8;
    let filmPhase = stretchEnergy * 9.0 + alongCoord * 7.0 + time * 1.9 + ribMask * 2.2;
    let film = 0.5 + 0.5 * cos(TAU * (vec3<f32>(filmPhase * 0.09) + vec3<f32>(0.0, 0.33, 0.67)));
    let soapHue = hsv2rgb(vec3<f32>(fract(0.55 + stretchEnergy * 0.35 + mids * 0.15), 0.75, 1.0));
    let soap = mix(film, soapHue, 0.45);

    rgb += soap * (0.22 + stretchEnergy * 0.38 + clickPluck * 0.55 + packets * 0.38 + packets2 * 0.22);
    rgb += soap * ribMask * 0.28 + soap * runners * 0.18;
    rgb += vec3<f32>(specular + aniso);
    rgb += bevelHard * soap * 0.32;
    rgb += packets * soap * influence * 0.35 * (1.0 + held * 0.4);

    let plasticSheen = pow(1.0 - abs(dot(viewDir, normal)), 3.0) * 0.18 * (1.0 + treble + held * 0.2);
    rgb += vec3<f32>(plasticSheen);

    let band = min(u32(alongCoord * 8.0), 7u);
    let bandShimmer = plasmaBuffer[band + 1u].x * 0.12;
    rgb += soap * bandShimmer * (0.4 + stretchEnergy);

    rgb = aces_tonemap(rgb * (1.0 + edgeGlow * 0.38 + held * 0.14 + packets * 0.08));
    rgb = mix(rgb, prev.rgb * 0.9, 0.16);

    let deformationEnergy = abs(totalShift) * 4.0;
    // Semantic (unpremultiplied) alpha
    let alpha = clamp(baseColor.a * 0.6 + deformationEnergy * depth + edgeGlow * 0.25 + clickPluck * 0.28 + packets * 0.1, 0.0, 1.0);
    let outDepth = clamp(depth + bevelHard * 0.08 + subRib * 0.04 + microRib * 0.02 + packets * 0.03, 0.0, 1.0);
    let outCol = vec4<f32>(rgb, alpha);

    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
