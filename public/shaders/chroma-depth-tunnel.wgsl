// Chroma depth tunnel with axial flight, spectral runners, and click shock rings.

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

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52, 0.50, 0.50) + vec3<f32>(0.48, 0.45, 0.42) *
        cos(6.28318 * (vec3<f32>(1.0, 0.68, 0.44) * t + vec3<f32>(0.00, 0.26, 0.57)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let speed = mix(-7.0, 7.0, u.zoom_params.x);
    let density = 1.0 + u.zoom_params.y * 5.0;
    let chroma = u.zoom_params.z * 0.05 * (1.0 + audio.x * 0.3 + audio.y * 0.15);
    let centerFade = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    let p = uv - mouse;
    let radius = length(vec2<f32>(p.x * aspect, p.y));
    let angle = atan2(p.y, p.x);
    let inverseRadius = 1.0 / max(radius, 0.004);

    // Axial motion and a helical offset form two independent smooth conveyors.
    let flight = time * speed;
    let helix = sin(angle * (5.0 + density) + inverseRadius * 0.12 - time * (3.0 + audio.y * 2.0));
    let tunnelBase = vec2<f32>(angle / 6.28318 + 0.5 + helix * 0.018, inverseRadius * 0.08 * density + flight * 0.07);
    let rUV = fract(tunnelBase + vec2<f32>(chroma, 0.0));
    let gUV = fract(tunnelBase);
    let bUV = fract(tunnelBase - vec2<f32>(chroma, 0.0));
    var color = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );

    let fog = mix(1.0, smoothstep(0.0, max(centerFade, 0.001), radius), step(0.001, centerFade));
    let ringPhase = inverseRadius * density * 0.45 - flight * 4.0;
    let ribs = pow(0.5 + 0.5 * sin(ringPhase), 10.0);
    let runnerPhase = fract(angle / 6.28318 * (6.0 + density) + inverseRadius * 0.04 - time * (1.8 + abs(speed)));
    let runner = exp(-pow((runnerPhase - 0.5) / 0.065, 2.0));

    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.5) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.26 + audio.x * 0.08));
            shock += (1.0 - smoothstep(0.0, 0.025, ring)) * (1.0 - age / 2.5);
        }
    }

    let spectral = palette(inverseRadius * 0.04 + angle * 0.1 + time * 0.12);
    var hdr = color * (0.65 + fog * 0.38);
    hdr += spectral * ribs * fog * (0.7 + audio.x * 1.2);
    hdr += palette(time * 0.1 + runnerPhase) * runner * (1.0 + audio.z + mouseDown * 0.65);
    hdr += vec3<f32>(0.25, 0.65, 1.0) * shock * 1.2;
    let historyUV = clamp(uv - normalize(p + vec2<f32>(0.0001)) * (0.004 + abs(speed) * 0.0015), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.12 + runner * 0.24, 0.0, 0.42));
    let spatialDither = (fract(52.9829189 * fract(dot(vec2<f32>(global_id.xy), vec2<f32>(0.06711056, 0.00583715)))) - 0.5) / 255.0;
    let mapped = clamp(aces(hdr * 1.14) + vec3<f32>(spatialDither), vec3<f32>(0.0), vec3<f32>(1.0));
    let alpha = clamp(fog * (0.16 + inverseRadius * 0.012 + ribs * 0.35 + runner * 0.25), 0.0, 1.0);
    let output = vec4<f32>(mapped * alpha, alpha);

    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
