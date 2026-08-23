// ═══════════════════════════════════════════════════════════════════
//  Ferrofluid Spikes — Studio Lighting & Metallic Sheen Enhanced
//  Category: simulation
//  Features: mouse-driven, audio-reactive, generative-surface, metallic-highlights,
//            3-point-lighting, GGX-specular, Fresnel-Schlick, anisotropic-sheen, AO
//  Complexity: High
//  Created: 2026-05-31
//  Enhanced: 2026-06-28
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + amp * noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

// ═══ GGX Specular Distribution ═══
fn D_GGX(NdotH: f32, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let d = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

// ═══ Fresnel-Schlick Approximation ═══
fn F_Schlick(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ Geometry Function (Smith GGX) ═══
fn G_Smith(NdotV: f32, NdotL: f32, roughness: f32) -> f32 {
    let k = (roughness * roughness) / 2.0;
    let g1 = NdotV / (NdotV * (1.0 - k) + k);
    let g2 = NdotL / (NdotL * (1.0 - k) + k);
    return g1 * g2;
}

// ═══ 3-Point Studio Lighting ═══
// key: warm ~5600K, fill: cool ~3200K, rim: hot ~7000K
fn threePointLighting(
    normal: vec3<f32>,
    viewDir: vec3<f32>,
    lightPos: vec3<f32>,
    worldPos: vec3<f32>,
    roughness: f32,
    metallic: f32,
    baseColor: vec3<f32>,
    ao: f32
) -> vec3<f32> {
    // Key light (warm, upper-right)
    let keyDir = normalize(vec3<f32>(0.5, 0.8, 0.6));
    let keyColor = vec3<f32>(1.0, 0.92, 0.78); // ~5600K warm
    let keyIntensity = 1.2;

    // Fill light (cool, lower-left)
    let fillDir = normalize(vec3<f32>(-0.6, -0.3, 0.4));
    let fillColor = vec3<f32>(0.65, 0.75, 1.0); // ~3200K cool
    let fillIntensity = 0.5;

    // Rim light (hot, from behind)
    let rimDir = normalize(vec3<f32>(-0.3, 0.5, -0.8));
    let rimColor = vec3<f32>(0.85, 0.90, 1.0); // ~7000K hot
    let rimIntensity = 1.0;

    let F0 = mix(vec3<f32>(0.04), baseColor, metallic);
    var result = vec3<f32>(0.0);

    // Process each light
    let lights = array<vec3<f32>, 3>(keyDir, fillDir, rimDir);
    let lightColors = array<vec3<f32>, 3>(keyColor * keyIntensity, fillColor * fillIntensity, rimColor * rimIntensity);

    for (var i = 0; i < 3; i = i + 1) {
        let L = lights[i];
        let H = normalize(viewDir + L);
        let NdotL = max(dot(normal, L), 0.0);
        let NdotH = max(dot(normal, H), 0.0);
        let NdotV = max(dot(normal, viewDir), 0.0);
        let VdotH = max(dot(viewDir, H), 0.0);

        let D = D_GGX(NdotH, roughness);
        let F = F_Schlick(VdotH, F0);
        let G = G_Smith(NdotV, NdotL, roughness);

        let specular = (D * F * G) / (4.0 * NdotV * NdotL + 0.001);
        let diffuse = baseColor * (1.0 - metallic) / PI;

        // Light attenuation: 1/(1 + kd + qd^2)
        let dist = length(worldPos - lightPos);
        let attenuation = 1.0 / (1.0 + 0.5 * dist + 0.25 * dist * dist);

        result = result + (diffuse + specular) * lightColors[i] * NdotL * attenuation * ao;
    }

    return result;
}

// ═══ Ambient Occlusion (5-sample hemisphere) ═══
fn ambientOcclusion(uv: vec2<f32>, normal: vec2<f32>, radius: f32) -> f32 {
    var occlusion = 0.0;
    let samples = array<vec2<f32>, 5>(
        vec2<f32>(0.0, 1.0),
        vec2<f32>(0.95, 0.31),
        vec2<f32>(0.59, -0.81),
        vec2<f32>(-0.59, -0.81),
        vec2<f32>(-0.95, 0.31)
    );
    for (var i = 0; i < 5; i = i + 1) {
        let offset = samples[i] * radius;
        let sampleUV = uv + offset;
        let neighbor = noise(sampleUV * 10.0);
        let heightDiff = neighbor - noise(uv * 10.0);
        occlusion = occlusion + max(0.0, heightDiff);
    }
    return 1.0 - clamp(occlusion * 0.2, 0.0, 1.0);
}

// ═══ Anisotropic Metallic Sheen (for ferrofluid) ═══
fn anisotropicSheen(viewDir: vec3<f32>, normal: vec3<f32>, tangent: vec3<f32>, roughness: f32) -> f32 {
    let H = normalize(viewDir + vec3<f32>(0.0, 1.0, 0.5));
    let TdotH = dot(tangent, H);
    let NdotH = dot(normal, H);
    let aniso = exp(-2.0 * (TdotH * TdotH) / ((NdotH + 0.001) * roughness));
    return aniso;
}

// ═══ Rim Lighting Edge Glow ═══
fn rimLighting(viewDir: vec3<f32>, normal: vec3<f32>, strength: f32) -> f32 {
    let rim = 1.0 - max(dot(viewDir, normal), 0.0);
    return pow(rim, 3.0) * strength;
}

fn rosensweigHeight(p: vec2<f32>, magnet: vec2<f32>, density: f32, time: f32) -> f32 {
    let delta = p - magnet;
    let radius = length(delta);
    let frequency = mix(18.0, 58.0, density);
    let k0 = vec2<f32>(1.0, 0.0);
    let k1 = vec2<f32>(0.5, 0.8660254);
    let k2 = vec2<f32>(-0.5, 0.8660254);
    let lattice = (cos(dot(p, k0) * frequency + time * 0.24)
        + cos(dot(p, k1) * frequency - time * 0.19)
        + cos(dot(p, k2) * frequency + time * 0.13)) / 3.0;
    let peaks = pow(clamp(lattice * 0.5 + 0.5, 0.0, 1.0), 7.0);
    let radialRibs = pow(abs(cos(atan2(delta.y, delta.x) * (7.0 + density * 9.0)
        + radius * frequency * 0.35 - time * 0.8)), 12.0);
    return exp(-radius * radius * 4.2) * (peaks * 0.82 + radialRibs * 0.18);
}

// IQ cosine palette — iridescent metal ramp keyed to a scalar quantity.
fn ferroSpectrum(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.2831853 * (
        vec3<f32>(1.0, 1.0, 1.0) * t + vec3<f32>(0.00, 0.28, 0.62)));
}

// Push channel spread away from luma so the iridescence stays vivid instead of
// averaging toward the dark grey of the base metal.
fn vivify(c: vec3<f32>, amount: f32) -> vec3<f32> {
    let luma = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return max(vec3<f32>(0.0), mix(vec3<f32>(luma), c, 1.0 + amount));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rawMouse = u.zoom_config.yz;

    let magnetStrength = u.zoom_params.x * (1.0 + bass * 0.5);
    let spikeDensity = u.zoom_params.y;
    let fluidViscosity = u.zoom_params.z;
    let highlightSharpness = u.zoom_params.w;

    let hasSpring = arrayLength(&extraBuffer) >= 139u;
    var mousePos = rawMouse; var magnetVelocity = vec2<f32>(0.0);
    if (hasSpring && extraBuffer[138] > 0.5) {
        mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]); magnetVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    }
    if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
        var pos = mousePos; var vel = magnetVelocity; let seeded = extraBuffer[138] > 0.5;
        if (!seeded) { pos = rawMouse; vel = vec2<f32>(0.0); }
        let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
        vel += ((rawMouse - pos) * 205.0 - vel * mix(20.0, 34.0, fluidViscosity)) * dt; pos += vel * dt;
        extraBuffer[133] = pos.x; extraBuffer[134] = pos.y; extraBuffer[135] = vel.x; extraBuffer[136] = vel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
    }

    let aspect = resolution.x / resolution.y;
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let aspectMouse = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = length(aspectUV - aspectMouse);

    // Magnetic field falls off with distance
    let field = smoothstep(0.5, 0.0, dist) * magnetStrength;

    // ── Fast motion B: travelling field conveyor ─────────────────────────
    // The whole Rosensweig lattice is sampled through a moving frame, so the
    // spike field streams past the magnet rather than sitting still. Closed
    // form in time; the conveyor rate is clamped so it can never blur out.
    let conveyorRate = clamp(0.06 + spikeDensity * 0.10 + mids * 0.08, 0.0, 0.28);
    let conveyor = vec2<f32>(time * conveyorRate, time * conveyorRate * 0.43);

    // True Rosensweig-like hexagonal peak family plus fine carrier ripples.
    let liquid = fbm(uv * (8.0 + spikeDensity * 20.0) + time * 0.1, 4);
    var clickHeight = 0.0;
    var clickSlope = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let front = smoothstep(0.026, 0.0, abs(radius - age * 0.34)) * exp(-age * 1.15);
            clickHeight += front;
            clickSlope += delta / max(radius, 0.001) * front;
        }
    }
    let held = select(0.62, 1.0, u.zoom_config.w > 0.5);
    let convUV = aspectUV + conveyor;
    let spikeBase = rosensweigHeight(convUV, aspectMouse + conveyor, spikeDensity, time * (1.0 + treble * 0.18));

    // ── Fast motion A: spike eruption packets ────────────────────────────
    // Gaussian envelopes racing outward from the magnet at a clamped speed.
    // Each packet is a closed-form function of (radius, time), so eruptions
    // travel coherently instead of popping in place.
    let eruptSpeed = clamp(0.30 + magnetStrength * 0.55 + bass * 0.45, 0.0, 1.4);
    var erupt = 0.0;
    for (var k = 0u; k < 3u; k = k + 1u) {
        let phase = fract(time * (0.55 + f32(k) * 0.21) * eruptSpeed);
        let packetR = phase * 0.62;
        let d = dist - packetR;
        erupt += exp(-d * d * 620.0) * (1.0 - phase) * (0.55 + bass * 0.7);
    }
    erupt = clamp(erupt, 0.0, 2.2);

    let spikeHeight = (spikeBase * field * (1.2 + magnetStrength) + clickHeight * 0.5
        + erupt * field * 0.55 + length(magnetVelocity) * field * 0.018)
        * mix(1.25, 0.62, fluidViscosity) * held;
    let eps = 1.3 / resolution.y;
    let convMouse = aspectMouse + conveyor;
    let hL = rosensweigHeight(convUV - vec2<f32>(eps, 0.0), convMouse, spikeDensity, time);
    let hR = rosensweigHeight(convUV + vec2<f32>(eps, 0.0), convMouse, spikeDensity, time);
    let hD = rosensweigHeight(convUV - vec2<f32>(0.0, eps), convMouse, spikeDensity, time);
    let hU = rosensweigHeight(convUV + vec2<f32>(0.0, eps), convMouse, spikeDensity, time);
    let normal = normalize(vec3<f32>((hL - hR) * field * 5.0 + clickSlope.x,
        (hD - hU) * field * 5.0 + clickSlope.y, 0.18));
    let viewDir = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));
    let worldPos = vec3<f32>(uv, spikeHeight);
    let lightPos = vec3<f32>(mousePos, 0.5);

    // ═══ AMBIENT OCCLUSION ═══
    let ao = ambientOcclusion(uv, normal.xy, 0.03 + fluidViscosity * 0.02);

    // ═══ 3-POINT PBR LIGHTING ═══
    let roughness = 0.15 + (1.0 - highlightSharpness) * 0.4;
    let metallic = 0.85 + field * 0.15;
    let baseColor = vec3<f32>(0.02, 0.02, 0.04) + vec3<f32>(0.08, 0.08, 0.12) * liquid;

    let litColor = threePointLighting(normal, viewDir, lightPos, worldPos, roughness, metallic, baseColor, ao);

    // ═══ ANISOTROPIC SHEEN ON SPIKE TIPS ═══
    let tangent = normalize(vec3<f32>(cos(time * 0.5), sin(time * 0.5), 0.0));
    let sheen = anisotropicSheen(viewDir, normal, tangent, roughness * 0.5);
    let sheenColor = vec3<f32>(0.7, 0.75, 0.85) * sheen * field * 2.0;

    // ═══ RIM LIGHTING ═══
    let rim = rimLighting(viewDir, normal, 1.0 + bass * 1.5);
    let rimColor = vec3<f32>(0.6, 0.85, 1.0) * rim * field * (0.5 + mids * 0.5);

    // Audio adds turbulence
    let turb = noise(uv * 30.0 + time * 2.0) * bass * 0.2;

    // Combine
    var color = litColor + sheenColor + rimColor;
    color = color + vec3<f32>(turb, turb * 0.5, turb * 0.8) * 0.5;

    // Subsurface glow for thin spike tips, now on an iridescent ramp keyed to
    // spike height rather than a fixed purple, with a per-band FFT hue offset
    // so the colour field reacts across the spectrum, and prismatic dispersion
    // along the eruption front.
    let bandIdx = u32(clamp(uv.x, 0.0, 0.999) * 8.0);
    let band = clamp(plasmaBuffer[bandIdx + 1u].x, 0.0, 1.0);
    let hue = fract(spikeHeight * 0.9 + erupt * 0.35 + time * 0.07
                    + band * 0.26 + field * 0.2);
    let disperse = clamp(erupt * 0.04 + conveyorRate * 0.12, 0.0, 0.06);
    let irid = vivify(vec3<f32>(
        ferroSpectrum(hue - disperse).r,
        ferroSpectrum(hue).g,
        ferroSpectrum(hue + disperse).b), 0.7);

    let sss = pow(max(0.0, spikeHeight - 0.3), 2.0) * 2.0 * mids;
    color = color + irid * sss;
    // Eruption crests flare on the same palette, half a turn round the wheel.
    color = color + vivify(ferroSpectrum(fract(hue + 0.5)), 0.7) * erupt * field * (0.35 + treble * 0.5);

    // Audio-reactive pulse: bass drives light intensity
    let pulse = 1.0 + bass * 0.3 + sin(time * 3.0 + dist * 10.0) * bass * 0.2;
    color = color * pulse;

    // Bloom-weighted alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alphaLive = clamp(0.48 + field * 0.35 + spikeHeight * 0.22 + luma * 0.2 + bass * 0.05, 0.0, 1.0);

    // Exact display history trails behind viscous spike relaxation.
    let drift = vec2<i32>(round((aspectUV - aspectMouse) / max(dist, 0.001)
        * mix(0.4, 2.2, fluidViscosity) + clickSlope));
    let prev = textureLoad(dataTextureC, clamp(vec2<i32>(global_id.xy) - drift,
        vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)), 0);
    let persistence = mix(0.18, 0.68, fluidViscosity) * clamp(field + clickHeight, 0.0, 1.0);
    color = mix(color, prev.rgb * 0.968, persistence);
    let alpha = mix(alphaLive, prev.a * 0.96, persistence * 0.5);

    // Premultiplied alpha writeback
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesToneMap(color) * alpha, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(min(color, vec3<f32>(8.0)), alpha));
    let sourceDepth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(max(sourceDepth * 0.82,
        clamp(field * 0.45 + spikeHeight * 0.48, 0.0, 0.95)), 0.0, 0.0, 0.0));
}
