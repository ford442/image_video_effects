// ═══════════════════════════════════════════════════════════════════════════════
//  Sonic Lava Flow
//  Category: artistic
//  Description: Navier-Stokes-style fluid solver with decayed feedback
//               creating a molten lava overlay with audio reactivity.
//  Features: audio-reactive, mouse-driven, temporal
// ═══════════════════════════════════════════════════════════════════════════════

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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
    return fract(vec2<f32>(n, n * 1.618));
}

fn noise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash22(i).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2D(p: vec2<f32>, octaves: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        val = val + noise2D(p * freq) * amp;
        amp = amp * 0.5;
        freq = freq * 2.0;
    }
    return val;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm2D(p + vec2<f32>(eps, 0.0), 3);
    let n2 = fbm2D(p - vec2<f32>(eps, 0.0), 3);
    let n3 = fbm2D(p + vec2<f32>(0.0, eps), 3);
    let n4 = fbm2D(p - vec2<f32>(0.0, eps), 3);
    return vec2<f32>(n3 - n4, n2 - n1) / (2.0 * eps);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let viscosity = mix(0.3, 0.95, u.zoom_params.x);
    let turbulence = u.zoom_params.y * 3.0;
    let decay = mix(0.8, 0.99, u.zoom_params.z);
    let heatGlow = u.zoom_params.w;

    // Mouse heat source
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let mouseDist = length(uv - mousePos);
    let mouseHeat = select(0.0, exp(-mouseDist * 10.0) * 0.5, mouseDown);

    // Flow velocity field
    let flowP = uv * 3.0 + time * 0.2;
    var velocity = curlNoise(flowP, time) * turbulence;

    // Audio pushes the flow
    velocity = velocity + vec2<f32>(
        cos(time * 2.0 + bass * 5.0) * bass,
        sin(time * 1.7 + mids * 4.0) * mids
    ) * 0.05;

    // Advected coordinate
    let advectUV = uv - velocity * 0.02 * (1.0 - viscosity);

    // Read base video
    let videoCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Lava color palette (temperature map)
    let temp = fbm2D(advectUV * 4.0 + time * 0.3, 4) + bass * 0.3 + mouseHeat;
    let lavaCol = vec3<f32>(
        smoothstep(0.0, 0.3, temp) * 1.0 + smoothstep(0.3, 0.7, temp) * 0.8,
        smoothstep(0.2, 0.5, temp) * 0.6 + smoothstep(0.5, 0.9, temp) * 0.4,
        smoothstep(0.4, 0.8, temp) * 0.3
    );

    // Molten surface detail
    let detail = fbm2D(advectUV * 8.0 - time * 0.5, 3);
    let crust = smoothstep(0.4, 0.6, detail) * 0.3;
    let moltenLava = lavaCol * (0.7 + crust) + vec3<f32>(1.0, 0.6, 0.2) * smoothstep(0.6, 0.8, detail) * 0.5;

    // Decay/feedback blend with video
    let feedback = mix(videoCol, moltenLava, 0.6);

    // Heat shimmer (chromatic distortion)
    let shimmer = sin(uv.y * 100.0 + time * 10.0) * bass * 0.003;
    let rSample = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(shimmer, 0.0), 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let bSample = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(shimmer, 0.0), 0.0).b;
    let chromaticVideo = vec3<f32>(rSample, gSample, bSample);

    // Blend video with lava
    var finalCol = mix(chromaticVideo, feedback, 0.5 + bass * 0.3);

    // Add heat glow
    let glowRadius = 0.3 + bass * 0.2;
    let centerDist = length(uv - vec2<f32>(0.5));
    let glow = exp(-centerDist * centerDist / (glowRadius * glowRadius)) * heatGlow;
    finalCol = finalCol + vec3<f32>(1.0, 0.4, 0.1) * glow * (0.5 + bass);

    // Depth: fluid height
    let depth = temp * 0.5 + 0.25;

    // Sparkle on hot spots
    if (treble > 0.6 && temp > 0.7) {
        let spark = hash22(uv * 100.0 + time).x;
        if (spark > 0.97) {
            finalCol = finalCol + vec3<f32>(1.0, 0.9, 0.7) * treble * 0.5;
        }
    }

    textureStore(writeTexture, id.xy, vec4<f32>(clamp(finalCol, vec3<f32>(0.0), vec3<f32>(2.0)), 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
