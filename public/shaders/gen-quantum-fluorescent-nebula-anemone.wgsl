// ----------------------------------------------------------------
// Quantum-Fluorescent Nebula-Anemone
// Category: generative
// Organic quantum-nebula with fluorescent anemone tentacles.
// Mouse/clicks create disturbance that makes tentacles reach + pulse.
// ----------------------------------------------------------------

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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tentacle Reach, y=Fluorescence, z=Nebula Density, w=Quantum Freq
    ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 6; i++) {
        value += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return value;
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(gid.xy) / size;
    if (gid.x >= u32(size.x) || gid.y >= u32(size.y)) { return; }

    let time = u.config.x;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let tentacleReach = u.zoom_params.x;
    let fluorescence = u.zoom_params.y;
    let nebulaDensity = u.zoom_params.z;
    let quantumFreq = u.zoom_params.w;

    // Read previous frame
    var col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // === Nebula Base (volumetric clouds) ===
    var p = uv * 6.0 - 3.0;
    p += vec2<f32>(sin(time * 0.15), cos(time * 0.2)) * 0.8;

    let nebula = fbm(p * 1.2 + time * vec2<f32>(0.1, 0.15)) * nebulaDensity;
    let nebula2 = fbm(p * 2.4 - time * vec2<f32>(0.2, 0.1)) * (nebulaDensity * 0.6);

    // === Quantum Interference Field ===
    let qWave = sin(length(p) * quantumFreq + time * 6.0) *
                cos(p.x * quantumFreq * 1.3 - time * 4.0) *
                sin(p.y * quantumFreq * 0.8 + time * 5.0);
    let quantum = (qWave * 0.5 + 0.5) * 0.8;

    // === Fluorescent Anemone Tentacles ===
    var anemone = 0.0;
    var tentacleColor = vec3<f32>(0.0);

    for (var i = 0; i < 18; i++) {
        let angle = f32(i) * 3.14159 * 2.0 / 18.0 + time * 0.35;
        let tentacleP = rot(angle) * p;

        // Tentacle shape with sway
        let sway = sin(time * 3.0 + f32(i) * 1.7) * 0.4;
        let dist = length(tentacleP + vec2<f32>(sway, 0.0)) - 1.6;

        // Reach toward mouse
        let mouseDir = normalize(mouse - uv);
        let reach = tentacleReach * 0.8;
        let mouseInfluence = max(0.0, 1.0 - length(uv - mouse) * 3.5) * reach;

        let tent = exp(-dist * dist * (3.5 - mouseInfluence * 1.2));
        anemone += tent * 0.75;

        // Fluorescent color per tentacle
        let hueShift = f32(i) * 0.07 + time * 0.4;
        let tentColor = vec3<f32>(
            sin(hueShift) * 0.5 + 0.5,
            sin(hueShift + 2.1) * 0.5 + 0.5,
            sin(hueShift + 4.2) * 0.5 + 0.5
        );
        tentacleColor += tentColor * tent * fluorescence;
    }

    // === Ripple Interaction (tentacles react) ===
    var rippleInfluence = 0.0;
    for (var i = 0; i < 20; i++) {
        let r = u.ripples[i];
        let d = length(uv - r.xy);
        if (d < 0.35) {
            rippleInfluence += (0.35 - d) * r.z * 2.5;
        }
    }

    // === Final Composition ===
    var finalColor = col * 0.88; // gentle persistence

    // Nebula glow
    finalColor += vec4<f32>(nebula * vec3<f32>(0.4, 0.2, 0.9), 1.0) * 0.55;
    finalColor += vec4<f32>(nebula2 * vec3<f32>(0.6, 0.3, 1.0), 1.0) * 0.4;

    // Quantum sparkles
    finalColor += vec4<f32>(quantum * vec3<f32>(1.0, 0.8, 1.5), 1.0) * 0.35;

    // Anemone tentacles + fluorescence
    finalColor += vec4<f32>(tentacleColor, 1.0) * 0.85;
    finalColor += vec4<f32>(anemone * vec3<f32>(0.9, 0.5, 1.6), 1.0) * 0.7;

    // Mouse attraction glow
    let mouseDist = length(uv - mouse);
    let mouseGlow = exp(-mouseDist * 12.0) * 1.2;
    finalColor += vec4<f32>(1.0, 0.4, 1.8, 1.0) * mouseGlow * fluorescence;

    // Ripple boost
    finalColor += vec4<f32>(0.6, 0.2, 1.4, 1.0) * rippleInfluence * 0.6;

    // Gentle chromatic aberration on edges
    finalColor.r += 0.015 * sin(time * 2.0 + uv.y * 30.0);
    finalColor.b += 0.015 * cos(time * 2.3 + uv.x * 30.0);

    finalColor = clamp(finalColor, vec4<f32>(0.0), vec4<f32>(1.8));
    finalColor = pow(finalColor, vec4<f32>(0.92)); // slight gamma lift for glow

    textureStore(writeTexture, gid.xy, finalColor);
}
