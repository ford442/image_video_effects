// Liquid Cathedral Dream — melting stained-glass arches with pointer refraction.

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

const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(TAU * (vec3<f32>(1.0, 0.78, 0.52) * t + vec3<f32>(0.0, 0.24, 0.55)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
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
    let spireDensity = u.zoom_params.x;
    let meltSpeed = u.zoom_params.y;
    let refraction = u.zoom_params.z;
    let stainedHue = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (4.0 + spireDensity * 4.0)) * u.zoom_config.w;
    let dragDirection = mouseDelta / mouseDistance;
    p -= dragDirection * dragMask * (0.05 + refraction * 0.16);

    let flowTime = time * (0.25 + meltSpeed * 1.8 + audio.y * 0.18);
    let melt = vec2<f32>(
        sin(p.y * 8.0 + flowTime * 1.3) + sin(p.y * 17.0 - flowTime),
        cos(p.x * 10.0 - flowTime * 0.8)
    ) * (0.015 + refraction * 0.065);
    let q = p + melt;
    let columns = 3.0 + floor(spireDensity * 9.0);
    let cellX = fract((q.x + 1.0) * columns * 0.5) - 0.5;
    let tierY = fract((q.y + flowTime * 0.08) * (3.0 + spireDensity * 3.0)) - 0.5;
    let archRadius = length(vec2<f32>(cellX * 1.25, max(tierY, 0.0) * 0.9));
    let arch = exp(-abs(archRadius - (0.27 + sin(flowTime + q.x * 4.0) * 0.035)) * (35.0 + spireDensity * 35.0));
    let spire = exp(-abs(cellX) * (28.0 + spireDensity * 34.0)) * smoothstep(0.5, -0.15, tierY);
    let window = smoothstep(0.43, 0.05, archRadius) * smoothstep(-0.45, 0.20, tierY);
    let glassPulse = 0.5 + 0.5 * sin(q.y * 19.0 - flowTime * 4.0 + cellX * 8.0);
    let roseAngle = atan2(tierY, cellX);
    let roseRadius = length(vec2<f32>(cellX, tierY));
    let roseTracery = pow(0.5 + 0.5 * cos(roseAngle * (6.0 + floor(spireDensity * 6.0)) + flowTime), 12.0) *
        exp(-abs(roseRadius - 0.24) * (32.0 + refraction * 28.0));
    let floorCaustic = pow(0.5 + 0.5 * sin(q.x * 28.0 + q.y * 11.0 - flowTime * 5.0), 16.0) * smoothstep(0.35, -0.42, tierY);

    var clickRose = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.2) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(delta) - age * (0.16 + meltSpeed * 0.14));
            let petals = 0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 8.0 + age * 4.0);
            clickRose += (1.0 - smoothstep(0.0, 0.028, ring)) * petals * (1.0 - age / 3.2);
        }
    }

    let hue = stainedHue + cellX * 0.7 + tierY * 0.35 + flowTime * 0.06;
    var hdr = palette(hue) * window * (0.5 + glassPulse * 1.4 + audio.z);
    hdr += palette(hue + 0.32) * (arch * 1.8 + spire * 0.8) * (0.8 + audio.x);
    hdr += palette(hue + 0.57) * (roseTracery * 1.35 + floorCaustic * 0.45) * (0.6 + audio.y);
    hdr += palette(hue + clickRose * 0.4) * clickRose * 2.0;
    hdr += vec3<f32>(1.0, 0.35, 0.75) * dragMask * (0.5 + refraction * 1.5);
    let historyUV = clamp(uv + vec2<f32>(melt.x / max(aspect, 0.001), 0.004 + meltSpeed * 0.007), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + refraction * 0.20 + dragMask * 0.12, 0.0, 0.42));
    let structure = clamp(max(arch, spire) + window * 0.45 + roseTracery * 0.35 + clickRose * 0.5, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr), clamp(0.16 + structure * 0.82, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.12 + structure * 0.78, 0.0, 0.95), 0.0, 0.0, 0.0));
}
