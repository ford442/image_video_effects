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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mousePos = u.zoom_config.yz;

    let magnetStrength = u.zoom_params.x * (1.0 + bass * 0.5);
    let spikeDensity = u.zoom_params.y;
    let fluidViscosity = u.zoom_params.z;
    let highlightSharpness = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let aspectMouse = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = length(aspectUV - aspectMouse);

    // Magnetic field falls off with distance
    let field = smoothstep(0.5, 0.0, dist) * magnetStrength;

    // Base liquid surface
    let liquid = fbm(uv * (8.0 + spikeDensity * 20.0) + time * 0.1, 4);

    // Spikes rise toward mouse
    let spikeNoise = fbm(uv * 15.0 + vec2<f32>(time * 0.2, 0.0), 3);
    let spikeHeight = spikeNoise * field * 2.0 * fluidViscosity;

    // Build 3D normal for lighting
    let normal = normalize(vec3<f32>(spikeNoise - 0.5, 0.5, spikeHeight * 0.3));
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

    // Subsurface glow for thin spike tips (purple/magenta)
    let sss = pow(max(0.0, spikeHeight - 0.3), 2.0) * 2.0 * mids;
    color = color + vec3<f32>(0.5, 0.1, 0.4) * sss;

    // Audio-reactive pulse: bass drives light intensity
    let pulse = 1.0 + bass * 0.3 + sin(time * 3.0 + dist * 10.0) * bass * 0.2;
    color = color * pulse;

    // Bloom-weighted alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.6 + field * 0.4 + luma * 0.3 + bass * 0.05, 0.0, 1.0);

    // Premultiplied alpha writeback
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * alpha, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(field, 0.0, 0.0, 0.0));
}
