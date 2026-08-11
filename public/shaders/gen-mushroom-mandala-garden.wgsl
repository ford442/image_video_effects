// Mushroom Mandala Garden — breathing caps, luminous gills, and spore bursts.

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
    return vec3<f32>(0.54, 0.48, 0.52) + vec3<f32>(0.46, 0.51, 0.48) *
        cos(TAU * (vec3<f32>(1.0, 0.69, 0.43) * t + vec3<f32>(0.03, 0.31, 0.62)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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
    let capCount = u.zoom_params.x;
    let breatheRate = u.zoom_params.y;
    let gillDetail = u.zoom_params.z;
    let bioluminescence = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (5.0 + capCount * 3.0)) * u.zoom_config.w;
    p += mouseDelta / mouseDistance * dragMask * sin(time * 3.0) * (0.03 + gillDetail * 0.08);

    let radius = max(length(p), 0.002);
    let angle = atan2(p.y, p.x);
    let segments = 5.0 + floor(capCount * 9.0);
    let petalAngle = abs(fract(angle / TAU * segments + 0.5) - 0.5) * 2.0;
    let breathe = 1.0 + sin(time * (0.8 + breatheRate * 4.5) + radius * 12.0) * (0.05 + audio.x * 0.06);
    let ringCoord = fract(radius * (4.0 + capCount * 7.0) * breathe) - 0.5;
    let cap = exp(-pow(ringCoord / (0.18 + capCount * 0.06), 2.0)) * smoothstep(0.95, 0.10, petalAngle);
    let stem = exp(-petalAngle * (10.0 + capCount * 15.0)) * smoothstep(0.48, 0.05, abs(ringCoord));
    let gills = pow(0.5 + 0.5 * cos(petalAngle * (18.0 + gillDetail * 52.0) - time * (1.0 + breatheRate * 2.0)), 9.0) * cap;
    let sporeLane = fract(radius * (8.0 + gillDetail * 16.0) - time * (0.7 + breatheRate * 2.5));
    let spores = exp(-pow((sporeLane - 0.5) / 0.08, 2.0)) * pow(hash21(floor(p * 40.0 + 70.0)), 5.0);
    let myceliumPhase = sin(p.x * (24.0 + gillDetail * 26.0) + sin(p.y * 13.0 - time * breatheRate * 2.0) * 3.0);
    let mycelium = pow(1.0 - abs(myceliumPhase), 14.0) * smoothstep(0.72, 0.08, radius);
    let fairyRing = exp(-abs(fract(radius * (7.0 + capCount * 9.0) - time * 0.18) - 0.5) * 24.0) * (0.5 + 0.5 * cos(angle * segments));

    var clickSpores = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.4) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let distanceToClick = length(delta);
            let front = abs(distanceToClick - age * (0.14 + breatheRate * 0.16));
            let rays = pow(0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 13.0 + age * 5.0), 8.0);
            clickSpores += (1.0 - smoothstep(0.0, 0.035, front)) * (0.35 + rays) * (1.0 - age / 3.4);
        }
    }

    let hue = angle / TAU + radius * 0.55 + time * 0.08 + bioluminescence * 0.35;
    var hdr = palette(hue) * cap * (0.9 + bioluminescence * 2.1 + audio.y);
    hdr += palette(hue + 0.28) * (gills * 1.8 + stem * 0.8) * (0.6 + audio.z);
    hdr += palette(hue + 0.6) * (spores * 1.2 + clickSpores * 1.8);
    hdr += palette(hue + 0.46) * (mycelium * 0.75 + fairyRing * 0.55) * (0.5 + audio.y);
    hdr += vec3<f32>(0.4, 1.0, 0.65) * dragMask * (0.5 + bioluminescence);
    let historyUV = clamp(uv + vec2<f32>(sin(angle) / max(aspect, 0.001), -cos(angle)) * (0.002 + breatheRate * 0.006), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + bioluminescence * 0.16 + dragMask * 0.14, 0.0, 0.40));
    let structure = clamp(cap + gills * 0.5 + spores + mycelium * 0.3 + clickSpores * 0.45, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(hdr), clamp(0.12 + structure * 0.86, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.10 + cap * 0.48 + gills * 0.22 + clickSpores * 0.18, 0.0, 0.95), 0.0, 0.0, 0.0));
}
