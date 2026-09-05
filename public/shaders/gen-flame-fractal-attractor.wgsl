// Flame Fractal Attractor — curling orbit-density fire field
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
    zoom_params: vec4<f32>, // x=Attractor Strength, y=Orbit Speed, z=Curl, w=Ember Bloom
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.0, 0.16, 0.42)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let strength = mix(0.72, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
    let orbitSpeed = mix(0.1, 1.8, clamp(u.zoom_params.y, 0.0, 1.0));
    let curl = mix(0.15, 1.25, clamp(u.zoom_params.z, 0.0, 1.0));
    let emberBloom = mix(0.25, 2.8, clamp(u.zoom_params.w, 0.0, 1.0));
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseDelta = p - mouse;
    p = rot(-time * orbitSpeed * 0.08) * p;
    p += normalize(mouseDelta + vec2<f32>(0.0001)) * sin(length(mouseDelta) * 10.0 - time * 3.0) * held * 0.09;

    var z = p * (1.15 + strength * 0.35);
    var orbitDensity = 0.0;
    var lineTrap = 0.0;
    var hueMoment = 0.0;
    for (var i = 0; i < 36; i++) {
        let fi = f32(i);
        let r2 = max(dot(z, z), 0.0005);
        let swirlAngle = curl * r2 + time * orbitSpeed * 0.025 + audio.y * 0.18;
        let swirled = rot(swirlAngle) * z;
        let folded = abs(swirled) - vec2<f32>(0.42 + audio.x * 0.08, 0.26);
        z = rot(0.72 + sin(time * 0.11) * 0.08) * folded * (0.84 + strength * 0.045) +
            vec2<f32>(-0.16, 0.09 + sin(fi * 1.7) * 0.025);
        let centerTrap = exp(-length(z) * (4.5 + audio.x * 2.0));
        let filament = exp(-abs(z.x * z.y) * (24.0 + audio.z * 16.0)) / (1.0 + r2 * 1.8);
        orbitDensity += centerTrap / (1.0 + fi * 0.08);
        lineTrap += filament * 0.035;
        hueMoment += (centerTrap + filament * 0.03) * fi;
    }

    var clickEmber = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickEmber += exp(-abs(distance(p, center) - age * 0.24) * 70.0) * exp(-age * 1.45);
        }
    }

    let density = min(orbitDensity * 0.38 + lineTrap, 5.0);
    let hue = hueMoment / max(orbitDensity + lineTrap, 0.001) * 0.012 + time * 0.02 + audio.y * 0.13;
    let flameColor = mix(vec3<f32>(1.25, 0.12, 0.015), palette(hue), 0.35 + audio.z * 0.2);
    var hdrColor = vec3<f32>(0.008, 0.003, 0.012) + flameColor * density * (0.55 + emberBloom + audio.x * 0.65);
    hdrColor += vec3<f32>(1.2, 0.42 + audio.y * 0.25, 0.06 + audio.z * 0.25) * lineTrap * emberBloom;
    hdrColor += vec3<f32>(1.0, 0.24, 0.65 + audio.z * 0.5) * clickEmber * 0.42;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.055 + audio.x * 0.07), vec3<f32>(0.0), vec3<f32>(8.0));
    let mapped = acesToneMap(hdrColor);
    let alpha = clamp(density * 0.42 + lineTrap * 0.25 + clickEmber * 0.1, 0.02, 0.98);
    let depth = clamp(density * 0.22 + orbitDensity * 0.035, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
