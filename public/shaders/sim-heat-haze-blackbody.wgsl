// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Blackbody
//  Category: advanced-hybrid
//  Features: simulation, blackbody-radiation, temperature-field, convection, mouse-driven, HDR, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: Schlieren along ∇T; buoyant plume shear from dT/dy
//  A packing: raw temperature in A.r
// ═══════════════════════════════════════════════════════════════════
//  Temperature field convection simulation with physically-correct
//  blackbody thermal glow. Hot ground and rising convection plumes
//  radiate with Planck's law colors — cool air stays neutral while
//  intense heat sources glow from red ember to blue-white.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

fn loadTemp(coord: vec2<i32>, max_coord: vec2<i32>) -> f32 {
    let c = clamp(coord, vec2<i32>(0), max_coord);
    return textureLoad(dataTextureC, c, 0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(gid.xy);
    let max_coord = vec2<i32>(resolution) - vec2<i32>(1);
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let temperature = mix(0.2, 1.0, u.zoom_params.x);
    let convectionSpeed = mix(0.5, 3.0, u.zoom_params.y);
    let distortion = mix(0.0, 0.05, u.zoom_params.z);
    let heatSources = mix(1.0, 5.0, u.zoom_params.w);
    let thermalIntensity = mix(0.5, 2.0, temperature);

    var sum = 0.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            sum += loadTemp(coord + vec2<i32>(x, y), max_coord);
        }
    }
    let diffused = sum / 9.0;
    let cooled = diffused * 0.98;

    let groundHeat = smoothstep(0.15, 0.0, uv.y) * temperature * (1.0 + bass * 0.2);

    var sourceHeat = 0.0;
    for (var i: i32 = 0; i < i32(heatSources); i++) {
        let fi = f32(i);
        let sourceX = 0.1 + (hash12(vec2<f32>(fi, 0.0)) * 0.8);
        let sourceY = 0.1 + (hash12(vec2<f32>(fi, 1.0)) * 0.3);
        let sourcePos = vec2<f32>(sourceX, sourceY);
        let dist = length(uv - sourcePos);
        sourceHeat += smoothstep(0.1, 0.0, dist) * temperature * 0.5;
    }

    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseHeat = smoothstep(0.1, 0.0, mouseDist) * temperature * 0.3;

    let newTemp = min(cooled + groundHeat + sourceHeat + mouseHeat, 1.0);
    textureStore(dataTextureA, gid.xy, vec4<f32>(newTemp, 0.0, 0.0, 1.0));

    let tempRight = loadTemp(coord + vec2<i32>(1, 0), max_coord);
    let tempLeft = loadTemp(coord + vec2<i32>(-1, 0), max_coord);
    let tempUp = loadTemp(coord + vec2<i32>(0, 1), max_coord);
    let tempDown = loadTemp(coord + vec2<i32>(0, -1), max_coord);
    let grad = vec2<f32>(tempRight - tempLeft, tempUp - tempDown);

    var displacement = vec2<f32>(
        grad.x * distortion,
        -newTemp * distortion * convectionSpeed * 0.5
    );
    // Idea 2 — plume shear: horizontal lean from dT/dy
    displacement.x += grad.y * distortion * convectionSpeed * 0.4;

    let shimmer = hash12(uv * 50.0 + time * 5.0) * newTemp * distortion * 0.3;
    displacement += vec2<f32>(shimmer);

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Idea 1 — Schlieren streaks along ∇T
    let schlieren = clamp((grad.x * 0.7 + grad.y * 1.3) * 12.0, -0.3, 0.3);
    color = color * (1.0 + schlieren * (0.85 + treble * 0.3));

    let kelvin = mix(800.0, 7000.0, newTemp);
    let thermalColor = blackbodyColor(kelvin) * thermalIntensity;
    let toneMapped = toneMapACES(thermalColor);

    let thermalBlend = smoothstep(0.1, 0.6, newTemp) * 0.75;
    color = mix(color, toneMapped, thermalBlend);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(color, vec3<f32>(luma), newTemp * 0.2);

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let alpha = mix(0.55, 0.98, newTemp * 0.55 + abs(schlieren) * 0.2 + mids * 0.04);

    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
