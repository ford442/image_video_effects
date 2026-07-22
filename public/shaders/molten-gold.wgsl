// molten-gold.wgsl
// Molten gold liquid metal effect — optimized for Generative Showcase
// Showcase features: strong idle animation, satisfying mouse claim, audio-reactive
// Wolfram Data:
//   Gold melting point: 1064.18°C = 1337.33 K
//   Gold thermal conductivity: 320 W/(m·K)
//   At 1337K, blackbody peak wavelength = 2.16683 μm (infrared)
// Upgrade (2026-07-22, Visualist): true Planckian blackbody ramp,
//   fresnel specular on flow ridges, bass-driven heat waves, glow clamp @1.2

// 13-binding universal layout (matches all 694+ shaders in this repo)
@group(0) @binding(0) var nearestSampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTexture: texture_2d<f32>;
@group(0) @binding(5) var nearestClampSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,       // x: time, y: unused, z: unused, w: unused
    zoom_config: vec4<f32>,  // x: mouseX, y: mouseY, z: mouseDown, w: unused
    zoom_params: vec4<f32>,  // x: flowSpeed/turbulence, y: glow, z: specular, w: highlightFreq
    ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        value += amplitude * noise(p * freq);
        freq *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = x * (x * 0.15 + 0.05) + 0.004;
    let b = x * (x * 0.15 + 0.50) + 0.06;
    return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

// True blackbody (Planckian locus) color ramp.
// Tanner-Helland approximation of blackbody chromaticity, valid ~800K–6500K.
// deep red (~900K) -> gold-orange (1337.33K melt point) -> white-hot (>4000K).
// Keeps the cited 1337K gold physics honest: at the melt point the metal
// really does glow orange-gold, not arbitrary palette colors.
fn blackbodyColor(kelvin: f32) -> vec3<f32> {
    let t = clamp(kelvin, 800.0, 6500.0) / 100.0;
    // Red channel: saturates at 1.0 below 6600K (always true in our range)
    let r = 1.0;
    // Green channel
    var g = 0.0;
    if (t <= 66.0) {
        g = clamp(0.3900815788 * log(t) - 0.6318414438, 0.0, 1.0);
    } else {
        g = clamp(1.1298908609 * pow(t - 60.0, -0.0755148492), 0.0, 1.0);
    }
    // Blue channel: zero below ~1900K, rises to full by 6600K
    var b = 0.0;
    if (t >= 66.0) {
        b = 1.0;
    } else if (t > 19.0) {
        b = clamp(0.5432067891 * log(t - 10.0) - 1.1962430891, 0.0, 1.0);
    }
    return vec3<f32>(r, g, b);
}

// Kelvin temperature field of the melt: 1337.33K baseline at the gold melt
// point, modulated by flow + glow + bass heat + mouse input energy.
// Emissive intensity falls off with the 4th power (Stefan-Boltzmann flavor).
fn meltTemperature(molten: f32, heatWave: f32, bass: f32, mousePull: f32) -> f32 {
    let base = 1337.33 * (0.55 + molten * 0.75);
    let bassHeat = bass * 420.0 * heatWave;
    let stirHeat = mousePull * 350.0;
    return clamp(base + bassHeat + stirHeat, 800.0, 5200.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let coord = vec2<i32>(id.xy);
    // bounds guard — mandatory for out-of-range workgroup threads
    if (coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) { return; }
    let uv = vec2<f32>(id.xy) / dims;
    let aspect = dims.x / dims.y;

    let t = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Zoom params (saved-preset contract: ids/defaults unchanged)
    let flowSpeed = mix(0.15, 0.6, u.zoom_params.x);
    let turbulence = mix(1.2, 3.5, u.zoom_params.x * 0.7);
    let glowIntensity = u.zoom_params.y;
    let specularStrength = u.zoom_params.z;
    let highlightFreq = u.zoom_params.w;

    // Audio data from plasmaBuffer
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse claim interaction
    let mouseInfluence = mouseDown * 2.5;
    let mousePos = (mouse * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let mouseDist = length((uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0) - mousePos);
    let mousePull = smoothstep(0.8, 0.1, mouseDist) * mouseInfluence;

    // Domain coordinates with flow
    var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    var q = p * 1.8;
    q.x += fbm(q * 0.8 + t * flowSpeed * 0.4, 4) * 0.6;
    q.y += fbm(q * 0.7 - t * flowSpeed * 0.35, 4) * 0.55;

    // Bass heat waves: slow rippling thermal bands pulsing through the melt.
    // Band phase drifts slowly with time; bass pumps their amplitude and
    // spatial frequency so the whole surface breathes with the low end.
    let bandPhase = dot(p, vec2<f32>(0.9, 0.45)) * (2.0 + bass * 2.5) - t * 0.55;
    let heatWave = 0.5 + 0.5 * sin(bandPhase + fbm(q * 0.6 + t * 0.1, 3) * 2.2);
    let heatGain = 0.35 + bass * 0.65;

    // Molten gold layers — heat waves feed back into the domain warp so the
    // bands visibly deform the flow, not just tint it.
    let molten = fbm(q * turbulence + heatWave * heatGain * 0.25
                     + vec2<f32>(t * 0.2, t * -0.15), 5);
    let detail = fbm(q * 4.2 + t * 0.8 + heatWave * 0.35, 3);

    // ── True blackbody temperature ramp ──────────────────────────────────
    // Map the flow field to a Kelvin temperature, then through the Planckian
    // locus: cool pockets glow deep red, ridges at melt point glow gold,
    // bass/mouse-heated crests run white-hot.
    let kelvin = meltTemperature(molten, heatWave, bass, mousePull);
    let blackbody = blackbodyColor(kelvin);
    // Stefan-Boltzmann-ish emissive falloff: relative to melt-point emission
    let emissive = pow(kelvin / 1337.33, 3.0);
    var color = blackbody * emissive * 0.55;

    // Detail sparkle keeps the fine fBM grain alive inside the ramp
    color += blackbody * detail * 0.35;

    // ── Fresnel specular on flow ridges ──────────────────────────────────
    // Pseudo-normal from the height-field gradient (finite differences of the
    // molten height). View-dependent Schlick fresnel lights only the ridge
    // flanks that tilt away from the viewer — that is what reads as metal.
    let eps = 0.03;
    let hC = molten + detail * 0.35;
    let hX = fbm((q + vec2<f32>(eps, 0.0)) * turbulence
                 + vec2<f32>(t * 0.2, t * -0.15), 4);
    let hY = fbm((q + vec2<f32>(0.0, eps)) * turbulence
                 + vec2<f32>(t * 0.2, t * -0.15), 4);
    let grad = vec2<f32>(hX - hC, hY - hC) / eps;
    let ridgeStrength = mix(0.6, 2.2, specularStrength);
    let nrm = normalize(vec3<f32>(-grad * 0.55 * ridgeStrength, 1.0));
    let viewDir = normalize(vec3<f32>(p * 0.6, 1.4));
    let fresnel = pow(1.0 - clamp(dot(nrm, viewDir), 0.0, 1.0), 3.0);
    let ridgeMask = smoothstep(0.15, 0.9, length(grad));
    // Highlight frequency slider sharpens the ridge lobe (shininess)
    let shininess = mix(6.0, 48.0, highlightFreq);
    let lightDir = normalize(vec3<f32>(0.4, 0.6, 0.7));
    let specLobe = pow(clamp(dot(reflect(-lightDir, nrm), viewDir), 0.0, 1.0), shininess);
    let fresnelSpec = (fresnel * ridgeMask * 1.6 + specLobe * 0.9)
                      * mix(0.15, 1.5, specularStrength) * (1.0 + treble * 1.2);
    color += blackbodyColor(kelvin + 900.0) * fresnelSpec;

    // ── Glow layer with bass heat waves, clamped pre-tint at ~1.2 ────────
    // (luma-echo-warp lesson: clamp BEFORE multiplying by tint, or the tint
    // saturates into a flat slab after tonemapping.)
    var glowAccum = pow(molten * 0.7 + detail * 0.3, 1.8)
                    * (0.35 + heatWave * heatGain)
                    * (0.6 + bass * 0.8);
    glowAccum = min(glowAccum, 1.2);
    color += blackbody * glowAccum * mix(0.4, 1.15, glowIntensity);

    // Legacy ridge glint kept (soul of the original specular pass), now
    // riding on the blackbody ramp instead of a fixed gold palette.
    let spec = pow(smoothstep(0.65, 0.95, molten + detail * 0.4), 3.0);
    color += vec3<f32>(1.0, 0.95, 0.7) * spec * mix(0.4, 1.1, specularStrength)
             * (1.0 + treble * 1.5);

    // Ripple shimmer from mid + highlight frequency
    let ripple = sin((molten * 12.0 + t * 3.0) * (1.0 + mid * 2.0)
                     * (0.5 + highlightFreq * 1.5)) * 0.035;
    color += ripple * (0.4 + treble * 0.6);

    // Tone and vignette
    color = pow(color, vec3<f32>(0.95));
    let vignette = 1.0 - length(uv - 0.5) * 0.6;
    color *= vignette * 0.95 + 0.05;

    // Chromatic aberration
    let depth = textureSampleLevel(depthTexture, nearestSampler, uv, 0.0).r;
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color);

    // Semantic alpha
    let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

    // Temporal feedback
    let prev = textureSampleLevel(dataTextureC, nearestSampler, uv, 0.0);
    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, color, 0.25);

    // Output
    textureStore(writeTexture, id.xy, vec4<f32>(temporal, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(temporal, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
