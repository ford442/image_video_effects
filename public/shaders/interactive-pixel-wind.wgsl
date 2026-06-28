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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Interactive Pixel Wind
// Param1: Wind Strength
// Param2: Turbulence
// Param3: Trail Length
// Param4: Color Shift

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

fn noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let a = random(i);
    var b = random(i + vec2<f32>(1.0, 0.0));
    let c = random(i + vec2<f32>(0.0, 1.0));
    var d = random(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var amp = 0.5;
    var sum = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        sum = sum + noise(p) * amp;
        p = p * 2.03 + vec2<f32>(17.1, 9.2);
        amp = amp * 0.5;
    }
    return sum;
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52, 0.50, 0.48) +
           vec3<f32>(0.48, 0.42, 0.38) *
           cos(6.28318 * (vec3<f32>(1.0, 0.74, 0.42) * t + vec3<f32>(0.02, 0.23, 0.48)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let overall = plasmaBuffer[0].w;

    let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.55); // Max wind speed
    let turbulence = u.zoom_params.y;
    let trails = u.zoom_params.z;
    let shift = u.zoom_params.w;

    // Calculate wind vector based on mouse position relative to center
    // Center is (0.5, 0.5)
    var windDir = vec2<f32>(0.0);
    if (mousePos.x >= 0.0) {
        windDir = mousePos - vec2<f32>(0.5);
    } else {
        // Default wind if no mouse interaction
        windDir = vec2<f32>(sin(time * 0.5), cos(time * 0.5)) * 0.5;
    }

    // Layered wind curls keep the motion organic instead of a flat smear.
    let gust = fbm(uv * 6.0 + vec2<f32>(time * 0.18, -time * 0.12));
    let curlA = fbm(uv * 13.0 + vec2<f32>(time * 0.7, gust * 2.0));
    let curlB = fbm(uv.yx * 14.0 + vec2<f32>(-time * 0.55, gust * 1.7));
    let turbOffset = (vec2<f32>(curlA, curlB) - 0.5) * turbulence * 0.075;

    let offset = windDir * strength + turbOffset;

    // Sample current frame with offset
    let baseUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);

    // Chromatic aberration (Color Shift) based on wind speed
    let redOffset = offset * (1.0 + shift * 6.0 + treble * 0.7);
    let blueOffset = offset * (1.0 - shift * 4.0 - bass * 0.25);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv - redOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    var b = textureSampleLevel(readTexture, u_sampler, clamp(uv - blueOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec4<f32>(r, color.g, b, color.a);

    // Feedback trail (Wind carries the trails too)
    let historyUV = clamp(uv - offset * 0.62, vec2<f32>(0.0), vec2<f32>(1.0)); // Trails move slower
    let history = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

    let speedGlow = smoothstep(0.005, 0.12, length(offset));
    let streak = pow(max(0.0, 1.0 - abs(noise(uv * vec2<f32>(60.0, 9.0) + time) - 0.5) * 3.2), 5.0);
    let spectral = palette(gust + time * 0.04 + shift + mids * 0.12);
    var hdr = mix(color.rgb, history.rgb, clamp(trails * 0.85, 0.0, 0.95));
    hdr = hdr * (0.94 + speedGlow * 0.18);
    hdr = hdr + spectral * streak * speedGlow * (0.35 + overall * 0.7);
    hdr = hdr + vec3<f32>(0.18, 0.34, 0.8) * pow(gust, 3.0) * turbulence * 0.22;

    let radial = length(uv - vec2<f32>(0.5)) * 1.414;
    hdr = hdr * mix(1.0, 0.68, smoothstep(0.35, 1.0, radial));
    let mapped = aces(hdr * (1.05 + bass * 0.25));
    let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
    let outRGB = clamp(mapped + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));
    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(0.18 + pow(max(0.0, luma - 0.55), 2.0) * 2.4 + speedGlow * 0.22, 0.0, 1.0);
    let finalColor = vec4<f32>(outRGB * alpha, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Store history
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass depth
    var d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
