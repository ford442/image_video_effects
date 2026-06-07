// molten-gold.wgsl
// Molten gold liquid metal effect — optimized for Generative Showcase
// Showcase features: strong idle animation, satisfying mouse claim, audio-reactive

// 13-binding universal layout (matches all 694+ shaders in this repo)
@group(0) @binding(0) var nearestSampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTexture: texture_2d<f32>;
@group(0) @binding(5) var nearestClampSampler: sampler;
@group(0) @binding(6) var depthWriteTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var videoTexture: texture_2d<f32>;
@group(0) @binding(12) var videoSampler: sampler;

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

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = vec2<f32>(id.xy) / dims;
    let aspect = dims.x / dims.y;

    let t = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Zoom params
    let flowSpeed = mix(0.15, 0.6, u.zoom_params.x);
    let turbulence = mix(1.2, 3.5, u.zoom_params.x * 0.7);
    let glowIntensity = u.zoom_params.y;
    let specularStrength = u.zoom_params.z;
    let highlightFreq = u.zoom_params.w;

    // Audio data from extraBuffer
    let bass = extraBuffer[0];
    let mid = extraBuffer[1];
    let treble = extraBuffer[2];
    let audioReactive = 1.0; // controlled by the A-toggle in App.tsx

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

    // Molten gold layers
    let molten = fbm(q * turbulence + vec2<f32>(t * 0.2, t * -0.15), 5);
    let detail = fbm(q * 4.2 + t * 0.8, 3);

    // Gold palette
    let goldBase = vec3<f32>(1.0, 0.72, 0.25);
    let goldDark = vec3<f32>(0.35, 0.18, 0.05);
    let goldHot = vec3<f32>(1.0, 0.92, 0.6);

    var color = mix(goldDark, goldBase, molten * 0.85 + 0.15);
    color = mix(color, goldHot, detail * 0.6 + mousePull * 0.4);

    // Glow layer with audio bass
    let glow = pow(molten * 0.7 + detail * 0.3, 1.8) * mix(0.6, 1.4, glowIntensity);
    color += goldHot * glow * (0.6 + bass * 0.8);

    // Specular highlights with treble
    let spec = pow(smoothstep(0.65, 0.95, molten + detail * 0.4), 3.0);
    color += vec3<f32>(1.0, 0.95, 0.7) * spec * mix(0.8, 2.2, specularStrength) * (1.0 + treble * 1.5);

    // Ripple shimmer from mid + highlight frequency
    let ripple = sin((molten * 12.0 + t * 3.0) * (1.0 + mid * 2.0) * (0.5 + highlightFreq * 1.5)) * 0.035;
    color += ripple * (0.4 + treble * 0.6);

    // Tone and vignette
    color = pow(color, vec3<f32>(0.95));
    let vignette = 1.0 - length(uv - 0.5) * 0.6;
    color *= vignette * 0.95 + 0.05;

    // Output
    textureStore(writeTexture, id.xy, vec4<f32>(color, 1.0));
    textureStore(depthWriteTexture, id.xy, vec4<f32>(molten, 0.0, 0.0, 1.0));
}
