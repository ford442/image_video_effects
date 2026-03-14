// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Prism Cascade
//  Category: EFFECT | Complexity: VERY_HIGH
//  Colors separate along curved refractive planes like light through liquid
//  prisms, creating a 3D depth illusion. Image detail is preserved but colors
//  float independently through layered color-space warping.
//  Mathematical approach: Snell's law refraction per-channel, depth-driven
//  curvature fields, spectral dispersion with Cauchy coefficients, feedback
//  trail blending for temporal persistence of prismatic ghosts.
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
    zoom_config: vec4<f32>,  // x=PrismDensity, y=MouseX, z=MouseY, w=TrailDecay
    zoom_params: vec4<f32>,  // x=Dispersion, y=CurvatureStrength, z=RefractIndex, w=SpectrumShift
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Hash functions
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var k = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(k) * 43758.5453);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth 2D value noise
// ─────────────────────────────────────────────────────────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  FBM for curvature field
// ─────────────────────────────────────────────────────────────────────────────
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Curl noise for flow field
// ─────────────────────────────────────────────────────────────────────────────
fn curlField(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.01;
    let nx = fbm(p + vec2<f32>(e, 0.0) + t * 0.1, 4) - fbm(p - vec2<f32>(e, 0.0) + t * 0.1, 4);
    let ny = fbm(p + vec2<f32>(0.0, e) + t * 0.1, 4) - fbm(p - vec2<f32>(0.0, e) + t * 0.1, 4);
    return vec2<f32>(ny, -nx) / (2.0 * e);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cauchy dispersion: refractive index varies per wavelength
//  Red (700nm) → lower refraction, Blue (450nm) → higher refraction
// ─────────────────────────────────────────────────────────────────────────────
fn cauchyRefract(baseIOR: f32, channel: f32) -> f32 {
    // channel: 0=R, 1=G, 2=B
    let wavelength = mix(0.70, 0.45, channel / 2.0);
    let B = 0.01;
    return baseIOR + B / (wavelength * wavelength);
}

// ─────────────────────────────────────────────────────────────────────────────
//  2D refraction through a curved surface
//  Returns displaced UV for a single color channel
// ─────────────────────────────────────────────────────────────────────────────
fn prismRefract(uv: vec2<f32>, normal: vec2<f32>, ior: f32) -> vec2<f32> {
    let incident = normalize(uv - 0.5);
    let cosI = dot(-incident, normal);
    let sinT2 = (1.0 / (ior * ior)) * (1.0 - cosI * cosI);
    let cosT = sqrt(max(0.0, 1.0 - sinT2));
    let refracted = incident / ior + normal * (cosI / ior - cosT);
    return refracted;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Compute depth-driven surface normal (gradient of depth field)
// ─────────────────────────────────────────────────────────────────────────────
fn depthNormal(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let dR = textureSampleLevel(readDepthTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    return normalize(vec2<f32>(dR - dL, dU - dD) + vec2<f32>(0.0001));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
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
    let dispersion = u.zoom_params.x * 0.06 + 0.005;       // 0.005 – 0.065
    let curvatureStr = u.zoom_params.y * 3.0 + 0.5;        // 0.5 – 3.5
    let baseIOR = u.zoom_params.z * 0.4 + 1.1;             // 1.1 – 1.5
    let spectrumShift = u.zoom_params.w;                     // 0 – 1
    let prismDensity = u.zoom_config.x * 4.0 + 1.0;        // 1 – 5
    let trailDecay = u.zoom_config.w * 0.3 + 0.6;          // 0.6 – 0.9

    // ─────────────────────────────────────────────────────────────────────────
    //  Read depth and compute curved refractive surface
    // ─────────────────────────────────────────────────────────────────────────
    let depth = textureSampleLevel(readDepthTexture, u_sampler, uv, 0.0).r;
    let dNormal = depthNormal(uv, texel);

    // Curl flow creates slowly drifting prism orientations
    let flow = curlField(uv * prismDensity, time);
    let prismNormal = normalize(dNormal * curvatureStr + flow * 0.3);

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: local curvature spikes
    // ─────────────────────────────────────────────────────────────────────────
    var rippleWarp = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let dist = distance(uv, r.xy);
        let age = time - r.z;
        if (age > 0.0 && age < 4.0) {
            let wave = sin(dist * 40.0 - age * 5.0) * exp(-dist * 8.0) * exp(-age * 0.8);
            rippleWarp += normalize(uv - r.xy + vec2<f32>(0.0001)) * wave * 0.02;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Per-channel prismatic refraction (Cauchy dispersion)
    // ─────────────────────────────────────────────────────────────────────────
    let effectiveNormal = normalize(prismNormal + rippleWarp * 20.0);

    // Each channel refracts differently through the curved surface
    let iorR = cauchyRefract(baseIOR, 0.0 + spectrumShift);
    let iorG = cauchyRefract(baseIOR, 1.0 + spectrumShift);
    let iorB = cauchyRefract(baseIOR, 2.0 + spectrumShift);

    let dispR = prismRefract(uv, effectiveNormal, iorR) * dispersion;
    let dispG = prismRefract(uv, effectiveNormal, iorG) * dispersion;
    let dispB = prismRefract(uv, effectiveNormal, iorB) * dispersion;

    // Depth modulates displacement: foreground refracts more than background
    let depthScale = 0.3 + depth * 0.7;

    let uvR = clamp(uv + dispR * depthScale + rippleWarp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + dispG * depthScale + rippleWarp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + dispB * depthScale + rippleWarp, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var prismColor = vec3<f32>(r, g, b);

    // ─────────────────────────────────────────────────────────────────────────
    //  Secondary refraction layer: a second curved plane offset in depth
    // ─────────────────────────────────────────────────────────────────────────
    let flow2 = curlField(uv * prismDensity * 1.5 + 3.7, time * 0.7);
    let norm2 = normalize(dNormal * curvatureStr * 0.6 + flow2 * 0.5);
    let disp2R = prismRefract(uv, norm2, iorR * 1.05) * dispersion * 0.5;
    let disp2B = prismRefract(uv, norm2, iorB * 1.05) * dispersion * 0.5;

    let uv2R = clamp(uv + disp2R * (1.0 - depthScale), vec2<f32>(0.0), vec2<f32>(1.0));
    let uv2B = clamp(uv + disp2B * (1.0 - depthScale), vec2<f32>(0.0), vec2<f32>(1.0));

    let r2 = textureSampleLevel(readTexture, u_sampler, uv2R, 0.0).r;
    let b2 = textureSampleLevel(readTexture, u_sampler, uv2B, 0.0).b;
    prismColor = mix(prismColor, vec3<f32>(r2, prismColor.g, b2), 0.3);

    // ─────────────────────────────────────────────────────────────────────────
    //  Prismatic caustic highlights
    // ─────────────────────────────────────────────────────────────────────────
    let causticPattern = fbm(uv * prismDensity * 8.0 + flow * 2.0 + time * 0.3, 5);
    let causticEdge = smoothstep(0.55, 0.7, causticPattern);
    let causticHue = fract(causticPattern * 3.0 + time * 0.05 + spectrumShift);
    let causticCol = vec3<f32>(
        smoothstep(0.0, 0.33, causticHue) - smoothstep(0.33, 0.66, causticHue),
        smoothstep(0.33, 0.66, causticHue) - smoothstep(0.66, 1.0, causticHue),
        smoothstep(0.66, 1.0, causticHue) + (1.0 - smoothstep(0.0, 0.15, causticHue))
    );
    prismColor += causticCol * causticEdge * 0.15 * dispersion * 10.0;

    // ─────────────────────────────────────────────────────────────────────────
    //  Feedback trail: prismatic ghosts persist and drift
    // ─────────────────────────────────────────────────────────────────────────
    let trailUV = clamp(uv + flow * 0.003, vec2<f32>(0.0), vec2<f32>(1.0));
    let trail = textureSampleLevel(dataTextureC, u_sampler, trailUV, 0.0).rgb;
    let finalColor = mix(prismColor, trail, trailDecay);

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
