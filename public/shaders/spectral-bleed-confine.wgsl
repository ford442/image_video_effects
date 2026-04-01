// ═══════════════════════════════════════════════════════════════════════════════
//  Spectral Bleed & Confinement
//  Category: EFFECT | Complexity: VERY_HIGH
//  Specific color bands "leak" outward from edges while being electromagnetically
//  "confined" by other channels. Creates glowing halos that feel physically
//  constrained—like plasma in a magnetic bottle.
//  Mathematical approach: Sobel edge detection per channel, anisotropic
//  diffusion with channel-dependent diffusion tensors, electromagnetic
//  confinement via cross-channel gradient repulsion, Fresnel-like boundary
//  reflection for confined colors.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=BleedRate, y=MouseX, z=MouseY, w=ConfinementStr
    zoom_params: vec4<f32>,  // x=DiffusionRadius, y=FieldIntensity, z=ChannelBias, w=PulseSpeed
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Sobel edge detection for a single channel
// ─────────────────────────────────────────────────────────────────────────────
fn sobelChannel(uv: vec2<f32>, texel: vec2<f32>, channel: i32) -> vec2<f32> {
    var vals: array<f32, 9>;
    var idx = 0;
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let s = textureSampleLevel(readTexture, u_sampler,
                clamp(uv + vec2<f32>(f32(dx), f32(dy)) * texel, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
            if (channel == 0) { vals[idx] = s.r; }
            else if (channel == 1) { vals[idx] = s.g; }
            else { vals[idx] = s.b; }
            idx++;
        }
    }
    // Sobel kernels
    let gx = -vals[0] + vals[2] - 2.0 * vals[3] + 2.0 * vals[5] - vals[6] + vals[8];
    let gy = -vals[0] - 2.0 * vals[1] - vals[2] + vals[6] + 2.0 * vals[7] + vals[8];
    return vec2<f32>(gx, gy);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Anisotropic diffusion kernel for color bleeding
//  Diffuses a channel outward from edges, modulated by confinement field
// ─────────────────────────────────────────────────────────────────────────────
fn diffuseChannel(uv: vec2<f32>, texel: vec2<f32>, channel: i32, radius: f32, confinement: f32) -> f32 {
    var sum = 0.0;
    var weight = 0.0;
    let steps = 4;
    let step = texel * radius;

    // Read the confinement field (other channels' edges block diffusion)
    let confCh1 = select(1, 0, channel == 1);
    let confCh2 = select(2, 1, channel == 2);
    let confEdge1 = length(sobelChannel(uv, texel, confCh1));
    let confEdge2 = length(sobelChannel(uv, texel, confCh2));
    let confField = (confEdge1 + confEdge2) * confinement;

    for (var dy = -steps; dy <= steps; dy++) {
        for (var dx = -steps; dx <= steps; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * step;
            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let dist2 = dot(offset, offset);

            // Gaussian envelope
            let gWeight = exp(-dist2 / (radius * radius * 0.3));

            // Confinement: suppress diffusion where other channels have edges
            let localConf = (confEdge1 + confEdge2) * confinement;
            let confFactor = exp(-localConf * 5.0);

            let s = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
            var val = 0.0;
            if (channel == 0) { val = s.r; }
            else if (channel == 1) { val = s.g; }
            else { val = s.b; }

            let w = gWeight * confFactor;
            sum += val * w;
            weight += w;
        }
    }

    return sum / max(weight, 0.001);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fresnel-like boundary glow at confinement edges
// ─────────────────────────────────────────────────────────────────────────────
fn fresnelGlow(edgeStr: f32, confinement: f32, phase: f32) -> f32 {
    let boundary = smoothstep(0.05, 0.2, edgeStr) * smoothstep(0.05, 0.15, confinement);
    return boundary * (0.5 + 0.5 * sin(phase)) * 0.3;
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB for glow coloring
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = fragCoord / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let diffRadius = u.zoom_params.x * 4.0 + 1.0;          // 1 – 5
    let fieldIntensity = u.zoom_params.y * 2.0 + 0.3;      // 0.3 – 2.3
    let channelBias = u.zoom_params.z;                       // 0 – 1 (which channel bleeds most)
    let pulseSpeed = u.zoom_params.w * 4.0 + 0.5;          // 0.5 – 4.5
    let bleedRate = u.zoom_config.x * 0.6 + 0.1;           // 0.1 – 0.7
    let confinementStr = u.zoom_config.w * 3.0 + 0.5;      // 0.5 – 3.5

    // ─────────────────────────────────────────────────────────────────────────
    //  Read source and depth
    // ─────────────────────────────────────────────────────────────────────────
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ─────────────────────────────────────────────────────────────────────────
    //  Per-channel edge detection
    // ─────────────────────────────────────────────────────────────────────────
    let edgeR = length(sobelChannel(uv, texel, 0));
    let edgeG = length(sobelChannel(uv, texel, 1));
    let edgeB = length(sobelChannel(uv, texel, 2));

    // ─────────────────────────────────────────────────────────────────────────
    //  Channel-biased bleed radius: selected channel bleeds more
    // ─────────────────────────────────────────────────────────────────────────
    let biasR = mix(1.0, 1.8, smoothstep(0.0, 0.33, channelBias));
    let biasG = mix(1.0, 1.8, smoothstep(0.33, 0.66, channelBias) - smoothstep(0.66, 1.0, channelBias));
    let biasB = mix(1.0, 1.8, smoothstep(0.66, 1.0, channelBias));

    // Pulsing bleed radius
    let pulse = 0.8 + 0.2 * sin(time * pulseSpeed);
    let radiusR = diffRadius * biasR * pulse * (0.5 + depth * 0.5);
    let radiusG = diffRadius * biasG * pulse * (0.5 + depth * 0.5);
    let radiusB = diffRadius * biasB * pulse * (0.5 + depth * 0.5);

    // ─────────────────────────────────────────────────────────────────────────
    //  Diffuse each channel with confinement from the other two
    // ─────────────────────────────────────────────────────────────────────────
    let bledR = diffuseChannel(uv, texel, 0, radiusR, confinementStr);
    let bledG = diffuseChannel(uv, texel, 1, radiusG, confinementStr);
    let bledB = diffuseChannel(uv, texel, 2, radiusB, confinementStr);

    let bledColor = vec3<f32>(bledR, bledG, bledB);

    // ─────────────────────────────────────────────────────────────────────────
    //  Mix original with bled version based on edge strength
    //  Strong edges bleed, flat areas stay crisp
    // ─────────────────────────────────────────────────────────────────────────
    let edgeMask = vec3<f32>(
        smoothstep(0.02, 0.15, edgeR),
        smoothstep(0.02, 0.15, edgeG),
        smoothstep(0.02, 0.15, edgeB)
    );
    var result = mix(srcColor, bledColor, edgeMask * bleedRate);

    // ─────────────────────────────────────────────────────────────────────────
    //  Confinement boundary glow: where bleed meets resistance
    // ─────────────────────────────────────────────────────────────────────────
    let glowR = fresnelGlow(edgeR, edgeG + edgeB, time * pulseSpeed + 0.0);
    let glowG = fresnelGlow(edgeG, edgeR + edgeB, time * pulseSpeed + 2.09);
    let glowB = fresnelGlow(edgeB, edgeR + edgeG, time * pulseSpeed + 4.18);
    result += vec3<f32>(glowR * 1.0, glowG * 0.8, glowB * 1.2) * fieldIntensity;

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: localized bleed burst
    // ─────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let dist = distance(uv, r.xy);
        let age = time - r.z;
        if (age > 0.0 && age < 3.0) {
            let ring = exp(-abs(dist - age * 0.15) * 30.0) * exp(-age * 0.8);
            let burstHue = fract(dist * 3.0 + age * 0.5);
            result += hsv2rgb(burstHue, 0.8, 1.0) * ring * 0.2 * fieldIntensity;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Feedback: bleed persists over time
    // ─────────────────────────────────────────────────────────────────────────
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(result, history, 0.3);

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
