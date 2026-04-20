// ═══════════════════════════════════════════════════════════════════
//  Honey Melt Blackbody
//  Category: advanced-hybrid
//  Features: hex-grid, blackbody-radiation, viscous-material, subsurface,
//            mouse-driven
//  Complexity: Very High
//  Chunks From: honey-melt, spec-blackbody-thermal
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  Honeycomb cells where thickness maps to blackbody temperature.
//  Thick honey glows hot with amber radiation; thin drips cool to
//  deep red. Mouse heat locally excites cells to white-hot plasma.
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

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal) ═══
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

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    let time = u.config.x;

    // Parameters
    let gridSize = mix(10.0, 80.0, u.zoom_params.x);
    let meltRadius = u.zoom_params.y * 0.5;
    let distortStr = u.zoom_params.z;
    let softness = u.zoom_params.w;
    let tempRangeLow = 1200.0;
    let tempRangeHigh = 6000.0;

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Hex grid
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let uvScaled = uv * aspectVec * gridSize;
    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);
    let centerA = idA * r;
    let centerB = idB * r + h;
    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);
    var center = select(centerB, centerA, distA < distB);
    let localVec = uvScaled - center;

    let gridUV = center / gridSize / aspectVec;
    let centerScreen = gridUV * aspectVec;
    let mouseScreen = mousePos * aspectVec;
    let distToMouse = distance(centerScreen, mouseScreen);

    let melt = 1.0 - smoothstep(meltRadius, meltRadius + softness + 0.01, distToMouse);

    // Honey thickness
    let len = length(localVec);
    let bulge = localVec * (1.0 - len * 0.8);
    let solidUV = (center + bulge) / gridSize / aspectVec;
    let rim = smoothstep(0.4, 0.5, len);
    let honeyThickness = max(0.05, (1.0 - len * 0.5) * (1.0 - rim * 0.5));

    // Temperature from thickness + mouse heat
    var temperature = mix(tempRangeLow, tempRangeHigh, honeyThickness);
    if (mouseDown > 0.5) {
        let mouseDistLocal = length(uv - mousePos);
        let mouseHeat = exp(-mouseDistLocal * mouseDistLocal * 400.0);
        temperature += mouseHeat * tempRangeHigh * 0.8;
    }

    // Blackbody color for honey
    let thermalColor = blackbodyColor(temperature);
    let thermalIntensity = 1.2;
    let honeyColor = thermalColor * thermalIntensity;

    // Melted state: fluid distortion
    let noiseVal = noise(uv * 10.0 + time * 0.5);
    let fluidUV = uv + vec2<f32>(noiseVal, -noiseVal) * 0.05 * distortStr;

    let colSolid = textureSampleLevel(readTexture, u_sampler, solidUV, 0.0);
    let colFluid = textureSampleLevel(readTexture, u_sampler, fluidUV, 0.0);

    // Blend honey blackbody with original
    let tintedSolid = mix(colSolid.rgb, honeyColor, 0.5);
    let tintedFluid = mix(colFluid.rgb, honeyColor * 0.7, 0.3);

    // Final mix
    let finalColor = mix(tintedSolid, tintedFluid, melt);

    // Alpha based on honey thickness (Beer-Lambert)
    let solidAlpha = mix(0.9, 0.82, melt * 0.5);
    let meltedAlpha = mix(0.45, 0.82, honeyThickness * 2.0);
    let alpha = mix(solidAlpha, meltedAlpha, melt);
    let absorption = exp(-honeyThickness * 1.4 * 0.3);
    let finalAlpha = mix(0.45, alpha, absorption);

    let display = toneMapACES(finalColor);

    textureStore(writeTexture, coord, vec4<f32>(display, clamp(finalAlpha, 0.35, 0.92)));
    textureStore(dataTextureA, coord, vec4<f32>(honeyColor, temperature / 15000.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
